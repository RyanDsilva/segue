// Owner: unit B. Gutter labels (decisions.md, phase 2 build rulings): the section name at
// 13pt, never below 12pt, a small second line for the repeat count or "(cont.)", top-aligned
// with the section. Laid out once per plan: they do not scale with the lyrics.

extension SectionLayout {
    /// Each labelled section's gutter labels at `gutter` width.
    static func gutters(
        for sections: [MeasuredSection],
        gutter: Double,
        style: LayoutStyle,
        measurer: Measurer,
    ) -> [Int: SectionGutters] {
        var result: [Int: SectionGutters] = [:]
        for section in sections where section.labelText != nil {
            func make(_ detail: MeasuredParagraph?) -> LabelLayout {
                label(
                    section.labelText,
                    detail: detail,
                    gutter: gutter,
                    style: style,
                    measurer: measurer,
                )
            }
            result[section.id] = SectionGutters(
                first: make(section.labelDetail),
                continuation: make(section.continuation),
            )
        }
        return result
    }

    /// The gutter label, top-aligned: the name on one line at `labelSize`, shrunk toward
    /// `minLabelSize` (never below) when the gutter is narrow, wrapped at words only when it
    /// still does not fit; then `detail` ("x2", "(cont.)") as a smaller second line.
    static func label(
        _ name: MeasuredParagraph?,
        detail: MeasuredParagraph?,
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
        var placed = wrap(name, size: size, width: gutter, measurer: measurer)
        if let detail {
            placed += wrap(detail, size: style.labelDetailSize, width: gutter, measurer: measurer)
        }
        var lines: [PlacedLine] = []
        var baseline = 0.0
        var bottom = 0.0
        for (index, line) in placed.enumerated() {
            let extents = measurer.metrics.extents(of: line.role)
            baseline = index == 0
                ? extents.inkTop * line.size
                : baseline + line.size * style.smallLineHeight
            lines.append(PlacedLine(text: line, baseline: baseline))
            bottom = baseline + extents.descent * line.size
        }
        return LabelLayout(lines: lines, height: bottom)
    }
}
