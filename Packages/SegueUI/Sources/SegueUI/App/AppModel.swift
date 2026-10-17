#if os(macOS)
    import Foundation
    import Library
    import Observation
    import Setlists
    import Support

    /// Process-wide dependencies, built by the app target and handed to `AppModel`.
    @MainActor
    public struct AppDependencies {
        public var fileSystem: any FileSystem
        public var clock: any Clock
        public var ids: any IDGenerator
        public var location: LibraryLocation
        /// Test-only library folder (`-SegueLibraryPath`): bypasses the bookmark and the panels.
        public var libraryOverride: URL?
        /// Test-only (`-SegueRememberLibrary`): also store `libraryOverride` as the library
        /// bookmark, so a later launch without the override exercises the stored-bookmark path.
        public var rememberLibraryOverride: Bool

        public init(
            fileSystem: any FileSystem,
            clock: any Clock,
            ids: any IDGenerator,
            location: LibraryLocation,
            libraryOverride: URL? = nil,
            rememberLibraryOverride: Bool = false,
        ) {
            self.fileSystem = fileSystem
            self.clock = clock
            self.ids = ids
            self.location = location
            self.libraryOverride = libraryOverride
            self.rememberLibraryOverride = rememberLibraryOverride
        }
    }

    /// Top-level app state: which library is open (if any) and the live performance session.
    @MainActor
    @Observable
    public final class AppModel {
        public enum State {
            /// Resolving the stored library at launch.
            case starting
            /// No usable library: the chooser is shown.
            case needsLibrary(NeedsLibraryReason)
            /// Opening the stores on a folder.
            case opening(URL)
            /// The library is open.
            case ready(LibrarySession)
        }

        /// Why the chooser is shown.
        public enum NeedsLibraryReason: Equatable {
            case firstLaunch
            /// The stored folder is no longer reachable (moved, deleted, stale bookmark).
            case accessLost(URL?)
            /// Opening the folder failed.
            case openFailed(String)
        }

        public private(set) var state: State = .starting
        /// The open performance, shown in the live window while non-nil.
        public var live: LiveViewModel?
        /// A performance waiting on the user's answer to "some songs are missing"; non-nil
        /// while that prompt is shown.
        public private(set) var pendingPerformance: PerformanceCheck?

        /// A setlist about to be performed with entries whose songs are gone.
        public struct PerformanceCheck: Equatable {
            public let setlistName: String
            /// 1-based positions of the entries whose song is no longer in the library.
            public let missingPositions: [Int]
            /// The songs that can be performed, in setlist order.
            public let songs: [SongRecord]
        }

        private let dependencies: AppDependencies

        public init(dependencies: AppDependencies) {
            self.dependencies = dependencies
        }

        /// The open library session, if any.
        public var session: LibrarySession? {
            if case let .ready(session) = state {
                session
            } else {
                nil
            }
        }

        /// Opens the test override, the stored library, or shows the chooser.
        public func start() async {
            guard case .starting = state else { return }
            if let override = dependencies.libraryOverride {
                await open(override, remember: dependencies.rememberLibraryOverride)
                return
            }
            switch dependencies.location.resolveStored() {
            case .notChosen:
                state = .needsLibrary(.firstLaunch)
            case let .lost(url):
                state = .needsLibrary(.accessLost(url))
            case let .resolved(url):
                await open(url, remember: false)
            }
        }

        /// "Create Library": save panel suggesting `~/Music/Segue`.
        public func createLibrary() async {
            do {
                guard let url = try await dependencies.location.createFolder() else { return }
                await adopt(url)
            } catch {
                state = .needsLibrary(.openFailed(UserMessage.describe(error)))
            }
        }

        /// "Choose Existing Folder": open panel.
        public func chooseLibrary() async {
            let hint: URL? = switch state {
            case let .needsLibrary(.accessLost(url)): url
            case let .ready(session): session.root.url
            default: nil
            }
            guard let url = await dependencies.location.chooseExistingFolder(startingAt: hint)
            else { return }
            await adopt(url)
        }

        /// Opens a folder the user just picked. The previous library's security scope is
        /// released only once the new library has opened; if opening fails, the previous
        /// library stays open and keeps its access.
        private func adopt(_ url: URL) async {
            let location = dependencies.location
            guard let access = location.startAccess(url) else {
                await open(url, remember: true)
                return
            }
            if await open(url, remember: true) {
                location.commit(access)
            } else {
                location.abandon(access)
            }
        }

        /// Opens the library at `url`; returns whether it is now the open library.
        @discardableResult
        private func open(_ url: URL, remember: Bool) async -> Bool {
            let previous = state
            state = .opening(url)
            do {
                let session = try await LibrarySession.open(
                    root: LibraryRoot(url: url),
                    dependencies: dependencies,
                )
                if remember {
                    do {
                        try dependencies.location.remember(url)
                    } catch {
                        // The library is open and usable; only the next launch is affected.
                        session.library.errorMessage = "Segue opened “\(url.lastPathComponent)” "
                            + "but could not remember it (\(UserMessage.describe(error))). "
                            + "You will be asked to choose it again next time."
                    }
                }
                live = nil
                pendingPerformance = nil
                state = .ready(session)
                return true
            } catch {
                let message = UserMessage.describe(error)
                if case let .ready(session) = previous {
                    // Keep the working library; surface the failure in it.
                    session.library.errorMessage = message
                    state = previous
                } else {
                    state = .needsLibrary(.openFailed(message))
                }
                return false
            }
        }

        /// Whether the stage is up (library commands are disabled meanwhile).
        public var isPerforming: Bool {
            live != nil
        }

        /// Prepares to perform `setlist`: rescans the library so the stage shows the songs
        /// as they are on disk now, then starts the performance and returns true (the caller
        /// presents the stage). When entries point at songs that are gone, nothing starts:
        /// the check is held in `pendingPerformance` for the user to confirm, and it returns
        /// false.
        public func perform(_ setlist: Setlist) async -> Bool {
            guard let session, live == nil else { return false }
            await session.library.refresh()
            var songs: [SongRecord] = []
            var missing: [Int] = []
            for (offset, entry) in setlist.entries.enumerated() {
                if let song = session.library.song(id: entry.songId) {
                    songs.append(song)
                } else {
                    missing.append(offset + 1)
                }
            }
            guard missing.isEmpty else {
                pendingPerformance = PerformanceCheck(
                    setlistName: setlist.name,
                    missingPositions: missing,
                    songs: songs,
                )
                return false
            }
            live = LiveViewModel(setlistName: setlist.name, songs: songs)
            return true
        }

        /// "Perform Without Them": starts the held performance with the songs that remain.
        /// Returns true when the caller should present the stage.
        public func confirmPendingPerformance() -> Bool {
            guard let check = pendingPerformance else { return false }
            pendingPerformance = nil
            guard !check.songs.isEmpty, live == nil else { return false }
            live = LiveViewModel(setlistName: check.setlistName, songs: check.songs)
            return true
        }

        /// Drops the held performance.
        public func cancelPendingPerformance() {
            pendingPerformance = nil
        }
    }

    /// An open library: both stores plus the view models of the main window.
    @MainActor
    @Observable
    public final class LibrarySession {
        /// Sidebar destinations of the main window.
        public enum Section: Hashable {
            case library
            case setlists
        }

        public let root: LibraryRoot
        /// The sidebar destination shown.
        public var section: Section? = .library {
            didSet {
                if sidebarSelection != section {
                    sidebarSelection = section
                }
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

        init(root: LibraryRoot, library: LibraryViewModel, setlists: SetlistsViewModel) {
            self.root = root
            self.library = library
            self.setlists = setlists
        }

        static func open(root: LibraryRoot, dependencies: AppDependencies) async throws
            -> LibrarySession
        {
            let libraryStore = LibraryStore(
                fileSystem: dependencies.fileSystem,
                clock: dependencies.clock,
                ids: dependencies.ids,
            )
            try await libraryStore.open(root: root)
            let setlistStore = SetlistStore(
                fileSystem: dependencies.fileSystem,
                clock: dependencies.clock,
                ids: dependencies.ids,
            )
            let issues = try await setlistStore.load(root: root)
            let library = LibraryViewModel(store: libraryStore)
            await library.reload()
            let setlists = SetlistsViewModel(store: setlistStore, loadIssues: issues)
            await setlists.reload()
            return LibrarySession(root: root, library: library, setlists: setlists)
        }
    }
#endif
