#if os(macOS)
    import Library
    import Setlists
    import Shows
    import SwiftUI

    /// Setlist (WS2a 3.5.3, A33 b): Start Show and Rehearse for the shown builder, New
    /// Setlist…, and Add Selected Song to Setlist ▸ (a keyboard and VoiceOver path for adding
    /// songs without dragging).
    struct SetlistCommands: Commands {
        let app: AppModel
        @FocusedValue(\.focusedSongID) private var focusedSongID

        var body: some Commands {
            CommandMenu("Setlist") {
                Button(MenuShortcuts.startShow.title) { start(.gig) }
                    .keyboardShortcut(MenuShortcuts.startShow)
                    .disabled(startableSetlist == nil)
                Button(MenuShortcuts.rehearse.title) { start(.rehearsal) }
                    .keyboardShortcut(MenuShortcuts.rehearse)
                    .disabled(startableSetlist == nil)
                Divider()
                Button(MenuShortcuts.newSetlist.title) { app.session?.isNamingNewSetlist = true }
                    .keyboardShortcut(MenuShortcuts.newSetlist)
                    .disabled(app.session == nil || app.isPerforming || app.isMainWindowBusy)
                if let session = app.session, let song = selectedSong {
                    AddToSetlistMenu(
                        title: "Add Selected Song to Setlist",
                        session: session,
                        songID: song,
                    )
                } else {
                    Button("Add Selected Song to Setlist") {}
                        .disabled(true)
                }
            }
        }

        /// The shown builder's setlist when it can start: not performing or starting, nothing
        /// up in the main window, and at least one of its songs still in the library.
        private var startableSetlist: Setlist? {
            guard let session = app.session, let setlist = app.shownSetlist, !app.isPerforming,
                  !app.isStartingShow, !app.isMainWindowBusy,
                  setlist.entries.contains(where: { session.library.song(id: $0.songId) != nil })
            else { return nil }
            return setlist
        }

        private func start(_ kind: ShowKind) {
            guard let setlist = startableSetlist else { return }
            // `startShow` saves the open editor first, as the builder's buttons do.
            Task { await app.startShow(setlist, kind: kind) }
        }

        private var selectedSong: SongID? {
            guard !app.isMainWindowBusy else { return nil }
            return app.menuSong(focused: focusedSongID)
        }
    }

    /// Add to Setlist ▸: one item per setlist in sidebar order, checked when the setlist
    /// already holds the song (choosing it still adds another copy, like the builder's +).
    /// Read-only setlists are listed but disabled. Shared by the Setlist menu, the song row's
    /// context menu and the detail pane's "…" menu.
    struct AddToSetlistMenu: View {
        var title = "Add to Setlist"
        let session: LibrarySession
        let songID: SongID

        var body: some View {
            Menu(title) {
                if session.setlists.setlists.isEmpty {
                    Button("No Setlists") {}
                        .disabled(true)
                }
                ForEach(session.setlists.setlists) { setlist in
                    // A checkmark (state on) when the setlist already holds the song;
                    // choosing it still appends another copy.
                    Toggle(setlist.name, isOn: Binding(
                        get: { setlist.entries.contains { $0.songId == songID } },
                        set: { _ in session.addSong(songID, to: setlist.id) },
                    ))
                    .disabled(setlist.readOnly != nil)
                }
            }
            .accessibilityIdentifier(AccessibilityID.addToSetlistMenu)
        }
    }
#endif
