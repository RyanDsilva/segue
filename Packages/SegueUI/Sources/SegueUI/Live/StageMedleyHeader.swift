#if os(macOS)
    import LiveLayout
    import SwiftUI

    /// A member header in the medley plan (P9-3 9.2, R187 quiet header): a one-line rule,
    /// the title (bold, 0.75 x the lyric size) with "2 of 3" and the key line, then the
    /// transition in the cue callout style led by "↳" (never colour alone) with the change
    /// line under it (a capo change in `cueText`), then the member's notes. Drawn at the
    /// geometry the engine placed, across the whole column.
    struct StageMedleyHeader: View {
        let placed: PlacedMemberHeader
        let width: CGFloat
        let style: LayoutStyle

        private var header: MemberHeader {
            placed.header
        }

        var body: some View {
            ZStack(alignment: .topLeading) {
                Color.clear.frame(width: width, height: placed.height)
                if placed.hasRule {
                    Rectangle()
                        .fill(Theme.color.line)
                        .frame(width: width, height: 1)
                        .accessibilityHidden(true)
                }
                titleLine
                    .alignmentGuide(.top) { $0[.firstTextBaseline] - placed.titleBaseline }
                if let callout = placed.callout {
                    calloutView(callout)
                        .offset(y: callout.y)
                }
                ForEach(placed.notes.indices, id: \.self) { index in
                    let line = placed.notes[index]
                    Text(line.text.text)
                        .font(StageTypography.font(.note, size: style.noteSize))
                        .foregroundStyle(Theme.color.muted)
                        .fixedSize()
                        .alignmentGuide(.leading) { _ in -line.text.x }
                        .alignmentGuide(.top) { $0[.firstTextBaseline] - line.baseline }
                }
            }
            .frame(width: width, height: placed.height, alignment: .topLeading)
            .accessibilityElement(children: .contain)
            .accessibilityLabel(spokenLabel)
            .accessibilityIdentifier(AccessibilityID.liveMemberHeader)
        }

        private var titleLine: some View {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(header.title)
                    .font(SchibstedGrotesk.bold.font(size: placed.titleSize))
                    .foregroundStyle(Theme.color.ink)
                    .accessibilityAddTraits(.isHeader)
                Text(header.positionText)
                    .font(SchibstedGrotesk.semiBold.font(size: 12))
                    .foregroundStyle(Theme.color.muted)
                if !header.keyLine.isEmpty {
                    Text(header.keyLine)
                        .font(SchibstedGrotesk.medium.font(size: max(13, placed.titleSize * 0.55)))
                        .foregroundStyle(Theme.color.muted)
                }
            }
            .lineLimit(1)
            .fixedSize()
        }

        private func calloutView(_ callout: PlacedCue) -> some View {
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Theme.color.cue.opacity(0.06))
                    .strokeBorder(Theme.color.controlBorder, lineWidth: 1)
                    .frame(width: callout.width, height: callout.height)
                Rectangle()
                    .fill(Theme.color.cue)
                    .frame(width: 2, height: max(0, callout.height - 8))
                    .offset(y: 4)
                ForEach(callout.lines.indices, id: \.self) { index in
                    let line = callout.lines[index]
                    Text(line.text.text)
                        .font(StageTypography.font(.cue, size: style.cueSize))
                        .foregroundStyle(Theme.color.cueText)
                        .fixedSize()
                        .alignmentGuide(.leading) { _ in -line.text.x }
                        .alignmentGuide(.top) { $0[.firstTextBaseline] - line.baseline }
                        .accessibilityIdentifier(AccessibilityID.liveMemberTransition)
                }
                if let baseline = placed.changesBaseline {
                    changeLine
                        .alignmentGuide(.leading) { _ in -style.cuePadding.width }
                        .alignmentGuide(.top) { $0[.firstTextBaseline] - baseline }
                }
            }
            .frame(width: callout.width, height: callout.height, alignment: .topLeading)
        }

        /// "G → A · capo 2 → no capo · 96 → 120 BPM": a capo change in the cue colour.
        private var changeLine: some View {
            HStack(alignment: .firstTextBaseline, spacing: 5) {
                ForEach(header.changes.indices, id: \.self) { index in
                    if index > 0 {
                        Text("\u{00B7}").foregroundStyle(Theme.color.muted)
                    }
                    let change = header.changes[index]
                    Text(change.text)
                        .foregroundStyle(change.kind == .capo ? Theme.color.cueText
                            : Theme.color.muted)
                }
            }
            .font(SchibstedGrotesk.medium.font(size: placed.changesSize))
            .lineLimit(1)
            .fixedSize()
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier(AccessibilityID.liveMemberChanges)
        }

        /// "Tum Hi Ho, 2 of 3, A, capo 2, 120. Transition: Hold the D. G to A".
        private var spokenLabel: String {
            var parts = ["\(header.title), \(header.positionText)"]
            if !header.keyLine.isEmpty {
                parts.append(header.keyLine)
            }
            var label = parts.joined(separator: ", ")
            if let transition = header.transition {
                label += ". Transition: \(transition)"
            }
            if !header.changes.isEmpty {
                label += ". " + header.changeLine.replacingOccurrences(of: "\u{2192}", with: "to")
            }
            return label
        }
    }
#endif
