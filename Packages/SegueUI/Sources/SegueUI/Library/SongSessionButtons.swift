#if os(macOS)
    import Library
    import Shows
    import SwiftUI

    /// "Rehearse" and "Live" for one library song (R150): in the song header (large) and on
    /// the selected song row (small). Both start a single-song session, never logged.
    struct SongSessionButtons: View {
        enum Size {
            case large
            case small
        }

        let songID: SongID
        var size: Size = .large
        @Environment(\.songSession) private var songSession

        var body: some View {
            if let songSession {
                HStack(spacing: size == .large ? 8 : 6) {
                    button("Rehearse", symbol: "play.fill", kind: .rehearsal, songSession)
                        .help("Rehearse this song on stage, not logged (⌥⌘↩)")
                        .accessibilityIdentifier(AccessibilityID.librarySongRehearse)
                    button("Live", symbol: nil, kind: .gig, songSession)
                        .help("Play this song live on stage, not logged (⇧⌘↩)")
                        .accessibilityIdentifier(AccessibilityID.librarySongLive)
                }
            }
        }

        @ViewBuilder
        private func button(
            _ title: String,
            symbol: String?,
            kind: ShowKind,
            _ action: SongSessionAction,
        ) -> some View {
            let label = Label {
                Text(title)
            } icon: {
                if let symbol {
                    Image(systemName: symbol).imageScale(.small)
                }
            }
            .labelStyle(.titleAndIcon)
            switch size {
            case .large:
                Button { action.start(songID, kind) } label: { label }
                    .buttonStyle(.segueSecondary)
                    .disabled(!action.isEnabled)
            case .small:
                Button { action.start(songID, kind) } label: {
                    label
                        .font(SchibstedGrotesk.semiBold.font(size: 12))
                        .foregroundStyle(Theme.color.ink)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background {
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .strokeBorder(Theme.color.controlBorder, lineWidth: 1)
                        }
                        .contentShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                }
                .buttonStyle(.plain)
                .disabled(!action.isEnabled)
            }
        }
    }
#endif
