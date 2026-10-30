#if os(macOS)
    import SwiftUI

    /// The jump confirmation (R148): "Jumped to Bridge" / "Jumped to Chorus · 2 of 3",
    /// centred at the top of the song area, fading in and out over 250 ms around 1.1 s on
    /// screen (no fade with Reduce Motion). It takes no clicks; VoiceOver hears it as an
    /// announcement (`LiveSession.jump(toPass:)`).
    struct StageJumpToast: View {
        /// One confirmation; `sequence` tells a repeated jump to the same pass apart.
        struct Message: Equatable {
            var text: String
            var sequence: Int
        }

        static let visible: Duration = .milliseconds(1100)
        static let fade: Duration = .milliseconds(250)

        let message: Message?
        @Environment(\.accessibilityReduceMotion) private var reduceMotion

        var body: some View {
            ZStack {
                if let message {
                    Text(message.text)
                        .font(SchibstedGrotesk.semiBold.font(size: 14))
                        .foregroundStyle(Theme.color.ink)
                        .lineLimit(1)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background {
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(Theme.color.surfaceAlt.opacity(0.95))
                                .overlay {
                                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                                        .strokeBorder(Theme.color.controlBorder, lineWidth: 1)
                                }
                        }
                        .id(message.sequence)
                        .transition(.opacity)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(message.text)
                        .accessibilityAddTraits(.isStaticText)
                        .accessibilityIdentifier(AccessibilityID.liveJumped)
                }
            }
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.25), value: message)
            .allowsHitTesting(false)
        }
    }
#endif
