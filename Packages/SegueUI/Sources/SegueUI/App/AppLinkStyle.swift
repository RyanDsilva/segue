#if os(macOS)
    import SwiftUI

    /// The app's one link style (as in the editor and the About panel): `cueText` with the
    /// pointing-hand cursor, never system blue. Every in-app link is a `Button` with this
    /// style (`.buttonStyle(.appLink)`), so a parent's foreground cannot turn it into plain
    /// text and the look changes in one place.
    struct AppLinkButtonStyle: ButtonStyle {
        func makeBody(configuration: Configuration) -> some View {
            configuration.label
                .foregroundStyle(Theme.color.cueText)
                .opacity(configuration.isPressed ? 0.7 : 1)
                .contentShape(Rectangle())
                .pointerStyle(.link)
        }
    }

    extension ButtonStyle where Self == AppLinkButtonStyle {
        static var appLink: AppLinkButtonStyle {
            AppLinkButtonStyle()
        }
    }
#endif
