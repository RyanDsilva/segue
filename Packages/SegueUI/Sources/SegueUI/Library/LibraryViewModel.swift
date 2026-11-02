import Diagrams
import Foundation
import Library
import ModelPort
import Observation
import Services

/// The song library as the main window sees it: the full catalog, the (debounced) search
/// results, the selection, and the open song editor (new or existing song).
///
/// Every navigation that would close the editor goes through `navigate(_:)`, which saves
/// the edits first (autosave, WS2a 3.4) and asks only when that save fails
/// (`pendingNavigation`).
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
    public internal(set) var catalog: [SongRecord] = []
    /// Songs matching `query` (all songs when the query is blank).
    public internal(set) var results: [SongRecord] = []
    /// Whether a search is in flight (results may be stale).
    public private(set) var isSearching = false
    /// The last failure, shown as a dismissible banner.
    public var errorMessage: String?
    /// Song files the last scan could not load (reported, never deleted).
    public private(set) var loadIssues: [LibraryLoadIssue] = []
    /// A short confirmation for the bottom bar ("All changes saved", "Added … to …"),
    /// cleared after 1.5 s.
    public internal(set) var transientMessage: String?

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
            if !filterState.query.isEmpty, oldValue.query.isEmpty {
                SegueTips.donate(SegueTips.searched)
            }
        }
    }

    /// The smart filter (or built-in filter) the list is narrowed to before the search and
    /// chips apply (P3-6). Set by the session from the sidebar selection.
    public var scope: LibraryScope = .all {
        didSet {
            if scope != oldValue {
                scheduleSearch()
            }
        }
    }

    /// Every tag in the library with its song count, most used first (chips, sidebar).
    public internal(set) var tags: [TagCount] = []
    /// "Last played" / "times played" per song, from the play projection.
    public internal(set) var playStats: [SongID: PlayStats] = [:]
    /// Bumped on every reload, so views that search on their own know to search again.
    public internal(set) var catalogRevision = 0

    /// The song the detail pane is about, if any. Change it with `select(_:)`.
    public internal(set) var selection: SongID? {
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
            if multiSelection.focus != listSelection {
                multiSelection = ListSelection(single: listSelection)
            }
        }
    }

    /// The list's selected rows (R84: ⌘-click, ⇧-click, ⇧↑ / ⇧↓). Its focus is
    /// `listSelection`, the song the detail pane and single-song commands use; Add to
    /// Setlist adds every selected song.
    var multiSelection = ListSelection<SongID>() {
        didSet {
            if listSelection != multiSelection.focus {
                listSelection = multiSelection.focus
            }
        }
    }

    /// The selected songs in list order (one when a single row is selected).
    var selectedSongs: [SongID] {
        multiSelection.ordered(in: results.map(\.id))
    }

    /// What the detail pane shows.
    public internal(set) var detail: Detail = .empty

    /// The user's chord shape library (loaded from Application Support when the library
    /// opens): every diagram the editor and song page draw consults it after the song's
    /// own `{define}`s.
    public internal(set) var userShapes: UserShapeLibrary = .empty

    /// Settings > Instrument (P8-4): the song page and the editor preview show bass notes
    /// when its bass view is on. The session hands it over when the library opens.
    @ObservationIgnored var instrument: InstrumentProfileStore?
    /// The previews' singer toggle (P9-2 section 7), shared with the editor.
    @ObservationIgnored var preview: PreviewPrefs?
    /// Heard chords and walk-up auditions (P8-6); the app hands it over with the services.
    @ObservationIgnored var sound: SoundSession? {
        didSet { makePlayAlong() }
    }

    /// The song pane's Play along bar (P8-6 10.3), made when sound arrives (observed, so the
    /// pane's button appears then), and its song.
    var playAlong: PlayAlong?
    @ObservationIgnored var playAlongSong: SongID?
    /// The last walk-up sidecar write from the library; the next waits for it (P8-4b).
    @ObservationIgnored var walkUpWrite: Task<Void, Never>?
    /// The fill span selected in the song pane's preview (P8-7 12.1), and its song.
    @ObservationIgnored let spanSelection = ChordSpanSelection()
    /// Slot times per song version (P8-8 section 5.9).
    @ObservationIgnored let times = SongTimeCache()
    @ObservationIgnored var spanSong: SongID?
    /// The fill editor sheet while it is open from the library, and the sheets a gig closed
    /// (kept for the next open of the same span, never saved).
    var fillEditor: FillEditorModel?
    /// A fill sheet opened from the Walk-ups list (presented by the list).
    @ObservationIgnored weak var listFillEditor: FillEditorModel?
    @ObservationIgnored var fillDrafts: [String: FillEditorModel] = [:]
    /// A one-time note after saving a fill with the bass-note view off.
    var fillNote: String?
    /// The song whose Walk-ups list is open from the library (P8-4b 8.9).
    var walkUpsSongID: SongID?

    /// The open editor: the new-song editor (`detail == .newSong`) or an edit of the
    /// selected song. Nil when the detail pane shows a rendered song or nothing.
    public internal(set) var editor: SongEditorViewModel? {
        didSet {
            if let editor, editor !== oldValue {
                editor.services = services
                services.record(.editorOpened(editor.editorMode == .visual ? .visual : .text))
                if editor.editorMode == .visual {
                    SegueTips.donate(SegueTips.visualEditorOpened)
                }
            }
        }
    }

    /// Records analytics events (WS3 spec 5); the session hands over the app's hub.
    @ObservationIgnored public var services: ServicesHub = .disabled {
        didSet {
            searchRecorder.services = services
            builderSearchRecorder.services = services
        }
    }

    /// Days since the first launch, set by the session when the library opens (rows 13).
    @ObservationIgnored var daysSinceFirstLaunch: DaysBucket = .zero

    /// Row 17 for the library's search field.
    @ObservationIgnored let searchRecorder = SearchRecorder()
    /// Row 17 for the setlist builder's library column.
    @ObservationIgnored let builderSearchRecorder = SearchRecorder()

    /// A navigation held because the editor's edits could not be saved (a conflict or a
    /// failed write). Non-nil while the "aren't saved" prompt is shown.
    public internal(set) var pendingNavigation: PendingNavigation?

    /// A deferred navigation (select another song, switch section, quit, ...).
    public struct PendingNavigation {
        /// The title of the song being edited, for the prompt.
        public let songTitle: String
        let action: @MainActor () -> Void
        /// Undoes any UI state that already moved (a list highlight) if the user stays.
        let onCancel: (@MainActor () -> Void)?
    }

    /// How the user answered the "aren't saved" prompt.
    public enum UnsavedChangesChoice {
        /// Keep the song's file as it is and save the edits as a new song.
        case saveAsCopy
        case discard
        case cancel
    }

    let store: LibraryStore
    /// The autosave timing every editor opened here uses.
    let autosave: AutosaveTiming
    /// The revision the open editor's text is based on (see `openEditor`).
    var editorBase: RevisionBox?
    /// The ID a new song's editor created on its first save, so later saves update (and
    /// rename) it; nil for other editors.
    var createdSong: CreatedSong?
    var transientTask: Task<Void, Never>?
    /// The main window's undo manager (Edit > Undo for deletes, import, metadata).
    @ObservationIgnored weak var undoManager: UndoManager?
    /// Undo targets of Move to Trash, one per song.
    let trashTargets = UndoTargets<SongID>()
    /// What the last import did, shown in the summary bar until dismissed.
    public internal(set) var importSummary: ImportSummary?
    /// A show is on stage: the main window takes no imports or drops meanwhile.
    public internal(set) var isPerforming = false
    /// The paste review sheet's model while it is open (P3-4).
    public internal(set) var pasteReview: PasteReviewModel?
    /// The AI router the review sheet refines with; the session hands over the app's.
    @ObservationIgnored public var aiRouter = Router(providers: [])
    /// Undo targets of metadata edits, one per song (3.9.1).
    let metadataTargets = UndoTargets<SongID>()
    /// Metadata undo and redo writes, run in order.
    var metadataWork: Task<Void, Never>?
    /// Undo targets of Import, one per import.
    let importTargets = UndoTargets<Int>()
    var importCount = 0
    /// Undo/redo file work of imports, run in order.
    var importWork: Task<Void, Never>?
    private let debounce: Duration
    private var searchTask: Task<Void, Never>?
    /// Bumped per scheduled search, so only the newest one clears `isSearching`.
    private var searchGeneration = 0
    var catalogIndex: [SongID: SongRecord] = [:]
    /// The `.cho` file name of every song seen this run, kept after its file goes, so a
    /// missing medley member can be named ("tum-hi-ho.cho is missing", R188).
    @ObservationIgnored var knownFileNames: [SongID: String] = [:]
    /// Hands `knownFileNames` on after each catalog load (the setlist store saves them).
    @ObservationIgnored var onFileNames: (@MainActor ([SongID: String]) async -> Void)?

    public init(
        store: LibraryStore,
        debounce: Duration = .milliseconds(200),
        autosave: AutosaveTiming = .standard,
    ) {
        self.store = store
        self.debounce = debounce
        self.autosave = autosave
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
            SegueTips.librarySongCount = songs.count
            SegueTips.isLibraryLoaded = true
            catalogIndex = Dictionary(songs.map { ($0.id, $0) }) { first, _ in first }
            for song in songs {
                knownFileNames[song.id] = URL(filePath: song.relativePath).lastPathComponent
            }
            await onFileNames?(knownFileNames)
            loadIssues = await store.loadIssues
            tags = try await store.allTags()
            playStats = try await store.playStats()
            catalogRevision += 1
            try await runSearch(filterState)
        } catch {
            errorMessage = UserMessage.describe(error)
        }
        // The song went away (external delete). Unsaved edits of it stay open: their next
        // save raises the conflict bar with "Save as New Song".
        if case let .song(id) = detail, catalogIndex[id] == nil,
           editor?.mode != .edit(id) || !hasUnsavedEdits
        {
            selection = nil
            detail = .empty
            closeEditor()
        }
        followDiskInEditor()
    }

    /// Whether the open editor edits a song whose file is no longer in the library.
    public var isEditingDeletedSong: Bool {
        guard case let .edit(id) = editor?.mode else { return false }
        return catalogIndex[id] == nil
    }

    // MARK: Songs

    /// Creates a song from `source`, selects it and returns it.
    public func createSong(source: String) async throws -> SongRecord {
        let record = try await store.createSong(source: source)
        await reload()
        recordSongsCreated(.newSong)
        selection = record.id
        detail = .song(record.id)
        return record
    }

    /// Saves new ChordPro `source` for song `id`, checked against `revision` (default: the
    /// one the store last loaded), and applies the saved record without a full reload. A
    /// conflict with the files on disk is thrown.
    public func updateSong(
        id: SongID,
        source: String,
        basedOn revision: SongRevision? = nil,
    ) async throws -> SongRecord {
        let record = try await store.updateSong(id: id, source: source, basedOn: revision)
        await applySaved(record)
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
        try await searchWithTier(state).records
    }

    /// `search(_:)` plus the index tier of the first result (nil when the free text is
    /// blank or nothing matched), for `Segue.Search.performed`.
    func searchWithTier(_ state: SongFilterState) async throws -> SearchOutcome {
        let filter = songFilter(state)
        let text = filter.text.trimmingCharacters(in: .whitespacesAndNewlines)
        let outcome = text.isEmpty
            ? SearchOutcome(records: catalog, firstTier: nil)
            : try await store.searchWithTier(query: text)
        let records = filter.hasConstraints
            ? outcome.records.filter(filter.matches)
            : outcome.records
        return SearchOutcome(records: records, firstTier: records.isEmpty ? nil : outcome.firstTier)
    }

    func scheduleSearch() {
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

    func runSearch(_ state: SongFilterState) async throws {
        let found = try await searchWithTier(state)
        try Task.checkCancellation()
        // A newer keystroke may have changed the query while the index was busy.
        guard state == filterState else { return }
        results = scoped(found.records)
        isSearching = false
        recordSearch(state, found)
    }
}
