// Owner: unit B. Turns the chosen candidate into the fully positioned `LayoutPlan`.

struct PlanAssembly {
    let candidate: Candidate
    let packer: ColumnPacker
    let request: LayoutRequest
    let columnWidth: Double
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
        )
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
        let content: LayoutBlock.Content = if section.isNotes {
            .notes(rows)
        } else if isFirst, let line = section.collapsedLine {
            .collapsed(line: line, differing: rows)
        } else {
            .rows(rows)
        }
        let firstBaseline = packer.firstBaseline(placement.section, placement.units)
        let labelLines = isFirst
            ? section.labelLines.map { line in
                PlacedLine(text: line.text, baseline: line.baseline + firstBaseline)
            }
            : []
        return LayoutBlock(
            id: section.id,
            label: isFirst ? section.label : nil,
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
            collapsedBaseline: isFirst ? section.collapsedBaseline.map { $0 + inset } : nil,
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
    /// Every row of the block, whatever its content (not the collapsed line).
    var allRows: [LayoutRow] {
        switch content {
        case let .collapsed(_, rows), let .notes(rows), let .rows(rows):
            rows
        }
    }
}
