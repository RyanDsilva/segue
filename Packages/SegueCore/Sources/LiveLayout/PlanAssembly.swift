// Owner: unit B, P8-2. Turns the chosen candidate into the fully positioned `LayoutPlan`.

struct PlanAssembly {
    let candidate: Candidate
    let packer: ColumnPacker
    let request: LayoutRequest
    let columnWidth: Double
    let gutterWidth: Double
    let lineCount: Int

    func plan(fit: LayoutFit) -> LayoutPlan {
        let style = request.style
        let columns = candidate.packing.columns.enumerated().map { index, placements in
            LayoutColumn(
                x: Double(index) * (columnWidth + style.columnGap),
                width: columnWidth,
                blocks: placements.map(block),
            )
        }
        let contentHeight = candidate.packing.contentHeight
        let viewport = request.viewport
        return LayoutPlan(
            lyricSize: candidate.size,
            chordSize: candidate.size * style.chordRatio,
            fit: fit,
            columns: columns,
            contentHeight: contentHeight,
            viewport: viewport,
            pageStops: Self.pageStops(
                columns: columns,
                contentHeight: contentHeight,
                viewport: viewport,
            ),
            lineCount: lineCount,
            gutterWidth: gutterWidth,
            passes: passes(),
        )
    }

    /// Each shown pass with where it landed: its first block's column and top, its last
    /// block's bottom, and its blocks' total height.
    private func passes() -> [PlanPass] {
        var passes: [PlanPass] = []
        for (column, placements) in candidate.packing.columns.enumerated() {
            for placement in placements {
                let section = candidate.sections[placement.section]
                guard !section.isNotes, let name = section.passName else { continue }
                let bottom = placement.y + placement.height
                if let last = passes.indices.last, passes[last].index == section.id {
                    passes[last].bottom = bottom
                    passes[last].weight += placement.height
                    continue
                }
                passes.append(PlanPass(
                    index: section.id,
                    position: section.position,
                    source: section.source,
                    name: name,
                    mode: section.mode,
                    tint: section.tint,
                    kind: section.kind,
                    column: column,
                    top: placement.y,
                    bottom: bottom,
                    weight: placement.height,
                ))
            }
        }
        return passes
    }

    private func block(_ placement: Placement) -> LayoutBlock {
        let section = candidate.sections[placement.section]
        let inset = packer.inset
        let isFirst = placement.part == 0
        var y = inset + (isFirst ? section.headHeight : 0)
        var rows: [LayoutRow] = []
        for unit in section.units[placement.units] {
            for row in unit.rows {
                var row = row
                row.y += y
                rows.append(row)
            }
            y += unit.height
        }
        let content: LayoutBlock.Content = section.isNotes ? .notes(rows) : .rows(rows)
        let top = packer.labelTop(placement.section, placement.units, part: placement.part)
        let labelLines = packer.gutter(placement.section, part: placement.part).lines.map { line in
            PlacedLine(text: line.text, baseline: line.baseline + top)
        }
        let continuation = section.name.map { "\($0) \(SongPreparation.continuationText)" }
        return LayoutBlock(
            id: section.id,
            source: section.source,
            pass: section.isNotes ? nil : section.id,
            label: isFirst ? section.label : continuation,
            isChorusLabel: section.isChorus,
            tint: section.tint,
            y: placement.y,
            height: placement.height,
            content: content,
            cues: isFirst ? section.cues.map { cue in
                var cue = cue
                cue.y += inset
                return cue
            } : [],
            labelLines: labelLines,
            part: placement.part,
        )
    }

    /// Scroll offsets for PgDn/PgUp: each page starts at the top of the last row that was
    /// fully visible on the previous page (one line of overlap); the last stop is the end.
    static func pageStops(columns: [LayoutColumn], contentHeight: Double, viewport: LayoutSize)
        -> [Double]
    {
        let overflow = max(0, contentHeight - viewport.height)
        guard overflow > 0 else { return [0] }
        let rows = columns.flatMap(\.blocks).flatMap { block in
            block.allRows.map { (top: block.y + $0.y, bottom: block.y + $0.y + $0.height) }
        }
        var stops = [0.0]
        var current = 0.0
        while current < overflow - 0.5 {
            let pageBottom = current + viewport.height
            // The last row fully on this page starts the next one.
            let overlap = rows
                .filter { $0.bottom <= pageBottom + 0.001 && $0.top > current + 1 }
                .map(\.top)
                .max()
            let next = min(overflow, overlap ?? current + viewport.height * 0.75)
            stops.append(next)
            current = next
        }
        return stops
    }
}

public extension LayoutBlock {
    /// Every row of the block, whatever its content.
    var allRows: [LayoutRow] {
        switch content {
        case let .notes(rows), let .rows(rows):
            rows
        }
    }
}
