#if os(macOS)
    import SwiftUI

    /// The Welcome sheet's paste card (P3-4, R93): what pasting does, that it stays on the
    /// Mac, and a quiet link to Settings > AI (the only place the local model downloads).
    struct WelcomePasteCard: View {
        let app: AppModel
        @Environment(\.openSettings) private var openSettings

        var body: some View {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: "doc.on.clipboard")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(Theme.color.ink)
                    .frame(width: 34, height: 34)
                    .background(
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .fill(Theme.color.ground),
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .strokeBorder(Theme.color.controlBorder, lineWidth: 1),
                    )
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Paste any chord sheet")
                        .font(SchibstedGrotesk.bold.font(size: 14))
                        .foregroundStyle(Theme.color.ink)
                    Text("Copy a song from a chord site or a note and press ⌥⌘V. Segue turns "
                        + "it into a song for you to check. It all happens on this Mac.")
                        .font(SchibstedGrotesk.medium.font(size: 13))
                        .foregroundStyle(Theme.color.muted)
                        .fixedSize(horizontal: false, vertical: true)
                    Button("AI settings and the local model") {
                        app.selectAISettingsPane()
                        openSettings()
                    }
                    .buttonStyle(.link)
                    .font(SchibstedGrotesk.medium.font(size: 13))
                    .padding(.top, 4)
                    .accessibilityIdentifier(AccessibilityID.welcomePasteSettings)
                }
                Spacer(minLength: 0)
            }
            .modifier(WelcomeGroup())
            .accessibilityElement(children: .contain)
        }
    }

    public extension AccessibilityID {
        /// The Welcome paste card's link to Settings > AI.
        static let welcomePasteSettings = "segue.welcome.pasteSettings"
    }
#endif
