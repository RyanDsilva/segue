// P9-3 9.2: the member header laid out at one lyric size, above a segment's first pass.

extension SectionLayout {
    /// The header at the head's top: an optional rule, the title line, the transition and
    /// change line in one callout, then the member's notes.
    func memberHeader(_ measured: MeasuredHeader) -> PlacedMemberHeader {
        let titleSize = context.lyricSize * PlacedMemberHeader.titleScale
        var y = measured.rule ? titleSize * 0.7 : 0
        let titleBand = titleSize * style.lineHeight
        let titleBaseline = y + SizeContext.baseline(
            band: titleBand,
            size: titleSize,
            extents: measurer.metrics.extents(of: .sectionLabel),
        )
        y += titleBand
        let changesSize = style.cueSize * 0.85
        let (callout, changesBaseline) = headerCallout(
            measured,
            y: y + titleSize * 0.2,
            changesSize: changesSize,
        )
        if let callout {
            y = callout.y + callout.height
        }
        var notes: [PlacedLine] = []
        if !measured.notes.isEmpty {
            let size = style.noteSize
            let band = size * style.smallLineHeight
            let baseline = SizeContext.baseline(
                band: band, size: size, extents: context.lyricExtents,
            )
            y += style.calloutSpacing
            for paragraph in measured.notes {
                for line in wrap(paragraph, size: size, width: headerWidth) {
                    notes.append(PlacedLine(text: line, baseline: y + baseline))
                    y += band
                }
            }
        }
        return PlacedMemberHeader(
            header: measured.header,
            height: y + titleSize * 0.55,
            hasRule: measured.rule,
            titleSize: titleSize,
            titleBaseline: titleBaseline,
            callout: callout,
            changesBaseline: changesBaseline,
            changesSize: changesSize,
            notes: notes,
        )
    }

    /// The transition (wrapped, in the cue style) with the change line under it; x from the
    /// column's left edge.
    private func headerCallout(
        _ measured: MeasuredHeader,
        y: Double,
        changesSize: Double,
    ) -> (PlacedCue?, Double?) {
        let changeLine = measured.header.changeLine
        guard measured.transition != nil || !changeLine.isEmpty else { return (nil, nil) }
        let padding = style.cuePadding
        let size = style.cueSize
        let band = size * style.smallLineHeight
        let baseline = SizeContext.baseline(
            band: band, size: size, extents: measurer.metrics.extents(of: .cue),
        )
        let inner = max(1, headerWidth - 2 * padding.width)
        let lines = measured.transition.map { wrap($0, size: size, width: inner) } ?? []
        let placed = lines.enumerated().map { index, text in
            var text = text
            text.x += padding.width
            return PlacedLine(
                text: text,
                baseline: padding.height + Double(index) * band + baseline,
            )
        }
        var height = Double(lines.count) * band + 2 * padding.height
        var widest = lines.map { $0.x + $0.width }.max() ?? 0
        var changesBaseline: Double?
        if !changeLine.isEmpty {
            let changesBand = changesSize * style.smallLineHeight
            let top = height - padding.height
            changesBaseline = top + SizeContext.baseline(
                band: changesBand, size: changesSize, extents: measurer.metrics.extents(of: .note),
            )
            height += changesBand
            let width = measurer.metrics.width(of: changeLine, role: .note, size: changesSize)
            widest = max(widest, min(width, inner))
        }
        let callout = PlacedCue(
            text: [measured.header.transition, changeLine.isEmpty ? nil : changeLine]
                .compactMap(\.self).joined(separator: ". "),
            y: y,
            height: height,
            x: 0,
            width: widest + 2 * padding.width,
            lines: placed,
        )
        return (callout, changesBaseline)
    }
}
