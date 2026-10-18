#if os(macOS)
    import Foundation
    import Library
    import Observation
    import Services

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
        /// The (trimmed) query `results` belong to; differs from `query` while a search for
        /// newer typing is still running.
        public private(set) var resultsQuery = ""
        /// Return pressed before the results for the query as typed landed: runs on their
        /// first result when they do.
        @ObservationIgnored private var pendingSubmit: (@MainActor (SongRecord) -> Void)?

        @ObservationIgnored private let library: LibraryStore
        /// Row 17 in the stage context.
        @ObservationIgnored private let recorder = SearchRecorder()
        @ObservationIgnored var services: ServicesHub {
            get { recorder.services }
            set { recorder.services = newValue }
        }

        @ObservationIgnored private var task: Task<Void, Never>?

        /// The query as searched.
        private var trimmedQuery: String {
            query.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        /// Whether `results` belong to the query as typed.
        var isCurrent: Bool {
            resultsQuery == trimmedQuery
        }

        /// Return: runs `action` on the selected result now, or, while the results are
        /// still for an earlier query, on the first result of this query once it lands
        /// (nothing when it finds nothing). Never acts on a stale result.
        func submit(_ action: @escaping @MainActor (SongRecord) -> Void) {
            if isCurrent {
                pendingSubmit = nil
                if let selected {
                    action(selected)
                }
            } else {
                pendingSubmit = action
            }
        }

        init(library: LibraryStore) {
            self.library = library
        }

        func reset() {
            task?.cancel()
            recorder.cancel()
            pendingSubmit = nil
            query = ""
            resultsQuery = ""
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
                recorder.cancel()
                results = []
                resultsQuery = ""
                selection = 0
                pendingSubmit = nil
                return
            }
            let library = library
            task = Task { [weak self] in
                do {
                    let found = try await library.searchWithTier(query: text)
                    guard !Task.isCancelled else { return }
                    self?.land(Array(found.records.prefix(Self.limit)), for: text)
                    self?.recorder.resultsShown(
                        .stage,
                        tier: found.firstTier,
                        count: found.records.count,
                    )
                } catch {
                    guard !Task.isCancelled else { return }
                    self?.errorMessage = UserMessage.describe(error)
                    self?.resultsQuery = text
                    self?.pendingSubmit = nil
                }
            }
        }

        private func land(_ found: [SongRecord], for text: String) {
            results = found
            resultsQuery = text
            selection = 0
            errorMessage = nil
            if let pending = pendingSubmit {
                pendingSubmit = nil
                if let first = found.first {
                    pending(first)
                }
            }
        }
    }
#endif
