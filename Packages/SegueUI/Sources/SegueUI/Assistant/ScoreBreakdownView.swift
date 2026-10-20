#if os(macOS)
    import SetAssistant
    import SwiftUI

    /// Why a song is where it is (spec 7 step 4): each signal's weighted contribution with
    /// its reason, a proportional bar of the positive ones, and the total they sum to.
    struct ScoreBreakdownView: View {
        let title: String
        let breakdown: ScoreBreakdown

        var body: some View {
            VStack(alignment: .leading, spacing: 0) {
                Text("Why \(title)")
                    .font(SchibstedGrotesk.bold.font(size: 14))
                    .foregroundStyle(Theme.color.ink)
                    .lineLimit(1)
                    .padding(.horizontal, 14)
                    .padding(.top, 12)
                bar
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                ForEach(breakdown.contributions, id: \.signal) { row in
                    HStack(spacing: 10) {
                        Text(row.signal.title)
                            .font(SchibstedGrotesk.semiBold.font(size: 13))
                            .foregroundStyle(Theme.color.ink)
                            .frame(width: 112, alignment: .leading)
                        Text(row.reason)
                            .font(SchibstedGrotesk.medium.font(size: 12))
                            .foregroundStyle(Theme.color.muted)
                            .lineLimit(1)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Text(Self.format(row.value))
                            .font(SchibstedGrotesk.semiBold.font(size: 13))
                            .foregroundStyle(row.value < 0 ? Theme.color.cueText : Theme.color.ink)
                            .frame(width: 48, alignment: .trailing)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 4)
                    .accessibilityElement(children: .combine)
                }
                Rule().padding(.top, 4)
                HStack {
                    Text("Score")
                    Spacer()
                    Text(Self.format(breakdown.total, signed: false))
                }
                .font(SchibstedGrotesk.bold.font(size: 13.5))
                .foregroundStyle(Theme.color.ink)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .accessibilityElement(children: .combine)
            }
            .frame(width: 340)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier(AccessibilityID.assistantBreakdown)
        }

        /// The positive contributions side by side, in proportion.
        private var bar: some View {
            let positive = breakdown.contributions.filter { $0.value > 0 }
            return GeometryReader { proxy in
                let sum = max(positive.map(\.value).reduce(0, +), 0.0001)
                HStack(spacing: 2) {
                    ForEach(positive, id: \.signal) { row in
                        RoundedRectangle(cornerRadius: 2)
                            .fill(Self.color(row.signal))
                            .frame(width: max((proxy.size.width - 8) * row.value / sum, 2))
                    }
                }
            }
            .frame(height: 6)
            .accessibilityHidden(true)
        }

        static func color(_ signal: ScoreSignal) -> Color {
            switch signal {
            case .proficiency: PartPalette.color(0)
            case .tags: PartPalette.color(2)
            case .slot: PartPalette.color(1)
            case .keyFlow: PartPalette.color(3)
            case .recent, .variety: Theme.color.muted
            }
        }

        /// "+1.00", "-0.61", "0.00".
        static func format(_ value: Double, signed: Bool = true) -> String {
            let text = String(format: "%.2f", abs(value))
            guard signed, abs(value) >= 0.005 else { return value < -0.005 ? "-" + text : text }
            return (value < 0 ? "-" : "+") + text
        }

        /// The VoiceOver summary of a row's score ("Score 2.95: Pro, 1 of 1 tags, ...").
        static func spoken(_ breakdown: ScoreBreakdown) -> String {
            let reasons = breakdown.contributions.map(\.reason).filter { !$0.isEmpty }
            return "Score \(format(breakdown.total, signed: false))"
                + (reasons.isEmpty ? "" : ": " + reasons.joined(separator: ", "))
        }
    }
#endif
