// Owner: unit B. Packs laid-out sections into columns and assembles the positioned plan.

/// A section (or a part of one) placed in a column.
struct Placement {
    var section: Int
    var units: Range<Int>
    var part: Int
    var y: Double
    var height: Double
}

/// Sections assigned to columns.
struct Packing {
    var columns: [[Placement]]

    var contentHeight: Double {
        columns.compactMap { $0.last.map { $0.y + $0.height } }.max() ?? 0
    }
}

/// Sections laid out on first use, so a fit trial that overflows stops laying out the rest
/// of the song. Not shared across threads (one per trial).
final class LaidSections {
    let count: Int
    private let make: (Int) -> LaidSection
    private var cache: [LaidSection?]

    init(count: Int, make: @escaping (Int) -> LaidSection) {
        self.count = count
        self.make = make
        cache = Array(repeating: nil, count: count)
    }

    var indices: Range<Int> {
        0 ..< count
    }

    subscript(index: Int) -> LaidSection {
        if let section = cache[index] {
            return section
        }
        let section = make(index)
        cache[index] = section
        return section
    }
}

/// Packs sections in reading order (down a column, then the next).
struct ColumnPacker {
    let sections: LaidSections
    /// Vertical padding inside a block, and the gap between blocks.
    let inset: Double
    let gap: Double

    /// Height of a block showing `units` of section `index` (`part` 0 carries the head;
    /// every part carries a gutter label, `(cont.)` after the first).
    func height(_ index: Int, _ units: Range<Int>, part: Int) -> Double {
        let section = sections[index]
        let body = section.units[units].reduce(0) { $0 + $1.height }
        let head = part == 0 ? section.headHeight : 0
        var height = inset + head + body + inset
        let gutter = gutter(index, part: part)
        if !gutter.lines.isEmpty {
            height = max(height, labelTop(index, units, part: part) + gutter.height + inset)
        }
        return height
    }

    /// The gutter label of `part` of section `index`.
    func gutter(_ index: Int, part: Int) -> LabelLayout {
        part == 0 ? sections[index].gutter : sections[index].continuationGutter
    }

    /// Where the gutter label's ink starts, from the block's top: level with the block's
    /// first ink (a cue box, the collapsed line, the first chord or lyric), so the label
    /// reads as the section's heading (mockup C, labels top-aligned).
    func labelTop(_ index: Int, _ units: Range<Int>, part: Int) -> Double {
        let section = sections[index]
        if part == 0, let head = section.headInkTop {
            return inset + head
        }
        var top = part == 0 ? section.headHeight : 0
        for unit in section.units[units] {
            if let ink = unit.inkTop {
                return inset + top + ink
            }
            top += unit.height
        }
        return inset
    }

    /// Greedy fill with `capacity` per column. Sections move whole to the next column; with
    /// `split`, a section that does not fit is broken between units (preferring stanza
    /// breaks). Nil when it needs more than `columns` columns.
    /// With `strict`, a section whose tab/grid line had to be broken fails the pack; without
    /// `allowWrap`, so does a section with a wrapped lyric line.
    func pack(
        columns: Int,
        capacity: Double,
        split: Bool,
        strict: Bool = false,
        allowWrap: Bool = true,
    ) -> Packing? {
        var result: [[Placement]] = [[]]
        var used = 0.0
        for index in sections.indices {
            if strict, sections[index].brokeVerbatim {
                return nil
            }
            if !allowWrap, sections[index].wrapped {
                return nil
            }
            var remaining = 0 ..< sections[index].units.count
            var part = 0
            while true {
                let offset = used > 0 ? used + gap : 0
                let whole = height(index, remaining, part: part)
                if offset + whole <= capacity {
                    result[result.count - 1].append(Placement(
                        section: index, units: remaining, part: part, y: offset, height: whole,
                    ))
                    used = offset + whole
                    break
                }
                if split, let count = splitCount(index, remaining, part, room: capacity - offset) {
                    let units = remaining.lowerBound ..< remaining.lowerBound + count
                    let height = height(index, units, part: part)
                    result[result.count - 1].append(Placement(
                        section: index, units: units, part: part, y: offset, height: height,
                    ))
                    remaining = Self.dropBreaks(
                        sections[index],
                        units.upperBound ..< remaining.upperBound,
                    )
                    part += 1
                    if remaining.isEmpty {
                        used = offset + height
                        break
                    }
                } else if used == 0 {
                    return nil
                }
                guard result.count < columns else { return nil }
                result.append([])
                used = 0
            }
        }
        return Packing(columns: result)
    }

    /// Everything in one column per `columns`, balanced: the smallest capacity that
    /// packs whole sections into `columns` (scrolled plans).
    func balanced(columns: Int) -> Packing {
        let single = pack(columns: 1, capacity: .infinity, split: false) ?? Packing(columns: [[]])
        guard columns > 1, sections.count > 1 else { return single }
        var low = sections.indices.map { height($0, 0 ..< sections[$0].units.count, part: 0) }
            .max() ?? 0
        var high = single.contentHeight
        while high - low > 0.5 {
            let mid = (low + high) / 2
            if pack(columns: columns, capacity: mid, split: false) != nil {
                high = mid
            } else {
                low = mid
            }
        }
        return pack(columns: columns, capacity: high, split: false) ?? single
    }

    /// How many units of `remaining` fit in `room` (at least one, fewer than all), cut at a
    /// stanza break when one is in the latter half.
    private func splitCount(_ index: Int, _ remaining: Range<Int>, _ part: Int, room: Double)
        -> Int?
    {
        let units = sections[index].units
        var best: Int?
        guard remaining.count > 1 else { return nil }
        for count in 1 ..< remaining.count {
            let range = remaining.lowerBound ..< remaining.lowerBound + count
            if units[range.upperBound - 1].isBreak || units[range.upperBound].keepsWithPrevious {
                continue
            }
            guard height(index, range, part: part) <= room else { break }
            best = count
        }
        guard let best else { return nil }
        let atBreak = (best / 2 ..< best).reversed().first { count in
            count > 0 && units[remaining.lowerBound + count].isBreak
        }
        return atBreak ?? best
    }

    private static func dropBreaks(_ section: LaidSection, _ range: Range<Int>) -> Range<Int> {
        var lower = range.lowerBound
        while lower < range.upperBound, section.units[lower].isBreak {
            lower += 1
        }
        return lower ..< range.upperBound
    }
}
