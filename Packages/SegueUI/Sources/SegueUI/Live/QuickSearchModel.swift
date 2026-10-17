#if os(macOS)
    import Foundation
    import Library
    import Observation

    /// The mid-show search overlay's state: the query, the results from the index (romanized
    /// Hindi tolerant through the normalized columns) and the selected row. Searches run off
    /// the main actor in the library store; a newer query cancels the older one, so typing
    /// never blocks the stage.
    @MainActor
    @Observable
    public final class QuickSearchModel {
        /// At most this many results are listed.
        static let limit = 8

        public var query = "" {
            didSet {
                if query != oldValue {
                    run()
                }
            }
        }

        public private(set) var results: [SongRecord] = []
        public var selection = 0
        /// The song being added to the requests while its optional note is typed (Cmd-Return
        /// or "Add to Requests"); nil while choosing a song.
        public private(set) var requesting: SongRecord?
        /// The request note ("table 4"); blank adds the request without one.
        public var note = ""
        /// The last search error, shown in place of results.
        public private(set) var errorMessage: String?

        @ObservationIgnored private let library: LibraryStore
        @ObservationIgnored private var task: Task<Void, Never>?

        init(library: LibraryStore) {
            self.library = library
        }

        func reset() {
            task?.cancel()
            query = ""
            results = []
            selection = 0
            errorMessage = nil
            requesting = nil
            note = ""
        }

        /// Starts adding `song` to the requests: the overlay asks for an optional note.
        func beginRequest(_ song: SongRecord) {
            note = ""
            requesting = song
        }

        /// Back from the note to the results (Esc).
        func cancelRequest() {
            requesting = nil
            note = ""
        }

        /// The note as stored: trimmed, nil when blank (Return on an empty field skips it).
        var trimmedNote: String? {
            let trimmed = note.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }

        var selected: SongRecord? {
            results.indices.contains(selection) ? results[selection] : nil
        }

        func moveSelection(_ delta: Int) {
            guard !results.isEmpty else { return }
            selection = min(results.count - 1, max(0, selection + delta))
        }

        private func run() {
            task?.cancel()
            let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else {
                results = []
                selection = 0
                return
            }
            let library = library
            task = Task { [weak self] in
                do {
                    let found = try await library.search(query: text)
                    guard !Task.isCancelled else { return }
                    self?.results = Array(found.prefix(Self.limit))
                    self?.selection = 0
                    self?.errorMessage = nil
                } catch {
                    guard !Task.isCancelled else { return }
                    self?.errorMessage = UserMessage.describe(error)
                }
            }
        }
    }
#endif
