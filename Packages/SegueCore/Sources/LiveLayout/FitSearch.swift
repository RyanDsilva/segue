// Owner: unit B. Auto-fit steps 3-6: the largest lyric size that fits, its column count,
// the scroll fallback at the minimum, and zoom. Build rulings (decisions.md, phase 2):
// a layout without wrapped lyric lines wins whenever it reaches a comfortable size
// (`comfortableSize`), and the column count leans toward `preferredColumns` (2).

/// One candidate layout: a size, a column count and how sections were packed.
struct Candidate {
    var size: Double
    var columns: Int
    var sections: LaidSections
    var packing: Packing

    /// A placed lyric line wraps.
    var wraps: Bool {
        packing.columns.joined().contains { sections[$0.section].wrapped }
    }
}

struct FitSearch {
    let request: LayoutRequest
    let song: MeasuredSong
    let measurer: Measurer
    /// The song's label gutter: wide enough for its longest label name on one line at
    /// `labelSize`, between `gutterWidth` and `maxGutterWidth`.
    let gutterWidth: Double
    /// Gutter labels by section id, laid out once (they do not scale with the lyrics).
    let gutters: [Int: SectionGutters]

    init(request: LayoutRequest, song: MeasuredSong, measurer: Measurer) {
        self.request = request
        self.song = song
        self.measurer = measurer
        let style = request.style
        let widest = song.sections.compactMap(\.labelText).map { paragraph in
            let advance = paragraph.words.reduce(0) { $0 + $1.width }
            let trailing = paragraph.words.last.map { $0.width - $0.inkWidth } ?? 0
            return (advance - trailing) * style.labelSize / referenceSize
        }.max() ?? 0
        let ceiling = max(style.maxGutterWidth, style.gutterWidth)
        gutterWidth = min(max(style.gutterWidth, widest.rounded(.up)), ceiling)
        gutters = SectionLayout.gutters(
            for: song.sections,
            gutter: gutterWidth,
            style: style,
            measurer: measurer,
        )
    }

    private var style: LayoutStyle {
        request.style
    }

    private var minSize: Double {
        max(1, request.minLyricSize)
    }

    private var maxSize: Double {
        max(style.maxLyricSize, minSize)
    }

    /// The size from which a layout without wrapping always wins (decisions.md, "Auto-fit
    /// wrapping (revised)"): max(28pt, 1.25 x the user minimum), capped at the largest size.
    var comfortableSize: Double {
        min(
            maxSize,
            max(style.comfortableLyricSize, style.comfortableMinimumFactor * request.minLyricSize),
        )
    }

    func plan() -> LayoutPlan {
        let base = fitted()
        let zoom = min(max(request.zoom.isFinite ? request.zoom : 1, 0.25), 4)
        guard let base else {
            let size = max(minSize, minSize * zoom)
            let fit: LayoutFit = size > minSize ? .scrollsZoomed : .scrollsAtMinimum
            return assemble(scrolled(size: size), fit: fit)
        }
        guard zoom != 1 else {
            return assemble(base, fit: .fits)
        }
        let size = max(minSize, base.size * zoom)
        let order = [base.columns] + columnOptions.filter { $0 != base.columns }
        for columns in order {
            if let candidate = candidate(
                size: size,
                columns: columns,
                split: false,
                allowWrap: true,
            )
                ?? candidate(size: size, columns: columns, split: true, allowWrap: true)
            {
                return assemble(candidate, fit: .fits)
            }
        }
        return assemble(scrolled(size: size), fit: .scrollsZoomed)
    }

    /// Column counts to try: forced, else 1...max limited by the minimum column width.
    var columnOptions: [Int] {
        if let forced = request.columns {
            return [min(max(forced, 1), max(style.maxColumns, 1))]
        }
        return (1 ... max(style.maxColumns, 1)).filter { count in
            count == 1 || columnWidth(count) >= style.minColumnWidth
        }
    }

    func columnWidth(_ columns: Int) -> Double {
        let gaps = Double(columns - 1) * style.columnGap
        return (request.viewport.width - gaps) / Double(columns)
    }

    /// Steps 3-4: per column count, binary search the largest stepped size that fits. The
    /// chosen layout without a wrapped lyric line wins when it reaches `comfortableSize`;
    /// below that the larger of it and the chosen layout with wrapping allowed wins.
    /// Within each, sections stay whole when any layout allows it; only then are they split
    /// between columns.
    private func fitted() -> Candidate? {
        let steps = Int(((maxSize - minSize) / style.sizeStep).rounded(.down))
        var unwrapped: Candidate?
        var wrapping: Candidate?
        for split in [false, true] {
            var plain: [Int: Candidate] = [:]
            var wrapped: [Int: Candidate] = [:]
            for columns in columnOptions {
                // The largest layout overall; nothing without wrapping can be larger, and
                // when it has no wrapped line it is also the largest without.
                guard let any = largest(
                    columns: columns, split: split, allowWrap: true, steps: steps, through: steps,
                ) else { continue }
                wrapped[columns] = any
                plain[columns] = any.wraps ? largest(
                    columns: columns,
                    split: split,
                    allowWrap: false,
                    steps: steps,
                    through: step(of: any.size) - 1,
                ) : any
            }
            unwrapped = unwrapped ?? choose(plain)
            wrapping = wrapping ?? choose(wrapped)
        }
        guard let unwrapped else { return wrapping }
        guard let wrapping, unwrapped.size < comfortableSize - 1e-9 else { return unwrapped }
        return wrapping.size > unwrapped.size ? wrapping : unwrapped
    }

    /// The size step index of `size`.
    private func step(of size: Double) -> Int {
        size >= maxSize ? Int(((maxSize - minSize) / style.sizeStep).rounded(.down))
            : Int(((size - minSize) / style.sizeStep).rounded())
    }

    /// The column bias (decisions.md, "Columns"): the preferred count (2) when it fits,
    /// unless fewer columns give a size more than `wrapTolerance` larger; otherwise the
    /// largest size, ties to fewer columns. More columns than preferred are therefore only
    /// used when the preferred count does not fit at all.
    func choose(_ found: [Int: Candidate]) -> Candidate? {
        func largest(_ candidates: some Sequence<Candidate>) -> Candidate? {
            candidates.reduce(nil) { best, candidate in
                guard let best else { return candidate }
                if candidate.size > best.size
                    || (candidate.size == best.size && candidate.columns < best.columns)
                {
                    return candidate
                }
                return best
            }
        }
        // A candidate that left columns empty is only a narrower layout of fewer columns.
        guard let preferred = found[style.preferredColumns],
              preferred.packing.columns.count == preferred.columns
        else {
            return largest(found.values)
        }
        let fewer = largest(found.values.filter { $0.columns < preferred.columns })
        if let fewer, fewer.size > preferred.size * (1 + style.wrapTolerance) {
            return fewer
        }
        return preferred
    }

    private func largest(
        columns: Int,
        split: Bool,
        allowWrap: Bool,
        steps: Int,
        through last: Int,
    ) -> Candidate? {
        func size(_ step: Int) -> Double {
            step == steps ? maxSize : minSize + Double(step) * style.sizeStep
        }
        func trial(_ step: Int) -> Candidate? {
            candidate(size: size(step), columns: columns, split: split, allowWrap: allowWrap)
        }
        guard last >= 0, var best = trial(0) else {
            return nil
        }
        var low = 0
        var high = last
        if last == 0 {
            return best
        }
        if let top = trial(last) {
            return top
        }
        // Invariant: `low` fits, `high` does not.
        while high - low > 1 {
            let mid = (low + high) / 2
            if let found = trial(mid) {
                best = found
                low = mid
            } else {
                high = mid
            }
        }
        return best
    }

    /// The layout at `size` in `columns` if everything fits the viewport (and, without
    /// `allowWrap`, no lyric line wraps).
    func candidate(size: Double, columns: Int, split: Bool, allowWrap: Bool) -> Candidate? {
        let sections = laid(size: size, columns: columns)
        let packer = packer(sections, size: size)
        guard let packing = packer.pack(
            columns: columns,
            capacity: request.viewport.height,
            split: split,
            strict: true,
            allowWrap: allowWrap,
        ) else { return nil }
        return Candidate(size: size, columns: columns, sections: sections, packing: packing)
    }

    /// Step 5: nothing fits; one column (or the forced count), balanced, scrolled.
    private func scrolled(size: Double) -> Candidate {
        let columns = request.columns.map { _ in columnOptions[0] } ?? 1
        let sections = laid(size: size, columns: columns)
        let packing = packer(sections, size: size).balanced(columns: columns)
        return Candidate(size: size, columns: columns, sections: sections, packing: packing)
    }

    private func laid(size: Double, columns: Int) -> LaidSections {
        let context = SizeContext(style: style, lyricSize: size, metrics: measurer.metrics)
        let width = max(1, columnWidth(columns) - gutterWidth - style.gutterGap)
        let layout = SectionLayout(
            context: context,
            width: width,
            gutters: gutters,
            measurer: measurer,
        )
        let song = song
        let hasNotes = !song.notes.isEmpty
        return LaidSections(count: song.sections.count + (hasNotes ? 1 : 0)) { index in
            if hasNotes {
                return index == 0 ? layout.notes(song.notes) : layout.lay(song.sections[index - 1])
            }
            return layout.lay(song.sections[index])
        }
    }

    private func packer(_ sections: LaidSections, size: Double) -> ColumnPacker {
        ColumnPacker(
            sections: sections,
            inset: size * style.blockInset,
            gap: size * style.sectionSpacing,
        )
    }

    private func assemble(_ candidate: Candidate, fit: LayoutFit) -> LayoutPlan {
        PlanAssembly(
            candidate: candidate,
            packer: packer(candidate.sections, size: candidate.size),
            request: request,
            columnWidth: columnWidth(candidate.columns),
            gutterWidth: gutterWidth,
            lineCount: song.lineCount,
        ).plan(fit: fit)
    }
}
