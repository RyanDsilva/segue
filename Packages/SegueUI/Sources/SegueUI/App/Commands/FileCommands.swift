#if os(macOS)
    import AppKit
    import Library
    import SwiftUI

    /// File (WS2a 3.5.2): New Song, Import Songs…, Export Library Archive… (hidden until
    /// WS2b fills its hook), Show in Finder, Move to Trash, Close, Save. There is no New
    /// Window: the main window is a single `Window` reopened from the Window menu.
    struct FileCommands: Commands {
        let app: AppModel
        /// The song selected in the focused song list (Move to Trash needs list focus).
        @FocusedValue(\.focusedSongID) private var focusedSongID

        var body: some Commands {
            CommandGroup(replacing: .newItem) {
                Button(MenuShortcuts.newSong.title) { newSong() }
                    .keyboardShortcut(MenuShortcuts.newSong)
                    // Nothing in the main window may change while the stage is up.
                    .disabled(app.session == nil || app.isPerforming)
                Button(MenuShortcuts.importSongs.title) { Task { await app.importSongs() } }
                    .keyboardShortcut(MenuShortcuts.importSongs)
                    .disabled(app.session == nil || app.isPerforming)
                if let export = app.dependencies.hooks.exportArchive {
                    Button("Export Library Archive…") { export(app.dependencies.workspace) }
                        .disabled(app.session == nil || app.isPerforming)
                }
                Divider()
                Button(MenuShortcuts.showInFinder.title) { revealTarget?() }
                    .keyboardShortcut(MenuShortcuts.showInFinder)
                    .disabled(revealTarget == nil)
                // Only while the song list has focus, so ⌘⌫ keeps its text meaning in the
                // editor and every field.
                Button(MenuShortcuts.moveToTrash.title) {
                    guard let session = app.session, let id = focusedSongID else { return }
                    session.requestMoveSongToTrash(id)
                }
                .keyboardShortcut(MenuShortcuts.moveToTrash)
                .disabled(app.session == nil || app.isPerforming || focusedSongID == nil)
                Divider()
            }
            CommandGroup(replacing: .saveItem) {
                // Replacing the save group drops the system Close, so it is restated here.
                Button(MenuShortcuts.close.title) { NSApp.keyWindow?.performClose(nil) }
                    .keyboardShortcut(MenuShortcuts.close)
                // Edits save themselves (R17): Save only confirms, and never opens a panel.
                Button(MenuShortcuts.save.title) {
                    guard let session = app.session else { return }
                    Task { await session.library.confirmSave() }
                }
                .keyboardShortcut(MenuShortcuts.save)
                .disabled(app.session == nil || app.isPerforming)
            }
        }

        private func newSong() {
            guard let session = app.session else { return }
            if session.section == .library {
                session.library.beginNewSong()
            } else {
                session.library.navigate {
                    session.section = .library
                    session.library.beginNewSong()
                }
            }
        }

        /// The focused or shown song, else the shown setlist.
        private var revealTarget: (() -> Void)? {
            guard let session = app.session, !app.isPerforming else { return nil }
            if let id = app.menuSong(focused: focusedSongID) {
                return { session.revealSong(id) }
            }
            if let setlist = app.shownSetlist {
                return { Task { await session.revealSetlist(setlist.id) } }
            }
            return nil
        }
    }
#endif
