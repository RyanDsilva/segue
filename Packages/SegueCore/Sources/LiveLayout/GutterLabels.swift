// Owner: unit B, P8-2. Gutter labels (decisions.md, phase 2 build rulings; R147): the section
// name at 13pt, never below 12pt, then on a first part the pass badge ("2 of 3") and the mode
// tag ("CHORDS"), or "(cont.)" on a continuation, top-aligned with the section. Laid out once
// per plan: they do not scale with the lyrics.

extension SectionLayout {
    /// Each labelled pass's gutter labels at `gutter` width.
    static func gutters(
        for sections: [MeasuredSection],
        gutter: Double,
        style: LayoutStyle,
        measurer: Measurer,
    ) -> [Int: SectionGutters] {
        var result: [Int: SectionGutters] = [:]
        for section in sections where section.labelText != nil {
            func make(_ extras: [MeasuredParagraph?]) -> LabelLayout {
                label(
                    section.labelText,
                    extras: extras.compactMap(\.self),
                    gutter: gutter,
                    style: style,
                    measurer: measurer,
                )
            }
            result[section.id] = SectionGutters(
                first: make([section.badge, section.modeTag]),
                continuation: make([section.continuation]),
            )
        }
        return result
    }

    /// The gutter label, top-aligned: the name on one line at `labelSize`, shrunk toward
    /// `minLabelSize` (never below) when the gutter is narrow, wrapped at words only when it
    /// still does not fit; then each of `extras` below it: "(cont.)" as a smaller line, the
    /// pass badge in its box and the mode tag `gutterLineGap` below the line above.
    static func label(
        _ name: MeasuredParagraph?,
        extras: [MeasuredParagraph],
        gutter: Double,
        style: LayoutStyle,
        measurer: Measurer,
    ) -> LabelLayout {
        guard let name, !name.words.isEmpty else { return .empty }
        let full = name.words.reduce(0) { $0 + $1.width } - (name.words.last.map {
            $0.width - $0.inkWidth
        } ?? 0)
        var size = style.labelSize
        if full * size / referenceSize > gutter {
            let fitting = ((gutter * referenceSize / full) * 2).rounded(.down) / 2
            size = max(style.minLabelSize, min(size, fitting))
        }
        var stack = GutterStack()
        for (index, line) in wrap(name, size: size, width: gutter, measurer: measurer)
            .enumerated()
        {
            let extents = measurer.metrics.extents(of: line.role)
            let step = size * style.smallLineHeight
            stack.baseline = index == 0 ? extents.inkTop * line.size : stack.baseline + step
            stack.lines.append(PlacedLine(text: line, baseline: stack.baseline))
            stack.bottom = stack.baseline + extents.descent * line.size
        }
        for extra in extras {
            stack.append(extra, gutter: gutter, style: style, measurer: measurer)
        }
        return LabelLayout(lines: stack.lines, height: stack.bottom)
    }
}

/// The gutter's lines as they are stacked: baselines from the first line's ink top, and how
/// far the last one reaches.
private struct GutterStack {
    var lines: [PlacedLine] = []
    var baseline = 0.0
    var bottom = 0.0

    /// One line under the name: the pass badge in its box and the mode tag
    /// `gutterLineGap` below the line above, "(cont.)" one small line down.
    mutating func append(
        _ extra: MeasuredParagraph,
        gutter: Double,
        style: LayoutStyle,
        measurer: Measurer,
    ) {
        let extents = measurer.metrics.extents(of: extra.role)
        func wrap(_ size: Double, _ width: Double) -> [PlacedText] {
            SectionLayout.wrap(extra, size: size, width: width, measurer: measurer)
        }
        switch extra.role {
        case .passBadge:
            let padding = style.passBadgePadding
            let size = style.passBadgeSize
            for var line in wrap(size, max(1, gutter - 2 * padding.width)) {
                line.x += padding.width
                baseline = bottom + style.gutterLineGap + padding.height + extents.ascent * size
                lines.append(PlacedLine(text: line, baseline: baseline))
                bottom = baseline + extents.descent * size + padding.height
            }
        case .modeTag:
            let size = style.modeTagSize
            for line in wrap(size, gutter) {
                baseline = bottom + style.gutterLineGap + extents.inkTop * size
                lines.append(PlacedLine(text: line, baseline: baseline))
                bottom = baseline + extents.descent * size
            }
        default:
            let size = style.labelDetailSize
            for line in wrap(size, gutter) {
                baseline += size * style.smallLineHeight
                lines.append(PlacedLine(text: line, baseline: baseline))
                bottom = baseline + extents.descent * size
            }
        }
    }
}
