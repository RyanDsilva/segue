#if os(macOS)
    import CoreText
    import LiveLayout
    import SwiftUI

    /// The song body's pass marks that change with the scroll (P8-2 section 8), drawn over
    /// `StagePlanView` (which stays `Equatable` and is not redrawn per frame) in the plan's
    /// coordinates: the current pass's cue dot before its gutter name, the name in `ink`; in
    /// a rehearsal loop, a dashed coral bracket in the gutter gap and "⟲ Loop" under the
    /// gutter lines. Decorative: the map strip and the header say the same in words.
    struct StagePassOverlay: View {
        let plan: LayoutPlan
        let current: Int?
        let loop: Int?
        var style: LayoutStyle = .stage

        /// The current pass's dot, and the gap before the name.
        static let dot: CGFloat = 7
        static let dotGap: CGFloat = 6

        var body: some View {
            ZStack(alignment: .topLeading) {
                Color.clear
                    .frame(width: plan.viewport.width, height: max(plan.contentHeight, 1))
                if let current {
                    currentMark(current)
                }
                if let loop {
                    loopMarks(loop)
                }
            }
            .frame(
                width: plan.viewport.width,
                height: max(plan.contentHeight, 1),
                alignment: .topLeading,
            )
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }

        /// The blocks of pass `index` with their columns, in order.
        private func blocks(of index: Int) -> [(block: LayoutBlock, column: LayoutColumn)] {
            plan.columns.flatMap { column in
                column.blocks.filter { $0.pass == index }.map { ($0, column) }
            }
        }

        @ViewBuilder
        private func currentMark(_ index: Int) -> some View {
            if let (block, column) = blocks(of: index).first,
               let first = block.labelLines.first(where: { $0.text.role == .sectionLabel })
            {
                let names = block.labelLines.filter { $0.text.role == .sectionLabel }
                let size = first.text.size
                let xHeight = CTFontGetXHeight(StageTextMetrics.ctFont(.sectionLabel, size: size))
                Circle()
                    .fill(Theme.color.cue)
                    .frame(width: Self.dot, height: Self.dot)
                    .offset(
                        x: column.x + first.text.x - Self.dotGap - Self.dot,
                        y: block.y + first.baseline - xHeight / 2 - Self.dot / 2,
                    )
                ZStack(alignment: .topLeading) {
                    Color.clear.frame(width: column.width, height: block.height)
                    ForEach(names.indices, id: \.self) { line in
                        placed(names[line], color: Theme.color.ink)
                    }
                }
                .frame(width: column.width, height: block.height, alignment: .topLeading)
                .offset(x: column.x, y: block.y)
            }
        }

        @ViewBuilder
        private func loopMarks(_ index: Int) -> some View {
            let parts = blocks(of: index)
            let x = plan.gutterWidth + (style.gutterGap - LoopBracket.width) / 2
            ForEach(parts.indices, id: \.self) { part in
                let (block, column) = parts[part]
                let extra: CGFloat = part == parts.count - 1 ? 8 : 0
                LoopBracket(height: block.height + extra)
                    .offset(x: column.x + x, y: block.y)
            }
            if let (block, column) = parts.first, let last = block.labelLines.last {
                let descent = StageTextMetrics().extents(of: last.text.role).descent
                HStack(spacing: 5) {
                    Text("⟲")
                    Text("Loop")
                }
                .font(SchibstedGrotesk.bold.font(size: 12))
                .foregroundStyle(Theme.color.cueText)
                .fixedSize()
                .offset(
                    x: column.x,
                    y: block.y + last.baseline + descent * last.text.size + 6,
                )
            }
        }

        /// A gutter line at its x and baseline in its block, as `StagePlanView` draws it.
        private func placed(_ line: PlacedLine, color: Color) -> some View {
            Text(line.text.text)
                .font(StageTypography.font(line.text.role, size: line.text.size))
                .foregroundStyle(color)
                .fixedSize()
                .alignmentGuide(.leading) { _ in -line.text.x }
                .alignmentGuide(.top) { dimensions in
                    dimensions[.firstTextBaseline] - line.baseline
                }
        }
    }

    /// The loop's dashed bracket: 3 pt wide, 8 pt dashes with 5 pt gaps, rounded ends.
    private struct LoopBracket: View {
        static let width: CGFloat = 3
        let height: CGFloat

        var body: some View {
            Path { path in
                let half = Self.width / 2
                path.move(to: CGPoint(x: half, y: half))
                path.addLine(to: CGPoint(x: half, y: max(half, height - half)))
            }
            // Round caps add half the width at each end: 5 + 3 = 8 pt dashes, 8 - 3 = 5 pt
            // gaps.
            .stroke(
                Theme.color.cue,
                style: StrokeStyle(lineWidth: Self.width, lineCap: .round, dash: [5, 8]),
            )
            .frame(width: Self.width, height: height)
        }
    }
#endif
