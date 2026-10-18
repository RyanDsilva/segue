#if os(macOS)
    import CryptoKit
    import Foundation
    import Library
    import Setlists
    import Shows
    import Support

    /// The sidebar destination, selected song and selected gig of one library, restored on
    /// the next launch (WS2a 3.10, A26). Not the editor (autosave means nothing is lost),
    /// not the search text or filters, and not `@SceneStorage` (E2E runs ignore persisted
    /// window state, and this must also survive closing and reopening the window).
    struct RestoredState: Codable, Equatable {
        static let currentVersion = 1

        var version = Self.currentVersion
        /// "library", "gigLog" or "setlist:<ULID>".
        var section: String
        var song: String?
        var gig: String?

        init(section: LibrarySession.Section?, song: SongID?, gig: ShowID?) {
            self.section = switch section {
            case .library, nil: "library"
            case .gigLog: "gigLog"
            case let .setlist(id): "setlist:\(id)"
            }
            self.song = song?.description
            self.gig = gig?.description
        }

        /// The section to show, given the setlists that exist now (a missing one falls
        /// back to the Library).
        func section(existing: (SetlistID) -> Bool) -> LibrarySession.Section {
            switch section {
            case "gigLog":
                return .gigLog
            case let value where value.hasPrefix("setlist:"):
                guard let ulid = ULID(string: String(value.dropFirst("setlist:".count))),
                      existing(SetlistID(ulid))
                else { return .library }
                return .setlist(SetlistID(ulid))
            default:
                return .library
            }
        }

        var songID: SongID? {
            song.flatMap(ULID.init(string:)).map(SongID.init)
        }

        var gigID: ShowID? {
            gig.flatMap(ULID.init(string:)).map(ShowID.init)
        }
    }

    /// Reads and writes `RestoredState` per library in the app's defaults, under
    /// `restoredState.<sha256 of the root path>`.
    @MainActor
    final class SessionRestore {
        private let defaults: UserDefaults
        private let key: String
        private var pendingWrite: Task<Void, Never>?

        init(defaults: UserDefaults, root: LibraryRoot) {
            self.defaults = defaults
            key = Self.key(for: root)
        }

        static func key(for root: LibraryRoot) -> String {
            let path = root.url.path(percentEncoded: false)
            let digest = SHA256.hash(data: Data(path.utf8))
            return "restoredState." + digest.map { String(format: "%02x", $0) }.joined()
        }

        /// The stored state; nil when none (or from a newer, unknown version).
        func load() -> RestoredState? {
            guard let data = defaults.data(forKey: key),
                  let state = try? JSONDecoder().decode(RestoredState.self, from: data),
                  state.version <= RestoredState.currentVersion
            else { return nil }
            return state
        }

        /// Stores `state` after 0.5 s of quiet (selection changes come in bursts).
        func save(_ state: RestoredState) {
            pendingWrite?.cancel()
            pendingWrite = Task { [weak self] in
                try? await Task.sleep(for: .milliseconds(500))
                guard !Task.isCancelled else { return }
                self?.write(state)
            }
        }

        /// Stores `state` now.
        func write(_ state: RestoredState) {
            pendingWrite?.cancel()
            if let data = try? JSONEncoder().encode(state) {
                defaults.set(data, forKey: key)
            }
        }
    }

    // MARK: - Session wiring

    extension LibrarySession {
        /// Applies the stored state once the library's first reload is done (before the
        /// resume prompt; a pending resume stays on top). Missing targets fall back: a gone
        /// setlist to the Library, a gone song to no selection, a gone gig to the list.
        func restoreState() {
            guard let restore else { return }
            if let state = restore.load() {
                let section = state.section { setlists.setlist($0) != nil }
                if case let .setlist(id) = section {
                    setlists.selection = id
                }
                self.section = section
                if let song = state.songID, library.song(id: song) != nil {
                    library.selection = song
                    library.detail = .song(song)
                }
                gigLog.restoredSelection = state.gigID
            }
            trackRestorableState()
        }

        /// Saves the state on every change of section, song or gig selection.
        private func trackRestorableState() {
            withObservationTracking {
                _ = currentRestoredState
            } onChange: { [weak self] in
                Task { @MainActor in
                    guard let self else { return }
                    self.restore?.save(self.currentRestoredState)
                    self.trackRestorableState()
                }
            }
        }

        var currentRestoredState: RestoredState {
            RestoredState(section: section, song: library.selection, gig: gigLog.selection)
        }
    }
#endif
