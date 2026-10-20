#if os(macOS)
    import Setlists
    import Shows
    import SwiftUI

    public extension AccessibilityID {
        /// The stage's break interstitial (R104).
        static let liveBreak = "segue.live.break"
    }

    /// The stage between two parts of a set (R104): "Break", the next part's label, the
    /// planned intermission, and the song the part starts with. Next continues; the show
    /// clock in the header keeps running.
    struct StageBreakView: View {
        let info: SetlistBreak
        /// The song behind the break (the current item).
        let nextTitle: String?

        var body: some View {
            VStack(alignment: .leading, spacing: 14) {
                Text("Break")
                    .font(Theme.font.label)
                    .textCase(.uppercase)
                    .tracking(1.2)
                    .foregroundStyle(Theme.color.muted)
                Text(info.label.isEmpty ? "Next part" : info.label)
                    .font(SchibstedGrotesk.extraBold.font(size: 56))
                    .foregroundStyle(Theme.color.ink)
                    .lineLimit(2)
                    .minimumScaleFactor(0.5)
                if let length = info.length, length > 0 {
                    Text("\(SetlistTiming.format(length)) break")
                        .font(Theme.font.body)
                        .foregroundStyle(Theme.color.muted)
                }
                if let nextTitle {
                    Text("Starts with \(Text(nextTitle).foregroundStyle(Theme.color.ink))")
                        .foregroundStyle(Theme.color.muted)
                        .font(SchibstedGrotesk.semiBold.font(size: 24))
                        .lineLimit(2)
                }
                Text("Press → to continue.")
                    .font(Theme.font.body)
                    .foregroundStyle(Theme.color.muted)
                    .padding(.top, 8)
            }
            .frame(maxWidth: 720, alignment: .leading)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Self.summary(info, nextTitle: nextTitle))
            .accessibilityIdentifier(AccessibilityID.liveBreak)
        }

        /// The interstitial's line for VoiceOver and the E2E suite.
        static func summary(_ info: SetlistBreak, nextTitle: String?) -> String {
            let label = info.label.isEmpty ? "Next part" : info.label
            return nextTitle.map { "Break - \(label) starts with \($0)" } ?? "Break - \(label)"
        }
    }
#endif
