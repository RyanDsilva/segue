// Owner: unit B. Auto-fit steps 3-6: the largest lyric size that fits, its column count,
// the scroll fallback at the minimum, and zoom.

/// One candidate layout: a size, a column count and how sections were packed.
struct Candidate {
    var size: Double
    var columns: Int
    var sections: LaidSections
    var packing: Packing
}

struct FitSearch {
    let request: LayoutRequest
    let song: MeasuredSong
    let measurer: Measurer

    private var style: LayoutStyle {
        request.style
    }

    private var minSize: Double {
        max(1, request.minLyricSize)
    }

    private var maxSize: Double {
        max(style.maxLyricSize, minSize)
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
            if let candidate = candidate(size: size, columns: columns, split: false)
                ?? candidate(size: size, columns: columns, split: true)
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

    /// Steps 3-4: per column count, binary search the largest stepped size that fits; the
    /// largest size wins and ties go to fewer columns. Sections stay whole when any layout
    /// allows it; only then are they split between columns.
    private func fitted() -> Candidate? {
        let steps = Int(((maxSize - minSize) / style.sizeStep).rounded(.down))
        for split in [false, true] {
            var best: Candidate?
            for columns in columnOptions {
                guard let found = largest(columns: columns, split: split, steps: steps) else {
                    continue
                }
                if found.size > (best?.size ?? 0) {
                    best = found
                }
            }
            if let best {
                return best
            }
        }
        return nil
    }

    private func largest(columns: Int, split: Bool, steps: Int) -> Candidate? {
        func size(_ step: Int) -> Double {
            step == steps ? maxSize : minSize + Double(step) * style.sizeStep
        }
        guard var best = candidate(size: minSize, columns: columns, split: split) else {
            return nil
        }
        var low = 0
        var high = steps
        if let top = candidate(size: maxSize, columns: columns, split: split) {
            return top
        }
        // Invariant: `low` fits, `high` does not.
        while high - low > 1 {
            let mid = (low + high) / 2
            if let found = candidate(size: size(mid), columns: columns, split: split) {
                best = found
                low = mid
            } else {
                high = mid
            }
        }
        return best
    }

    /// The layout at `size` in `columns` if everything fits the viewport.
    func candidate(size: Double, columns: Int, split: Bool) -> Candidate? {
        let sections = laid(size: size, columns: columns)
        let packer = packer(sections, size: size)
        guard let packing = packer.pack(
            columns: columns,
            capacity: request.viewport.height,
            split: split,
            strict: true,
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
        let width = max(1, columnWidth(columns) - style.gutterWidth - style.gutterGap)
        let layout = SectionLayout(context: context, width: width, measurer: measurer)
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
            lineCount: song.lineCount,
        ).plan(fit: fit)
    }
}
