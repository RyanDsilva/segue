#if os(macOS)
    import Diagrams
    import Foundation
    import Library
    import Observation
    import Setlists
    import Shows
    import Support

    /// An open library: both stores plus the view models of the main window.
    @MainActor
    @Observable
    public final class LibrarySession {
        /// Sidebar destinations of the main window.
        public enum Section: Hashable {
            case library
            case gigLog
            /// The builder of one setlist.
            case setlist(SetlistID)
            /// The library list narrowed to a saved smart filter (P3-6).
            case smartFilter(SmartFilterID)
            /// The library list narrowed to songs missing a set essential (R110).
            case missingEssentials
        }

        public let root: LibraryRoot
        /// The library's machine state outside the folder (index, locks, `state.json`),
        /// keyed by its `LibraryIdentity` (P9-6 5.2).
        public let state: LibraryStateDirectory
        /// The sidebar destination shown.
        public var section: Section? = .library {
            didSet {
                if sidebarSelection != section {
                    sidebarSelection = section
                }
                if case let .setlist(id) = section, setlists.selection != id {
                    setlists.selection = id
                }
                syncLibraryScope()
            }
        }

        /// The sidebar's highlighted row (bound to the sidebar `List`). Changing it asks the
        /// library to navigate, so unsaved edits are never dropped; if the user stays in the
        /// editor it snaps back to `section`.
        public var sidebarSelection: Section? = .library {
            didSet {
                guard sidebarSelection != oldValue, sidebarSelection != section else { return }
                let target = sidebarSelection
                let show: @MainActor () -> Void = { [weak self] in self?.section = target }
                let stay: @MainActor () -> Void = { [weak self] in
                    // After the sidebar finishes applying the click that moved it.
                    Task { @MainActor in self?.sidebarSelection = self?.section }
                }
                library.navigate(show, onCancel: stay)
            }
        }

        public let library: LibraryViewModel
        public let setlists: SetlistsViewModel
        public let gigLog: GigLogViewModel
        /// Saved smart filters (P3-6): the sidebar section and the editor sheet.
        public let smartFilters: SmartFiltersViewModel
        /// The stores behind the view models, for the live session (phase 2, unit C) and the
        /// gig log (unit D).
        public let stores: LibraryStores
        /// Held for the session's lifetime so no other copy of Segue opens this library
        /// (B-2); nil under `LibraryLockPolicy.unlocked`.
        let lock: LibraryLock?
        /// Reveals files in Finder (Show in Finder) and opens links.
        let workspace: any WorkspaceActions
        /// Where File > Import Songs… gets its files.
        let importPanel: any ImportPanel
        /// Stores the section and selections for the next launch (3.10).
        @ObservationIgnored var restore: SessionRestore?
        /// The New Setlist name sheet is up (sidebar button or Setlist > New Setlist…).
        public var isNamingNewSetlist = false
        /// A one-time note of this open (the old timings folder moved to the Trash, P8-8 5.8;
        /// a Finder copy given its own identity, P9-6 5.2).
        public var upgradeNote: LibraryNote?
        /// The `{duration}` cleanup offer: how many songs hold a `{duration}` line, shown
        /// once per library (P8-8 5.7); nil when not offered.
        public var durationOffer: Int?
        /// Whether the folder sits in a file-sync service (P9-6 5.4), set after each open.
        public internal(set) var folderKind: LibraryFolderKind = .local
        /// "Don't Show Again" on the file-sync warning, remembered per library ID.
        public internal(set) var fileSyncWarningDismissed = false
        /// A song waiting on "Move to Trash?" because setlists use it (A23).
        public internal(set) var songTrashConfirmation: SongTrashConfirmation?

        /// The main window's undo manager, handed to the view models (Edit > Undo).
        @ObservationIgnored public weak var undoManager: UndoManager? {
            didSet {
                library.undoManager = undoManager
                setlists.undoManager = undoManager
                gigLog.undoManager = undoManager
                smartFilters.undoManager = undoManager
            }
        }

        init(
            root: LibraryRoot,
            state: LibraryStateDirectory,
            library: LibraryViewModel,
            setlists: SetlistsViewModel,
            stores: LibraryStores,
            lock: LibraryLock?,
            autosave: AutosaveTiming = .standard,
            workspace: any WorkspaceActions,
            importPanel: any ImportPanel,
        ) {
            self.root = root
            self.state = state
            self.lock = lock
            self.workspace = workspace
            self.importPanel = importPanel
            self.library = library
            self.setlists = setlists
            self.stores = stores
            smartFilters = SmartFiltersViewModel(store: stores.filters)
            gigLog = GigLogViewModel(shows: stores.shows, autosave: autosave) { [library] in
                await library.reload()
            }
        }

        /// Picks up changes made in other apps: rescans the songs (a clean editor follows
        /// its file) and reloads the setlists. Runs on Library > Refresh and when the app
        /// becomes active (not while performing).
        public func refreshFromDisk() async {
            await library.refresh()
            await setlists.reloadFromDisk()
            await smartFilters.reloadFromDisk()
        }

        /// Shows the builder of the setlist selected in `setlists` (after create or
        /// duplicate), or leaves a builder whose setlist is gone.
        public func followSetlistSelection() {
            if let id = setlists.selection {
                if section != .setlist(id) {
                    library.navigate { [weak self] in self?.section = .setlist(id) }
                }
            } else if case let .setlist(id) = section, setlists.setlist(id) == nil {
                section = .library
            }
        }

        /// Loads the user's chord shape library for every diagram the library draws; on
        /// failure diagrams fall back to curated and generated shapes, and the banner says why.
        private static func loadShapeLibrary(
            into library: LibraryViewModel,
            dependencies: AppDependencies,
        ) {
            if let url = dependencies.shapeLibraryURL {
                do {
                    library.userShapes = try UserShapeLibrary.load(
                        from: url,
                        fileSystem: dependencies.fileSystem,
                    )
                } catch {
                    // Diagrams fall back to curated and generated shapes; say why.
                    library.errorMessage = "Segue could not read your chord shape library "
                        + "(\(UserMessage.describe(error))), so built-in shapes are shown."
                }
            }
        }

        /// What a re-open of the open library keeps: its lock and state directory.
        struct Held {
            let lock: LibraryLock?
            let state: LibraryStateDirectory
        }

        /// `root`'s state directory and lock: `held` when re-opening the open library, else
        /// its identity resolved (a Finder copy re-keyed) and its lock taken (P9-6 5.2).
        private static func claim(
            _ root: LibraryRoot,
            dependencies: AppDependencies,
            held: Held?,
        ) throws -> (Held, isCopy: Bool) {
            if let held {
                return (held, false)
            }
            let (resolved, lock) = try LibraryState.open(
                root: root,
                location: dependencies.libraryState,
                fileSystem: dependencies.fileSystem,
                clock: dependencies.clock,
                ids: dependencies.ids,
                lock: dependencies.libraryLock.acquire,
            )
            return (Held(lock: lock, state: resolved.directory), resolved.isCopy)
        }

        /// The song store, opened on `root` with its index in `state`.
        private static func openSongs(
            _ root: LibraryRoot,
            _ state: LibraryStateDirectory,
            _ dependencies: AppDependencies,
        ) async throws -> LibraryStore {
            let store = LibraryStore(
                fileSystem: dependencies.fileSystem,
                clock: dependencies.clock,
                ids: dependencies.ids,
            )
            try await store.open(root: root, state: state)
            return store
        }

        /// Opens the stores on `root`. The library's identity is resolved and its lock taken
        /// first (or `held`, the open session's own lock when the same library is re-opened),
        /// so nothing is read while another copy of Segue has the library open.
        static func open(
            root: LibraryRoot,
            dependencies: AppDependencies,
            held: Held? = nil,
        ) async throws -> LibrarySession {
            let (claimed, isCopy) = try claim(root, dependencies: dependencies, held: held)
            let libraryStore = try await openSongs(root, claimed.state, dependencies)
            let setlistStore = SetlistStore(
                fileSystem: dependencies.fileSystem,
                clock: dependencies.clock,
                ids: dependencies.ids,
            )
            let issues = try await setlistStore.load(root: root)
            let autosave = AutosaveTiming(policy: AutosavePolicy(
                idle: dependencies.autosaveDelay ?? AutosavePolicy.idle,
            ))
            let library = LibraryViewModel(store: libraryStore, autosave: autosave)
            library.instrument = dependencies.live.instrument
            library.preview = dependencies.live.preview
            loadShapeLibrary(into: library, dependencies: dependencies)
            // Setlists save each song's file name, so a missing one is named (R191).
            library.onFileNames = { names in await setlistStore.setSongFileNames(names) }
            await library.reload()
            let setlists = SetlistsViewModel(store: setlistStore, loadIssues: issues)
            await setlists.reload()
            // Shows are loaded (and the launch check run) by `AppModel` once the session is
            // up (phase 2, unit C), so a show problem never blocks opening the library.
            let shows = ShowStore(
                fileSystem: dependencies.fileSystem,
                clock: dependencies.clock,
                playHistory: libraryStore,
            )
            let stores = LibraryStores(
                library: libraryStore,
                setlists: setlistStore,
                shows: shows,
                filters: .make(dependencies),
                fileSystem: dependencies.fileSystem,
                clock: dependencies.clock,
                ids: dependencies.ids,
            )
            let session = LibrarySession(
                root: root,
                state: claimed.state,
                library: library,
                setlists: setlists,
                stores: stores,
                lock: claimed.lock,
                autosave: autosave,
                workspace: dependencies.workspace,
                importPanel: dependencies.importPanel,
            )
            await session.loadSmartFilters()
            session.runUpgradeSteps(fileSystem: dependencies.fileSystem, isCopy: isCopy)
            session.restore = SessionRestore(defaults: dependencies.location.defaults, root: root)
            return session
        }
    }

    /// How a library session claims its folder (WS1 4.8g).
    public enum LibraryLockPolicy: Sendable {
        /// `LibraryLock` in the library's state directory: a second copy of Segue cannot open
        /// the library while this one has it.
        case exclusive
        /// No lock: only for integration tests that deliberately run several in-process
        /// app instances on one library.
        case unlocked

        func acquire(_ state: LibraryStateDirectory) throws -> LibraryLock? {
            switch self {
            case .exclusive: try LibraryLock(state: state)
            case .unlocked: nil
            }
        }
    }

    /// The open library's stores and the injected process dependencies they share.
    public struct LibraryStores: Sendable {
        public let library: LibraryStore
        public let setlists: SetlistStore
        /// Not loaded until `AppModel` runs the launch check.
        public let shows: ShowStore
        /// Saved smart filters (P3-6); the set assistant (P3-7) and Pick mode (P3-12) read
        /// them here.
        public let filters: SmartFilterStore
        public let fileSystem: any FileSystem
        public let clock: any Clock
        public let ids: any IDGenerator
    }
#endif
