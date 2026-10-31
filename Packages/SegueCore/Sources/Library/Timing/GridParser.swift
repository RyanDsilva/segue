// P8-7a (docs/phases/8-workstreams/P8-7-time-model-and-fills.md section 5.5, R167 Q4).
// ChordPro grids (`{start_of_grid}` ... `{end_of_grid}`) read as timed chords. Pure.

import ChordPro
import Editing
import Foundation
import MusicTheory

/// A grid section's chords in played order (repeats, voltas and `%` expanded), timed in
/// ticks from the grid's first bar.
public struct GridChart: Sendable, Hashable {
    public struct Chord: Sendable, Hashable {
        /// As written ("G7", "N.C.").
        public var token: String
        /// 0-based among the grid's `.chord` chords in written, unexpanded order; nil for
        /// `N.C.`.
        public var ordinal: Int?
        /// The grid line it is written on.
        public var line: BlockPath
        /// Ticks from the grid's first bar.
        public var onset: Int
        public var length: Int

        public var isSilent: Bool {
            ordinal == nil
        }
    }

    public var chords: [Chord]
    /// Ticks before the first chord (cells that continue the chord before the grid).
    public var leadingTicks: Int
    public var totalTicks: Int

    public static let empty = Self(chords: [], leadingTicks: 0, totalTicks: 0)
}

public enum GridParser {
    /// Whether `section` is a ChordPro grid (a verbatim `grid` section).
    public static func isGrid(_ section: RenderSection) -> Bool {
        guard let kind = section.kind, DirectiveLine.isVerbatimSection(kind) else { return false }
        if case let .custom(name) = kind {
            return name.lowercased() == "grid"
        }
        return false
    }

    /// The grid's `.chord` chords in written order (what `ChordAnchors` anchors), each with
    /// its line. Empty for any other section.
    public static func writtenChords(_ section: RenderSection)
        -> [(token: String, line: BlockPath)]
    {
        guard isGrid(section) else { return [] }
        var result: [(String, BlockPath)] = []
        for (text, path) in lines(of: section) {
            for measure in measures(of: text) {
                for token in measure.tokens {
                    for name in chordNames(in: token) where isChord(name) {
                        result.append((name, path))
                    }
                }
            }
        }
        return result
    }

    /// The grid's chords timed in `meter` (one measure is one bar). `header` is the grid's
    /// start value: a shape (`1+4x2+4`, or `shape="1+4x2+4"`) gives the cells per measure;
    /// without one each measure's cells are its tokens.
    public static func parse(_ section: RenderSection, header: String?, meter: Meter) -> GridChart {
        guard isGrid(section) else { return .empty }
        let cellsPerMeasure = header.flatMap(shapeCells)
        var raw: [RawMeasure] = []
        var ordinal = 0
        for (text, path) in lines(of: section) {
            for measure in measures(of: text) {
                raw.append(rawMeasure(
                    measure,
                    line: path,
                    cells: cellsPerMeasure,
                    bar: meter.ticksPerBar,
                    ordinal: &ordinal,
                ))
            }
        }
        let played = expand(resolvePercents(raw))
        return timed(played, bar: meter.ticksPerBar)
    }

    // MARK: Lines and measures

    /// The section's verbatim lines with their paths.
    private static func lines(of section: RenderSection) -> [(String, BlockPath)] {
        section.items.compactMap { item in
            if case let .verbatim(text, path) = item {
                return (text, path)
            }
            return nil
        }
    }

    /// A bar token's meaning.
    struct Bar {
        var startsRepeat = false
        var endsRepeat = false
        var volta: Int?
    }

    /// The tokens between two bar lines, with the bars around them.
    struct Measure {
        var tokens: [String]
        var before: Bar
        var after: Bar
    }

    /// `|`, `||`, `|.`, `|:`, `:|`, `:|:`, voltas `|1` and `:|2`; nil for anything else.
    static func bar(_ token: String) -> Bar? {
        switch token {
        case "|", "|.", "||": return Bar()
        case "|:", "||:": return Bar(startsRepeat: true)
        case ":|", ":||": return Bar(endsRepeat: true)
        case ":|:", ":||:": return Bar(startsRepeat: true, endsRepeat: true)
        default:
            var rest = Substring(token)
            var bar = Bar()
            if rest.hasPrefix(":") {
                bar.endsRepeat = true
                rest = rest.dropFirst()
            }
            guard rest.hasPrefix("|") else { return nil }
            rest = rest.dropFirst()
            if rest.hasSuffix(".") {
                rest = rest.dropLast()
            }
            guard let volta = Int(rest), (1 ... 9).contains(volta) else { return nil }
            bar.volta = volta
            return bar
        }
    }

    /// The measures of one grid line: margin text before the first bar and after the last is
    /// ignored, as is a strum line (`|S`).
    static func measures(of line: String) -> [Measure] {
        let tokens = line.split(whereSeparator: \.isWhitespace).map(String.init)
        guard !tokens.contains(where: { $0.hasPrefix("|S") || $0.hasPrefix("|s") }) else {
            return []
        }
        var result: [Measure] = []
        var open: (bar: Bar, tokens: [String])?
        for token in tokens {
            if let bar = bar(token) {
                if let current = open, !current.tokens.isEmpty {
                    result.append(Measure(tokens: current.tokens, before: current.bar, after: bar))
                } else if let current = open, current.tokens.isEmpty {
                    // Two bar tokens in a row (`:| |2`): their meanings merge.
                    var merged = bar
                    merged.startsRepeat = merged.startsRepeat || current.bar.startsRepeat
                    merged.volta = merged.volta ?? current.bar.volta
                    if current.bar.endsRepeat, var last = result.popLast() {
                        last.after.endsRepeat = true
                        result.append(last)
                    }
                    open = (merged, [])
                    continue
                }
                open = (bar, [])
            } else if open != nil {
                open?.tokens.append(token)
            }
        }
        return result
    }

    /// `G~C` is two chords sharing a cell.
    private static func chordNames(in token: String) -> [String] {
        token.split(separator: "~", omittingEmptySubsequences: true).map(String.init)
    }

    private static func isChord(_ name: String) -> Bool {
        if case .chord = ChordToken(parsing: name) {
            return true
        }
        return false
    }

    private static func isSilent(_ name: String) -> Bool {
        if case .noChord = ChordToken(parsing: name) {
            return true
        }
        return false
    }

    /// The cells per measure of a shape: `1+4x2+4`, `4x2`, or `shape="..."` (the number
    /// after the `x`).
    public static func shapeCells(_ header: String) -> Int? {
        var text = header.trimmingCharacters(in: .whitespaces)
        if let range = text.range(of: "shape=") {
            text = String(text[range.upperBound...])
                .trimmingCharacters(in: CharacterSet(charactersIn: "\"' "))
            text = String(text.prefix { !$0.isWhitespace && $0 != "\"" && $0 != "'" })
        }
        let parts = text.split(separator: "+", omittingEmptySubsequences: false)
        guard let core = parts.first(where: { $0.contains("x") }) else { return nil }
        let sides = core.split(separator: "x")
        guard sides.count == 2, Int(sides[0]) != nil, let cells = Int(sides[1]), cells > 0
        else { return nil }
        return cells
    }

    // MARK: Raw measures

    /// One event in a measure: a chord (or `N.C.`) starting `offset` ticks into the bar.
    struct Event: Hashable {
        var offset: Int
        var token: String
        var ordinal: Int?
        var line: BlockPath
    }

    struct RawMeasure {
        var events: [Event]
        var startsRepeat: Bool
        var endsRepeat: Bool
        var volta: Int?
        /// `%` (1) or `%%` (2): repeats that many measures before it.
        var repeats: Int
        /// Only continuation cells (`.`, `/`, text): `%%` may consume it.
        var isContinuation: Bool
    }

    private static func rawMeasure(
        _ measure: Measure,
        line: BlockPath,
        cells shapeCells: Int?,
        bar: Int,
        ordinal: inout Int,
    ) -> RawMeasure {
        var raw = RawMeasure(
            events: [],
            startsRepeat: measure.before.startsRepeat,
            endsRepeat: measure.after.endsRepeat,
            volta: measure.before.volta,
            repeats: 0,
            isContinuation: true,
        )
        if measure.tokens.first == "%%" {
            raw.repeats = 2
            raw.isContinuation = false
            return raw
        }
        if measure.tokens.first == "%" {
            raw.repeats = 1
            raw.isContinuation = false
            return raw
        }
        let cells = max(shapeCells ?? 0, measure.tokens.count, 1)
        for (cell, token) in measure.tokens.enumerated() {
            let names = chordNames(in: token).filter { isChord($0) || isSilent($0) }
            guard !names.isEmpty else { continue }
            raw.isContinuation = false
            let start = cell * bar / cells
            let end = (cell + 1) * bar / cells
            for (index, name) in names.enumerated() {
                var event = Event(
                    offset: start + index * (end - start) / names.count,
                    token: name,
                    ordinal: nil,
                    line: line,
                )
                if isChord(name) {
                    event.ordinal = ordinal
                    ordinal += 1
                }
                raw.events.append(event)
            }
        }
        return raw
    }

    /// `%` copies the measure before it, `%%` the two before (and takes the next measure
    /// when that one only continues).
    private static func resolvePercents(_ raw: [RawMeasure]) -> [RawMeasure] {
        var result: [RawMeasure] = []
        var index = 0
        while index < raw.count {
            var measure = raw[index]
            switch measure.repeats {
            case 1 where !result.isEmpty:
                measure.events = result[result.count - 1].events
                result.append(measure)
            case 2 where result.count >= 2:
                var first = measure
                first.events = result[result.count - 2].events
                first.endsRepeat = false
                var second = measure
                second.events = result[result.count - 1].events
                second.startsRepeat = false
                second.volta = nil
                if index + 1 < raw.count, raw[index + 1].isContinuation {
                    second.endsRepeat = raw[index + 1].endsRepeat
                    index += 1
                }
                result += [first, second]
            default:
                measure.repeats = 0
                result.append(measure)
            }
            index += 1
        }
        return result
    }

    /// Repeats and voltas played out: `|: A | B |1 C :|2 D |` is A B C A B D.
    private static func expand(_ raw: [RawMeasure]) -> [RawMeasure] {
        var result: [RawMeasure] = []
        var start = 0
        var repeated = Set<Int>()
        var secondTime = false
        var index = 0
        while index < raw.count {
            let measure = raw[index]
            if measure.startsRepeat, !secondTime {
                start = index
            }
            if secondTime, measure.volta == 1 {
                // The first ending is skipped the second time through.
                let end = raw[index...].firstIndex(where: \.endsRepeat) ?? raw.count - 1
                repeated.insert(end)
                secondTime = false
                index = end + 1
                start = index
                continue
            }
            result.append(measure)
            if measure.endsRepeat, !repeated.contains(index), result.count < 4096 {
                repeated.insert(index)
                secondTime = true
                index = start
                continue
            }
            if measure.endsRepeat {
                secondTime = false
                start = index + 1
            }
            index += 1
        }
        return result
    }

    /// Each chord lasts until the next one starts (or the grid ends).
    private static func timed(_ measures: [RawMeasure], bar: Int) -> GridChart {
        var events: [(onset: Int, event: Event)] = []
        for (index, measure) in measures.enumerated() {
            for event in measure.events {
                events.append((index * bar + event.offset, event))
            }
        }
        let total = measures.count * bar
        var chords: [GridChart.Chord] = []
        for (index, entry) in events.enumerated() {
            let end = index + 1 < events.count ? events[index + 1].onset : total
            guard end > entry.onset else { continue }
            chords.append(GridChart.Chord(
                token: entry.event.token,
                ordinal: entry.event.ordinal,
                line: entry.event.line,
                onset: entry.onset,
                length: end - entry.onset,
            ))
        }
        return GridChart(chords: chords, leadingTicks: chords.first?.onset ?? 0, totalTicks: total)
    }
}
