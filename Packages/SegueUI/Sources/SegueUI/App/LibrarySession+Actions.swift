#if os(macOS)
    import Foundation
    import Library
    import Setlists
    import Shows

    /// Asking before a song goes to the Trash: only when setlists use it, so the reader
    /// learns what will show it as missing (A23, like Finder's hidden-consequence rule).
    public struct SongTrashConfirmation: Identifiable, Equatable {
        public let id: SongID
        public let title: String
        /// The setlists that use the song, in sidebar order.
        public let setlistNames: [String]

        /// "Move “Harbour Lights” to the Trash?"
        public var headline: String {
            "Move “\(title)” to the Trash?"
        }

        /// "It is in 2 setlists: Friday, Sunday Brunch. They will show it as missing. You
        /// can undo this."
        public var message: String {
            let names = setlistNames.joined(separator: ", ")
            return setlistNames.count == 1
                ? "It is in 1 setlist: \(names). That setlist will show it as missing. "
                + "You can undo this."
                : "It is in \(setlistNames.count) setlists: \(names). They will show it as "
                + "missing. You can undo this."
        }
    }

    // MARK: - Move to Trash and Show in Finder (WS2a 3.3, 3.8)

    public extension LibrarySession {
        /// Move to Trash for a song: at once when no setlist uses it, else after the
        /// confirmation (`songTrashConfirmation`).
        func requestMoveSongToTrash(_ id: SongID) {
            guard let record = library.song(id: id) else { return }
            let names = setlists.setlists
                .filter { setlist in setlist.entries.contains { $0.songId == id } }
                .map(\.name)
            guard !names.isEmpty else {
                Task { await library.moveSongToTrash(id) }
                return
            }
            songTrashConfirmation = SongTrashConfirmation(
                id: id,
                title: LibraryViewModel.sortTitle(record),
                setlistNames: names,
            )
        }

        /// Answers the confirmation.
        func resolveSongTrashConfirmation(moveToTrash: Bool) {
            guard let confirmation = songTrashConfirmation else { return }
            songTrashConfirmation = nil
            if moveToTrash {
                Task { await library.moveSongToTrash(confirmation.id) }
            }
        }

        /// Shows song `id`'s `.cho` in Finder.
        func revealSong(_ id: SongID) {
            guard let record = library.song(id: id) else { return }
            reveal(root.url.appending(path: record.relativePath, directoryHint: .notDirectory))
        }

        /// Shows setlist `id`'s `.setlist.json` in Finder.
        func revealSetlist(_ id: SetlistID) async {
            guard let url = await setlists.fileURL(for: id) else { return }
            reveal(url)
        }

        /// Shows gig `id`'s `.show.json` in Finder (A28).
        func revealGig(_ id: ShowID) async {
            guard let url = await gigLog.fileURL(for: id) else { return }
            reveal(url)
        }

        /// File > Import Songs… and the empty library's button: the open panel (or the E2E
        /// stand-in), then the import.
        func chooseAndImport() async {
            guard library.canImport else { return }
            let urls = await importPanel.chooseFiles()
            await library.importSongs(urls)
        }

        /// Library > Show Library in Finder: the library folder itself.
        func revealLibrary() {
            workspace.reveal([root.url])
        }

        /// Reveals `url`; a file gone since the last refresh shows its folder instead.
        private func reveal(_ url: URL) {
            if stores.fileSystem.fileExists(at: url) {
                workspace.reveal([url])
            } else {
                workspace.reveal([url.deletingLastPathComponent()])
                library.errorMessage = "The file is no longer there; showing its folder."
            }
        }
    }
#endif
