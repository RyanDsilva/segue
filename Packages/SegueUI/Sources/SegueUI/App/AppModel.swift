#if os(macOS)
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

        public init(
            fileSystem: any FileSystem,
            clock: any Clock,
            ids: any IDGenerator,
            location: LibraryLocation,
            libraryOverride: URL? = nil,
            rememberLibraryOverride: Bool = false,
            shapeLibraryURL: URL? = nil,
            live: LiveDependencies? = nil,
        ) {
            self.live = live ?? LiveDependencies(settings: LiveSettingsStore(defaults: .standard))
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
        }

        public private(set) var state: State = .starting
        /// The run on stage (gig or rehearsal), shown in the stage window while non-nil.
        public var live: LiveSession?

        let dependencies: AppDependencies

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
                resetShowState()
                state = .ready(session)
                await runShowLaunchCheck()
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

        // MARK: Phase 2 show state (lifecycle in AppModel+Shows.swift)

        /// The unfinished show the launch check found (< 12 h old): "Resume show?" is shown
        /// while non-nil.
        public internal(set) var pendingResume: ShowRecord?

        /// Reorder reviews waiting for Save/Discard (show end, or shows auto-closed at
        /// launch), oldest first. The main window presents the first as `ReorderDiffSheet`.
        public internal(set) var pendingReorderReviews: [ReorderDiff] = []

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
