#if os(macOS)
    import AppKit
    import Diagrams
    import Foundation
    import Library
    import Observation
    import Setlists
    import Shows
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
        /// The user's chord shape library (lookup order step 2, after the song's
        /// `{define}`s); `nil` for none. See `defaultShapeLibraryURL`.
        public var shapeLibraryURL: URL?
        /// Live mode: settings, Shortcut runner, power source, scroll clock, key bindings.
        /// Defaults to the standard UserDefaults and the real Shortcut runner.
        public var live: LiveDependencies
        /// How an open library is claimed: the real cross-process lock, or none for tests
        /// that run several in-process app instances on one library on purpose.
        public var libraryLock: LibraryLockPolicy
        /// Menu slots later workstreams fill (Welcome, What's New, export, feedback).
        public var hooks: AppHooks
        /// Opens links and reveals files (Help links, Show in Finder).
        public var workspace: any WorkspaceActions
        /// Where File > Import Songs… gets its files.
        public var importPanel: any ImportPanel
        /// Test-only override of the autosave idle debounce (`-SegueAutosaveDelay`); nil
        /// uses `AutosavePolicy.idle`.
        public var autosaveDelay: Duration?

        public init(
            fileSystem: any FileSystem,
            clock: any Clock,
            ids: any IDGenerator,
            location: LibraryLocation,
            libraryOverride: URL? = nil,
            rememberLibraryOverride: Bool = false,
            shapeLibraryURL: URL? = nil,
            live: LiveDependencies? = nil,
            libraryLock: LibraryLockPolicy = .exclusive,
            hooks: AppHooks = AppHooks(),
            workspace: (any WorkspaceActions)? = nil,
            importPanel: (any ImportPanel)? = nil,
            autosaveDelay: Duration? = nil,
        ) {
            self.live = live ?? LiveDependencies(settings: LiveSettingsStore(defaults: .standard))
            self.hooks = hooks
            self.workspace = workspace ?? NSWorkspaceActions()
            self.importPanel = importPanel ?? OpenPanelImportPanel()
            self.autosaveDelay = autosaveDelay
            self.libraryLock = libraryLock
            self.fileSystem = fileSystem
            self.clock = clock
            self.ids = ids
            self.location = location
            self.libraryOverride = libraryOverride
            self.rememberLibraryOverride = rememberLibraryOverride
            self.shapeLibraryURL = shapeLibraryURL
        }

        /// `Application Support/<bundle id>/shape-library.json` (inside the sandbox
        /// container for the sandboxed app).
        public static func defaultShapeLibraryURL(bundleID: String) -> URL {
            URL.applicationSupportDirectory
                .appending(path: bundleID, directoryHint: .isDirectory)
                .appending(path: UserShapeLibrary.fileName, directoryHint: .notDirectory)
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
            /// Another copy of Segue (the other flavor) has the library open (B-2).
            case inUseByAnotherCopy
        }

        public private(set) var state: State = .starting
        /// The run on stage (gig or rehearsal), shown in the stage window while non-nil.
        public var live: LiveSession?

        let dependencies: AppDependencies
        @ObservationIgnored private var activationObservers: [any NSObjectProtocol] = []

        public init(dependencies: AppDependencies) {
            self.dependencies = dependencies
        }

        /// Activation picks up edits made in other apps (A19, B-16); leaving the app saves the
        /// open editor (WS2a 3.4). Neither runs while performing.
        private func observeActivation() {
            guard activationObservers.isEmpty else { return }
            let center = NotificationCenter.default
            activationObservers = [
                center.addObserver(
                    forName: NSApplication.didBecomeActiveNotification,
                    object: nil,
                    queue: .main,
                ) { [weak self] _ in
                    MainActor.assumeIsolated { self?.appDidBecomeActive() }
                },
                center.addObserver(
                    forName: NSApplication.didResignActiveNotification,
                    object: nil,
                    queue: .main,
                ) { [weak self] _ in
                    MainActor.assumeIsolated { self?.appDidResignActive() }
                },
            ]
        }

        func appDidBecomeActive() {
            guard let session, !isPerforming, !isStartingShow else { return }
            Task { await session.refreshFromDisk() }
        }

        func appDidResignActive() {
            guard let session, !isPerforming else { return }
            Task { await session.library.flushEditor() }
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
            observeActivation()
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

        /// Switching libraries is blocked while a show is on stage or starting: the run, its
        /// keep-awake assertion and the stage window belong to the open library.
        public var canSwitchLibrary: Bool {
            !isPerforming && !isStartingShow
        }

        /// "Create Library": save panel suggesting `~/Music/Segue`.
        public func createLibrary() async {
            guard canSwitchLibrary else { return }
            do {
                guard let url = try await dependencies.location.createFolder() else { return }
                await adopt(url)
            } catch {
                state = .needsLibrary(.openFailed(UserMessage.describe(error)))
            }
        }

        /// "Choose Existing Folder": open panel.
        public func chooseLibrary() async {
            guard canSwitchLibrary else { return }
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
            let root = LibraryRoot(url: url)
            // Re-opening the open library keeps its lock rather than contending with itself.
            let heldLock: LibraryLock? = if case let .ready(open) = previous, open.root == root {
                open.lock
            } else {
                nil
            }
            state = .opening(url)
            do {
                let session = try await LibrarySession.open(
                    root: root,
                    dependencies: dependencies,
                    heldLock: heldLock,
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
                resetShowState()
                state = .ready(session)
                await runShowLaunchCheck()
                return true
            } catch {
                let inUse = (error as? LibraryLock.Failure) == .inUse
                let message = inUse ? Self.inUseMessage : UserMessage.describe(error)
                if case let .ready(session) = previous {
                    // Keep the working library; surface the failure in it.
                    session.library.errorMessage = message
                    state = previous
                } else {
                    state = .needsLibrary(inUse ? .inUseByAnotherCopy : .openFailed(message))
                }
                return false
            }
        }

        /// Shown when the library is locked by another copy of Segue.
        static let inUseMessage = "This library is open in another copy of Segue. "
            + "Quit it there, then choose the library again."

        // MARK: Phase 2 show state (lifecycle in AppModel+Shows.swift)

        /// The unfinished show the launch check found (< 12 h old): "Resume show?" is shown
        /// while non-nil.
        public internal(set) var pendingResume: ShowRecord?

        /// Reorder reviews waiting for Save/Discard (show end, or shows auto-closed at
        /// launch), oldest first. The main window presents the first as `ReorderDiffSheet`.
        public internal(set) var pendingReorderReviews: [ReorderDiff] = []
        /// Why a pending review cannot be saved, by setlist (deleted or read-only since the
        /// show started): the sheet disables Save and shows this (open question 17).
        public internal(set) var reviewSaveBlockers: [SetlistID: String] = [:]
        /// Why the last "Save to Setlist" failed; the review stays up with this shown.
        public internal(set) var reviewSaveFailure: String?

        /// The pre-show checklist while it is shown (start of a show or rehearsal).
        public internal(set) var preShow: PreShowChecklist?

        /// Why the last start did not happen (every song missing, an engine error); shown as
        /// an alert until dismissed.
        public var startFailure: String?

        /// True while a start or resume is being prepared (blocks a second one).
        var isStartingShow = false

        /// Whether the stage is up (library commands are disabled meanwhile).
        public var isPerforming: Bool {
            live != nil
        }

        /// Settings > Live.
        public var liveSettings: LiveSettingsStore {
            dependencies.live.settings
        }
    }
#endif
