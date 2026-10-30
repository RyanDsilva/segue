#if os(macOS)
    import SwiftUI

    /// Interim (P8-2 section 5, until P8-3 rebuilds Arrange Sections): an arrangement with
    /// Chords only or First line passes is shown read-only, so the old editor can never drop
    /// a mode.
    struct ShowModesBanner: View {
        var body: some View {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Image(systemName: "lock.fill")
                    .foregroundStyle(Theme.color.muted)
                    .accessibilityHidden(true)
                Text("This arrangement uses show modes; update Segue's editor")
                    .font(SchibstedGrotesk.medium.font(size: 13))
                    .foregroundStyle(Theme.color.muted)
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
            .background(Theme.color.surfaceAlt)
        }
    }
#endif
