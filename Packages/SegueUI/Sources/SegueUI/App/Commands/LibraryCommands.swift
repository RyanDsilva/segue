#if os(macOS)
    import Library
    import Shows
    import SwiftUI

    /// Library (WS2a 3.5.4): Refresh, Rehearse Song and Play Song Live (R150), Rebuild Index,
    /// Remove Old Length Lines… (P8-8 5.7), Show Library in Finder, Choose Library Folder….
    struct LibraryCommands: Commands {
        let app: AppModel
        @FocusedValue(\.focusedSongID) private var focusedSongID

        var body: some Commands {
            CommandMenu("Library") {
                Button(MenuShortcuts.refresh.title) {
                    guard let session = app.session else { return }
                    Task { await session.refreshFromDisk() }
                }
                .keyboardShortcut(MenuShortcuts.refresh)
                .disabled(app.session == nil || app.isPerforming)
                Divider()
                // One song on stage, never logged (R150, R158 Q5).
                Button(MenuShortcuts.rehearseSong.title) { startSong(.rehearsal) }
                    .keyboardShortcut(MenuShortcuts.rehearseSong)
                    .disabled(!app.canStartSongSession(focusedSongID))
                Button(MenuShortcuts.playSongLive.title) { startSong(.gig) }
                    .keyboardShortcut(MenuShortcuts.playSongLive)
                    .disabled(!app.canStartSongSession(focusedSongID))
                Divider()
                Button(uiString("Rebuild Index")) {
                    guard let session = app.session else { return }
                    Task { await session.library.rebuildIndex() }
                }
                .disabled(app.session == nil || app.isPerforming)
                // The one-time offer stays reachable here (P8-8 5.7).
                Button(uiString("Remove Old Length Lines…")) {
                    app.session?.durationOffer = songsToClean.count
                }
                .disabled(app.isPerforming || songsToClean.isEmpty)
                Divider()
                Button(uiString("Show Library in Finder")) { app.session?.revealLibrary() }
                    .disabled(app.session == nil)
                Button(uiString("Choose Library Folder…")) {
                    let choose = { Task { await app.chooseLibrary() } }
                    if let session = app.session {
                        session.library.navigate { _ = choose() }
                    } else {
                        _ = choose()
                    }
                }
                // The show belongs to the open library: end it before switching.
                .disabled(!app.canSwitchLibrary)
                .help(app
                    .canSwitchLibrary ? "" : uiString("End the show before switching libraries."))
            }
        }

        /// Songs holding a `{duration}` line.
        private var songsToClean: [SongID] {
            app.session?.library.songsWithDurationLines ?? []
        }

        private func startSong(_ kind: ShowKind) {
            guard let song = focusedSongID, app.canStartSongSession(song) else { return }
            Task { await app.startSongSession(song, kind: kind) }
        }
    }
#endif
