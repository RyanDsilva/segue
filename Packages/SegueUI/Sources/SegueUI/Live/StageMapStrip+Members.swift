#if os(macOS)
    import LiveLayout
    import SwiftUI

    /// The map across a medley's members (P9-3 9.3, R187 direction B): each member's chips
    /// in a faint container with the member's title as a tab above them, the current
    /// member's container lit. The tab sits in the band's own height, so the chips are
    /// shorter and the band does not grow.
    extension StageMapStrip {
        /// The member tab's height and the container's inner padding.
        static let memberTab: CGFloat = 15
        static let memberPadding: CGFloat = 4
        static let memberGap: CGFloat = 8

        /// The passes of member `segment`, as indices into `passes`.
        func passes(of segment: Int) -> [Int] {
            passes.indices.filter { passes[$0].segment == segment }
        }

        /// Chip widths when the containers' padding and gaps are taken out of the room; nil
        /// when they do not fit at the minimum (the strip then scrolls, ungrouped).
        func groupedWidths(_ available: CGFloat) -> [CGFloat]? {
            let groups = CGFloat(members.count)
            let room = available - (groups - 1) * Self.memberGap
                - groups * 2 * Self.memberPadding
                + (groups - 1) * style.metrics.gap
            return Self.widths(passes.map(\.weight), in: room, metrics: style.metrics)
        }

        func groupedRow(_ widths: [CGFloat]) -> some View {
            HStack(alignment: .top, spacing: Self.memberGap) {
                ForEach(members.indices, id: \.self) { segment in
                    group(segment, widths: widths)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }

        private func group(_ segment: Int, widths: [CGFloat]) -> some View {
            let lit = segment == currentMember
            let shape = RoundedRectangle(cornerRadius: 8, style: .continuous)
            return VStack(alignment: .leading, spacing: 1) {
                Text(members[segment])
                    .font(SchibstedGrotesk.semiBold.font(size: 10.5))
                    .foregroundStyle(lit ? Theme.color.ink : Theme.color.muted)
                    .lineLimit(1)
                    .frame(height: Self.memberTab - 1, alignment: .leading)
                    .padding(.leading, 5)
                HStack(spacing: style.metrics.gap) {
                    ForEach(passes(of: segment), id: \.self) { index in
                        chip(index).frame(width: widths[index])
                    }
                }
                .frame(maxHeight: .infinity)
            }
            .padding(Self.memberPadding)
            .background(
                lit ? Theme.color.surfaceAlt.opacity(0.6) : Theme.color.ink.opacity(0.02),
                in: shape,
            )
            .overlay {
                shape.strokeBorder(
                    lit ? Theme.color.controlBorder : Theme.color.line,
                    lineWidth: 1,
                )
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel(members[segment])
            .accessibilityIdentifier(AccessibilityID.liveMapMember)
        }
    }
#endif
