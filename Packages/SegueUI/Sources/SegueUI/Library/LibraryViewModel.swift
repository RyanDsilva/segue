import Diagrams
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
    /// Song files the last scan could not load (reported, never deleted).
    public private(set) var loadIssues: [LibraryLoadIssue] = []
    /// A save refused because the song changed on disk; non-nil while the conflict prompt
    /// is shown.
    public private(set) var saveConflict: SaveConflict?

    /// The search field text. Changes are debounced before hitting the index.
    public var query: String {
        get { filterState.query }
        set { filterState.query = newValue }
    }

    /// The search text plus the filter chips (tags, proficiency). Changes are debounced
    /// before hitting the index.
    public var filterState = SongFilterState() {
        didSet {
            if filterState != oldValue {
                scheduleSearch()
            }
        }
    }

    /// Every tag in the library with its song count, most used first (chips, sidebar).
    public internal(set) var tags: [TagCount] = []
    /// "Last played" / "times played" per song, from the play projection.
    public internal(set) var playStats: [SongID: PlayStats] = [:]
    /// Bumped on every reload, so views that search on their own know to search again.
    public private(set) var catalogRevision = 0

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

    /// The user's chord shape library (loaded from Application Support when the library
    /// opens): every diagram the editor and song page draw consults it after the song's
    /// own `{define}`s.
    public internal(set) var userShapes: UserShapeLibrary = .empty

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

    let store: LibraryStore
    private let debounce: Duration
    private var searchTask: Task<Void, Never>?
    /// Bumped per scheduled search, so only the newest one clears `isSearching`.
    private var searchGeneration = 0
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
        filterState.isActive
    }

    /// Reloads the catalog and re-runs the current search.
    public func reload() async {
        do {
            let songs = try await store.allSongs()
            catalog = songs
            catalogIndex = Dictionary(songs.map { ($0.id, $0) }) { first, _ in first }
            loadIssues = await store.loadIssues
            tags = try await store.allTags()
            playStats = try await store.playStats()
            catalogRevision += 1
            try await runSearch(filterState)
        } catch {
            errorMessage = UserMessage.describe(error)
        }
        // The song went away (external delete). Unsaved edits of it stay open: saving then
        // offers "Save as New Song" (`isEditingDeletedSong`).
        if case let .song(id) = detail, catalogIndex[id] == nil,
           editor?.mode != .edit(id) || !hasUnsavedEdits
        {
            selection = nil
            detail = .empty
            editor = nil
        }
    }

    /// Whether the open editor edits a song whose file is no longer in the library.
    public var isEditingDeletedSong: Bool {
        guard case let .edit(id) = editor?.mode else { return false }
        return catalogIndex[id] == nil
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
            // A failed save keeps the editor open with its error shown, and so does text
            // typed while the save was in flight.
            guard let editor, let record = await editor.commit(),
                  closeAfterSave(editor, saved: record)
            else {
                pending.onCancel?()
                return
            }
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
        navigate { [weak self] in self?.openEditor(on: record) }
    }

    /// Shows `record` with its editor open on `text` (default: its source).
    private func openEditor(on record: SongRecord, text: String? = nil) {
        let id = record.id
        selection = id
        detail = .song(id)
        // Saves are checked against the revision the editor's text came from, so an edit
        // made in another app meanwhile is never silently overwritten (`saveConflict`).
        let base = RevisionBox(record.revision)
        let save: (String) async throws -> SongRecord = { [weak self] source in
            guard let self else { throw CancellationError() }
            let saved = try await updateSong(id: id, source: source, basedOn: base.revision)
            base.revision = saved.revision
            return saved
        }
        // Display toggles write the sidecar only; the editor's base revision follows the
        // sidecar it wrote, so its own toggles never read as an outside change.
        typealias PersistPrefs = (SongID, DisplayPrefs) async throws -> SongRecord
        typealias PersistLivePrefs = (SongID, LivePrefs) async throws -> SongRecord
        let persistPrefs: PersistPrefs = { [weak self] id, prefs in
            guard let self else { throw CancellationError() }
            let saved = try await updateDisplayPrefs(id: id, prefs)
            base.revision.sidecarHash = saved.revision.sidecarHash
            return saved
        }
        let persistLivePrefs: PersistLivePrefs = { [weak self] id, prefs in
            guard let self else { throw CancellationError() }
            let saved = try await updateLivePrefs(id: id, prefs)
            base.revision.sidecarHash = saved.revision.sidecarHash
            return saved
        }
        let editor = SongEditorViewModel(
            mode: .edit(id),
            source: record.source,
            prefs: record.sidecar.displayPrefs,
            livePrefs: record.sidecar.live,
            fileName: record.relativePath,
            userShapes: userShapes,
            persistPrefs: persistPrefs,
            persistLivePrefs: persistLivePrefs,
            save: save,
        )
        if let text, text != record.source {
            editor.sourceTextDidChange(text)
        }
        self.editor = editor
    }

    /// Editor "Cancel": asks before discarding unsaved edits.
    public func cancelEditing() {
        navigate {}
    }

    /// Editor "Save": saves and closes the editor (a new song becomes the selection).
    public func saveEditor() async {
        guard let editor, let record = await editor.commit() else { return }
        closeAfterSave(editor, saved: record)
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
        editor = SongEditorViewModel(
            mode: .create,
            source: "",
            userShapes: userShapes,
            persistPrefs: { [weak self] id, prefs in
                guard let self else { throw CancellationError() }
                return try await updateDisplayPrefs(id: id, prefs)
            },
            persistLivePrefs: { [weak self] id, prefs in
                guard let self else { throw CancellationError() }
                return try await updateLivePrefs(id: id, prefs)
            },
            save: { [weak self] source in
                guard let self else { throw CancellationError() }
                return try await createSong(source: source)
            },
        )
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

    /// Saves new ChordPro `source` for song `id`, checked against `revision` (default: the
    /// one the store last loaded). A conflict with the files on disk is thrown and also
    /// shown as `saveConflict`.
    public func updateSong(
        id: SongID,
        source: String,
        basedOn revision: SongRevision? = nil,
    ) async throws -> SongRecord {
        let record: SongRecord
        do {
            record = try await store.updateSong(id: id, source: source, basedOn: revision)
        } catch {
            noteConflict(error, songID: id)
            throw error
        }
        await reload()
        return record
    }

    /// Searches the index (FTS plus romanized-Hindi normalization, so "pyar" finds
    /// "Pyaar"). A blank query returns the whole catalog.
    public func search(_ query: String) async throws -> [SongRecord] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? catalog : try await store.search(query: trimmed)
    }

    /// Songs matching `state`: the free text through the index, then the typed tokens and
    /// chips (tags, proficiency, key) through `SongFilter`.
    public func search(_ state: SongFilterState) async throws -> [SongRecord] {
        let filter = state.filter(knownTags: tags.map(\.tag))
        let found = try await search(filter.text)
        return filter.hasConstraints ? found.filter(filter.matches) : found
    }

    private func scheduleSearch() {
        searchTask?.cancel()
        searchGeneration += 1
        let generation = searchGeneration
        isSearching = true
        let state = filterState
        let debounce = debounce
        searchTask = Task { [weak self] in
            do {
                try await Task.sleep(for: debounce)
                try await self?.runSearch(state)
            } catch is CancellationError {
                return
            } catch {
                self?.errorMessage = UserMessage.describe(error)
            }
            // An older search finishing late must not hide the newer one's spinner.
            if self?.searchGeneration == generation {
                self?.isSearching = false
            }
        }
    }

    private func runSearch(_ state: SongFilterState) async throws {
        let found = try await search(state)
        try Task.checkCancellation()
        // A newer keystroke may have changed the query while the index was busy.
        guard state == filterState else { return }
        results = found
        isSearching = false
    }
}

// MARK: - Saving and conflicts

extension LibraryViewModel {
    /// Closes `editor` after it saved `record`, unless text was typed while the save was in
    /// flight: then the editor stays open with that text as an unsaved change (a new song's
    /// editor becomes an edit of the song it just created). Returns whether it closed.
    @discardableResult
    private func closeAfterSave(_ editor: SongEditorViewModel, saved record: SongRecord) -> Bool {
        guard editor === self.editor else { return false }
        guard editor.source == record.source else {
            if editor.mode == .create {
                openEditor(on: record, text: editor.source)
            }
            return false
        }
        closeEditor()
        return true
    }

    /// Answers the save-conflict prompt.
    public func resolveSaveConflict(_ choice: SaveConflictChoice) async {
        guard let conflict = saveConflict else { return }
        saveConflict = nil
        guard let editor, editor.mode == .edit(conflict.songID) else { return }
        let text = editor.source
        do {
            switch choice {
            case .cancel:
                return
            case .reload:
                try await store.refresh()
                await reload()
                if let record = song(id: conflict.songID), !record.isReadOnly {
                    openEditor(on: record)
                } else {
                    closeEditor()
                }
            case .overwrite:
                _ = try await store.overwriteSong(id: conflict.songID, source: text)
                closeEditor()
                await reload()
            case .saveAsCopy:
                let record = try await store.createSong(source: text)
                closeEditor()
                await reload()
                selection = record.id
                detail = .song(record.id)
            }
        } catch {
            editor.errorMessage = UserMessage.describe(error)
            noteConflict(error, songID: conflict.songID)
        }
    }

    /// Raises the save-conflict prompt for a save refused because the files changed (or
    /// the song is gone).
    private func noteConflict(_ error: any Error, songID: SongID) {
        let kind: SongConflict
        switch error {
        case let LibraryError.conflict(_, conflict):
            kind = conflict
        case LibraryError.songNotFound:
            kind = .deleted
        default:
            return
        }
        let title = editor?.document.metadata.title?.trimmingCharacters(in: .whitespaces) ?? ""
        saveConflict = SaveConflict(
            songID: songID,
            kind: kind,
            songTitle: title.isEmpty ? "Untitled" : title,
        )
    }
}
