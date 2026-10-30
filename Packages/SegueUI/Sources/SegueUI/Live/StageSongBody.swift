#if os(macOS)
    import LiveLayout
    import SwiftUI

    /// Draws a `LayoutPlan` exactly as positioned: every run at its x and baseline, in the
    /// face `StageTypography` gives its role, at the plan's sizes. Nothing is re-flowed here,
    /// so what is drawn is what auto-fit measured.
    struct StagePlanView: View, Equatable {
        let plan: LayoutPlan
        var style: LayoutStyle = .stage

        var body: some View {
            ZStack(alignment: .topLeading) {
                Color.clear
                    .frame(width: plan.viewport.width, height: max(plan.contentHeight, 1))
                ForEach(plan.columns.indices, id: \.self) { index in
                    let column = plan.columns[index]
                    ForEach(column.blocks) { block in
                        StageBlockView(block: block, column: column, plan: plan, style: style)
                            .offset(x: column.x, y: block.y)
                    }
                }
            }
            .frame(
                width: plan.viewport.width,
                height: max(plan.contentHeight, 1),
                alignment: .topLeading,
            )
            .accessibilityElement(children: .contain)
        }
    }

    /// One section (or the notes block): tint, gutter label, rows and cue callouts.
    private struct StageBlockView: View {
        let block: LayoutBlock
        let column: LayoutColumn
        let plan: LayoutPlan
        let style: LayoutStyle

        private var lyricOrigin: Double {
            plan.gutterWidth + style.gutterGap
        }

        var body: some View {
            ZStack(alignment: .topLeading) {
                Color.clear.frame(width: column.width, height: block.height)
                tint
                ForEach(block.labelLines.indices, id: \.self) { index in
                    labelLine(block.labelLines[index])
                }
                content
                ForEach(block.cues.indices, id: \.self) { index in
                    cue(block.cues[index])
                }
            }
            .frame(width: column.width, height: block.height, alignment: .topLeading)
        }

        @ViewBuilder private var tint: some View {
            if let color = Self.tintColor(block.tint) {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(color)
                    // 8pt of padding left of the lyrics, so the tint never meets a label
                    // that fills the gutter.
                    .frame(
                        width: max(0, column.width - lyricOrigin + 12),
                        height: block.height + 12,
                    )
                    .offset(x: lyricOrigin - 8, y: -6)
                    .accessibilityHidden(true)
            }
        }

        /// Low-luminance tints by section type (brand.md: distinct, never bright). They are
        /// decorative: the label already names the section.
        static func tintColor(_ tint: SectionTint) -> Color? {
            switch tint {
            case .chorus: Theme.color.ink.opacity(0.045)
            case .bridge: Theme.color.cue.opacity(0.05)
            case .tab: Theme.color.ink.opacity(0.03)
            case .other, .verse: nil
            }
        }

        @ViewBuilder private var content: some View {
            switch block.content {
            case let .notes(rows), let .rows(rows):
                rowViews(rows)
            }
        }

        /// One gutter line: the name (chorus labels `ink`, others `muted`), the pass badge in
        /// its hairline box, the mode tag, or "(cont.)".
        @ViewBuilder
        private func labelLine(_ line: PlacedLine) -> some View {
            switch line.text.role {
            case .passBadge:
                let padding = style.passBadgePadding
                placed(
                    text(line.text)
                        .padding(.horizontal, padding.width)
                        .padding(.vertical, padding.height)
                        .overlay {
                            RoundedRectangle(cornerRadius: 5, style: .continuous)
                                .strokeBorder(Theme.color.controlBorder, lineWidth: 1)
                        },
                    x: line.text.x - padding.width,
                    baseline: line.baseline,
                )
                .accessibilityIdentifier(AccessibilityID.livePassBadge(block.id + 1))
            case .sectionLabel:
                placed(
                    text(
                        line.text,
                        color: block.isChorusLabel ? Theme.color.ink : Theme.color.muted,
                    ),
                    x: line.text.x,
                    baseline: line.baseline,
                )
                .accessibilityAddTraits(.isHeader)
            default:
                placed(text(line.text), x: line.text.x, baseline: line.baseline)
            }
        }

        private func rowViews(_ rows: [LayoutRow]) -> some View {
            ForEach(rows.indices, id: \.self) { index in
                let row = rows[index]
                if let chordBaseline = row.chordBaseline {
                    ForEach(row.chords.indices, id: \.self) { chord in
                        placed(
                            text(row.chords[chord]),
                            x: lyricOrigin + row.chords[chord].x,
                            baseline: row.y + chordBaseline,
                        )
                        .accessibilityIdentifier(row.chords[chord].role == .chordDetail
                            ? AccessibilityID.liveChordDetail : AccessibilityID.sheetChord)
                    }
                }
                ForEach(row.text.indices, id: \.self) { run in
                    placed(
                        text(row.text[run]),
                        x: lyricOrigin + row.text[run].x,
                        baseline: row.y + row.textBaseline,
                    )
                    .accessibilityIdentifier(AccessibilityID.liveLyric)
                }
            }
        }

        /// A cue callout: a hairline box at the section's top edge with the cue dot, text in
        /// `cueText`, wrapped as the engine placed it.
        private func cue(_ cue: PlacedCue) -> some View {
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Theme.color.cue.opacity(0.06))
                    .strokeBorder(Theme.color.controlBorder, lineWidth: 1)
                    .frame(width: cue.width, height: cue.height)
                Rectangle()
                    .fill(Theme.color.cue)
                    .frame(width: 2, height: max(0, cue.height - 8))
                    .offset(x: 0, y: 4)
                ForEach(cue.lines.indices, id: \.self) { index in
                    let line = cue.lines[index]
                    placed(text(line.text), x: line.text.x, baseline: line.baseline)
                }
            }
            .frame(width: cue.width, height: cue.height, alignment: .topLeading)
            .offset(x: lyricOrigin + cue.x, y: cue.y)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(cue.text)
            .accessibilityAddTraits(.isStaticText)
            .accessibilityIdentifier(AccessibilityID.liveCue)
        }

        private func text(_ run: PlacedText, color: Color? = nil) -> Text {
            let size = run.size > 0 ? run.size : size(run.role)
            return Text(run.text)
                .font(StageTypography.font(run.role, size: size))
                .tracking(StageTypography.tracking(run.role, size: size))
                .foregroundStyle(color ?? self.color(run))
        }

        /// The fallback size of a run that carries none: lyric-relative roles scale with the
        /// plan, gutter and callout roles are fixed.
        private func size(_ role: TextRole) -> Double {
            switch role {
            case .chord, .chordSeparator: plan.chordSize
            case .chordDetail: plan.chordSize * ChordUnit.detailScale
            case .lyric: plan.lyricSize
            case .comment: plan.lyricSize * style.commentScale
            case .moreLines: plan.lyricSize * style.moreLinesScale
            case .verbatim: plan.lyricSize * style.verbatimScale
            default: Self.fixedSize(role, style: style)
            }
        }

        private static func fixedSize(_ role: TextRole, style: LayoutStyle) -> Double {
            switch role {
            case .labelDetail: style.labelDetailSize
            case .passBadge: style.passBadgeSize
            case .modeTag: style.modeTagSize
            case .cue: style.cueSize
            case .note: style.noteSize
            default: style.labelSize
            }
        }

        private func color(_ run: PlacedText) -> Color {
            switch run.role {
            case .chord:
                run.chordKind == .chord || run.chordKind == nil
                    ? Theme.color.cueText : Theme.color.muted
            case .chordDetail, .comment, .labelDetail, .modeTag, .moreLines, .note,
                 .sectionLabel:
                Theme.color.muted
            case .chordSeparator:
                Theme.color.indicatorOff
            case .cue:
                Theme.color.cueText
            case .lyric, .passBadge, .verbatim:
                Theme.color.ink
            }
        }

        /// Places `view` with its leading edge at `x` and its first baseline at `baseline`
        /// (both from the block's top-left).
        private func placed(_ view: some View, x: Double, baseline: Double) -> some View {
            view
                .fixedSize()
                .alignmentGuide(.leading) { _ in -x }
                .alignmentGuide(.top) { dimensions in dimensions[.firstTextBaseline] - baseline }
        }
    }
#endif
