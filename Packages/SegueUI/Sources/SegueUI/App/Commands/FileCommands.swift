#if os(macOS)
    import AppKit
    import Library
    import SwiftUI

    /// File (WS2a 3.5.2, P3-4): New Song, New Song from Clipboard, Import Songs…, Export Library
    /// Archive… (hidden until
    /// WS2b fills its hook), Show in Finder, Move to Trash, Close, Save, Export PDF… and Print…
    /// (P9-1). There is no New Window: the main window is a single `Window` reopened from the
    /// Window menu.
    struct FileCommands: Commands {
        let app: AppModel
        /// The song selected in the focused song list (Move to Trash needs list focus).
        @FocusedValue(\.focusedSongID) private var focusedSongID

        var body: some Commands {
            CommandGroup(replacing: .newItem) {
                // During a show New Song goes straight to Start blank and Import takes only
                // already-ChordPro files (R109); neither acts while the stage has the keyboard.
                Button(MenuShortcuts.newSong.title) { app.newSong() }
                    .keyboardShortcut(MenuShortcuts.newSong)
                    .disabled(app.session == nil)
                Button(MenuShortcuts.newSongFromClipboard.title) { app.newSongFromClipboard() }
                    .keyboardShortcut(MenuShortcuts.newSongFromClipboard)
                    .disabled(app.session == nil || app.isPerforming)
                    .help(app.isPerforming ? LibraryViewModel.pasteDuringShowReason : "")
                Button(MenuShortcuts.importSongs.title) { Task { await app.importSongs() } }
                    .keyboardShortcut(MenuShortcuts.importSongs)
                    .disabled(app.session == nil)
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
            // P9-1 (R178): Export PDF... and Print... both open the preview; no system Page
            // Setup or Print item survives.
            CommandGroup(replacing: .printItem) {
                let target = app.pdfMenuTarget(focused: focusedSongID)
                Button(MenuShortcuts.exportPDF.title) {
                    if let target {
                        app.openPDF(target)
                    }
                }
                .keyboardShortcut(MenuShortcuts.exportPDF)
                .disabled(target == nil || app.pdfPreview != nil)
                Button(MenuShortcuts.print.title) {
                    if let target {
                        app.openPDF(target, forPrint: true)
                    }
                }
                .keyboardShortcut(MenuShortcuts.print)
                .disabled(target == nil || app.pdfPreview != nil)
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
