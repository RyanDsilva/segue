import Foundation
import Library
import Observation

/// The song library as the main window sees it: the full catalog, the (debounced) search
/// results, the selection, and the open song editor (new or existing song).
///
/// Every navigation that would close the editor goes through `navigate(_:)`, which asks
/// before discarding unsaved edits (`pendingNavigation`).
@MainActor
@Observable
public final class LibraryViewModel {
    /// What the detail pane shows.
    public enum Detail: Equatable {
        case empty
        case song(SongID)
        case newSong
    }

    /// Every song, by title. Setlists resolve their entries against this.
    public private(set) var catalog: [SongRecord] = []
    /// Songs matching `query` (all songs when the query is blank).
    public private(set) var results: [SongRecord] = []
    /// Whether a search is in flight (results may be stale).
    public private(set) var isSearching = false
    /// The last failure, shown as a dismissible banner.
    public var errorMessage: String?

    /// The search field text. Changes are debounced before hitting the index.
    public var query = "" {
        didSet {
            if query != oldValue {
                scheduleSearch()
            }
        }
    }

    /// The song the detail pane is about, if any. Change it with `select(_:)`.
    public private(set) var selection: SongID? {
        didSet {
            if listSelection != selection {
                listSelection = selection
            }
        }
    }

    /// The list's highlighted row (bound to the `List`). Clicking a row asks to navigate;
    /// if the user cancels the unsaved-changes prompt it snaps back to `selection`.
    public var listSelection: SongID? {
        didSet {
            if listSelection != oldValue, listSelection != selection {
                select(listSelection)
            }
        }
    }

    /// What the detail pane shows.
    public private(set) var detail: Detail = .empty

    /// The open editor: the new-song editor (`detail == .newSong`) or an edit of the
    /// selected song. Nil when the detail pane shows a rendered song or nothing.
    public private(set) var editor: SongEditorViewModel?

    /// A navigation waiting on the user's answer to "save your edits?". Non-nil while the
    /// unsaved-changes prompt is shown.
    public private(set) var pendingNavigation: PendingNavigation?

    /// A deferred navigation (select another song, switch section, ...).
    public struct PendingNavigation {
        /// The title of the song being edited, for the prompt.
        public let songTitle: String
        let action: @MainActor () -> Void
        /// Undoes any UI state that already moved (a list highlight) if the user stays.
        let onCancel: (@MainActor () -> Void)?
    }

    /// How the user answered the unsaved-changes prompt.
    public enum UnsavedChangesChoice {
        case save
        case discard
        case cancel
    }

    private let store: LibraryStore
    private let debounce: Duration
    private var searchTask: Task<Void, Never>?
    private var catalogIndex: [SongID: SongRecord] = [:]

    public init(store: LibraryStore, debounce: Duration = .milliseconds(200)) {
        self.store = store
        self.debounce = debounce
    }

    /// Looks up a song in the catalog.
    public func song(id: SongID) -> SongRecord? {
        catalogIndex[id]
    }

    /// Whether the query is non-blank.
    public var isFiltering: Bool {
        !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Reloads the catalog and re-runs the current search.
    public func reload() async {
        do {
            let songs = try await store.allSongs()
            catalog = songs
            catalogIndex = Dictionary(songs.map { ($0.id, $0) }) { first, _ in first }
            try await runSearch(query)
        } catch {
            errorMessage = UserMessage.describe(error)
        }
        if case let .song(id) = detail, catalogIndex[id] == nil {
            // The song went away (external delete): drop it and any edit of it.
            selection = nil
            detail = .empty
            editor = nil
        }
    }

    /// Rescans the folder for external edits, then reloads.
    public func refresh() async {
        do {
            try await store.refresh()
        } catch {
            errorMessage = UserMessage.describe(error)
        }
        await reload()
    }

    /// Deletes and rebuilds the index from the files on disk, then reloads.
    public func rebuildIndex() async {
        do {
            try await store.rebuildIndex()
        } catch {
            errorMessage = UserMessage.describe(error)
        }
        await reload()
    }

    // MARK: Navigation

    /// Whether the open editor holds edits that would be lost by closing it.
    public var hasUnsavedEdits: Bool {
        editor?.hasUnsavedChanges ?? false
    }

    /// Runs `action` (a navigation that closes the editor) now if nothing would be lost,
    /// otherwise holds it in `pendingNavigation` until the user answers the prompt.
    /// `onCancel` runs if the user stays in the editor (or saving fails).
    public func navigate(
        _ action: @escaping @MainActor () -> Void,
        onCancel: (@MainActor () -> Void)? = nil,
    ) {
        guard let editor, editor.hasUnsavedChanges else {
            closeEditor()
            action()
            return
        }
        let title = editor.document.metadata.title?.trimmingCharacters(in: .whitespaces) ?? ""
        pendingNavigation = PendingNavigation(
            songTitle: title.isEmpty ? "Untitled" : title,
            action: action,
            onCancel: onCancel,
        )
    }

    /// Answers the unsaved-changes prompt: save then navigate, discard then navigate, or
    /// stay in the editor.
    public func resolvePendingNavigation(_ choice: UnsavedChangesChoice) async {
        guard let pending = pendingNavigation else { return }
        pendingNavigation = nil
        switch choice {
        case .cancel:
            pending.onCancel?()
        case .discard:
            closeEditor()
            pending.action()
        case .save:
            // A failed save keeps the editor open with its error shown.
            guard let editor, await editor.commit() != nil else {
                pending.onCancel?()
                return
            }
            closeEditor()
            pending.action()
        }
    }

    /// Selects a song in the list (asking first if that would lose unsaved edits).
    public func select(_ id: SongID?) {
        guard let id else {
            // Deselecting (e.g. clicking empty list space) never closes an open editor.
            if editor == nil {
                selection = nil
                detail = .empty
            } else {
                restoreListSelection()
            }
            return
        }
        // Re-selecting the song already shown (or being edited) is not a navigation.
        guard detail != .song(id) else { return }
        let show: @MainActor () -> Void = { [weak self] in
            self?.selection = id
            self?.detail = .song(id)
        }
        let stay: @MainActor () -> Void = { [weak self] in self?.restoreListSelection() }
        navigate(show, onCancel: stay)
    }

    /// Opens the editor for a new song (asking first if that would lose unsaved edits).
    public func beginNewSong() {
        if detail == .newSong, editor != nil {
            return
        }
        navigate { [weak self] in self?.openNewSongEditor() }
    }

    /// Opens the editor on the selected song's source.
    public func beginEditing(_ record: SongRecord) {
        guard !record.isReadOnly else { return }
        let id = record.id
        navigate { [weak self] in
            guard let self else { return }
            selection = id
            detail = .song(id)
            let save: (String) async throws -> SongRecord = { [weak self] source in
                guard let self else { throw CancellationError() }
                return try await updateSong(id: id, source: source)
            }
            editor = SongEditorViewModel(mode: .edit(id), source: record.source, save: save)
        }
    }

    /// Editor "Cancel": asks before discarding unsaved edits.
    public func cancelEditing() {
        navigate {}
    }

    /// Editor "Save": saves and closes the editor (a new song becomes the selection).
    public func saveEditor() async {
        guard let editor, await editor.commit() != nil else { return }
        closeEditor()
    }

    /// Moves the list highlight back to the song actually shown, after the table has
    /// finished applying the click that moved it.
    private func restoreListSelection() {
        Task { @MainActor [weak self] in
            guard let self else { return }
            listSelection = selection
        }
    }

    private func openNewSongEditor() {
        selection = nil
        detail = .newSong
        editor = SongEditorViewModel(mode: .create, source: "") { [weak self] source in
            guard let self else { throw CancellationError() }
            return try await createSong(source: source)
        }
    }

    /// Closes the editor without saving. Leaving the new-song editor shows nothing.
    private func closeEditor() {
        editor = nil
        if detail == .newSong {
            detail = selection.map(Detail.song) ?? .empty
        }
    }

    // MARK: Songs

    /// Creates a song from `source`, selects it and returns it.
    public func createSong(source: String) async throws -> SongRecord {
        let record = try await store.createSong(source: source)
        await reload()
        selection = record.id
        detail = .song(record.id)
        return record
    }

    /// Saves new ChordPro `source` for song `id`.
    public func updateSong(id: SongID, source: String) async throws -> SongRecord {
        let record = try await store.updateSong(id: id, source: source)
        await reload()
        return record
    }

    /// Searches the index (FTS plus romanized-Hindi normalization, so "pyar" finds
    /// "Pyaar"). A blank query returns the whole catalog.
    public func search(_ query: String) async throws -> [SongRecord] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? catalog : try await store.search(query: trimmed)
    }

    private func scheduleSearch() {
        searchTask?.cancel()
        isSearching = true
        let query = query
        let debounce = debounce
        searchTask = Task { [weak self] in
            do {
                try await Task.sleep(for: debounce)
                try await self?.runSearch(query)
            } catch is CancellationError {
                return
            } catch {
                self?.errorMessage = UserMessage.describe(error)
            }
            self?.isSearching = false
        }
    }

    private func runSearch(_ query: String) async throws {
        let found = try await search(query)
        try Task.checkCancellation()
        // A newer keystroke may have changed the query while the index was busy.
        guard query == self.query else { return }
        results = found
        isSearching = false
    }
}
