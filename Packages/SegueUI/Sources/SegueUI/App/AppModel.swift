#if os(macOS)
    import AppKit
    import Diagrams
    import Foundation
    import Library
    import Observation
    import Playback
    import Services
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
        /// The consent-gated services (WS3): view models record analytics events through it.
        public var services: ServicesHub
        /// The consent decisions (prompt, Settings > Privacy).
        public var consent: ConsentStore
        /// The privacy-safe diagnostic log (WS3 spec 7); nil in in-process tests.
        public var diagnosticLog: DiagnosticLog?
        /// Which app this is (`Segue.App.launched`'s `segue.flavor`).
        public var flavor: AppFlavor
        /// Help > Report a Problem's presenter (the app's hook calls `present()`).
        public var reportPresenter: ReportProblemPresenter
        /// What a bug report may attach (the diagnostic log, the MetricKit payload).
        public var diagnostics: any DiagnosticsSource
        /// Report a Problem's "Email Instead".
        public var mail: any MailComposer
        /// First run, What's New, review prompt, appearance and tips (WS2b).
        public var polish: PolishDependencies
        /// AI providers, router and availability (P3-2, `AppModel+AI.swift`); the app target
        /// replaces the deterministic-only default with its providers.
        public var ai = AIServices.deterministicOnly()
        /// The process's audio engine (P8-6): the rehearsal click and heard chords share it.
        public var audio: AudioEngineHost = .shared
        /// Where heard chords and walk-ups go (a recorder in tests). Called on the first
        /// sound, never while a gig runs (P8-6 section 9).
        public var makeSoundOutput: (@MainActor (AudioEngineHost) -> any SoundOutput) = {
            AudioEngineSoundOutput(host: $0)
        }

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
            services: ServicesHub? = nil,
            consent: ConsentStore? = nil,
            diagnosticLog: DiagnosticLog? = nil,
            flavor: AppFlavor = .appStore,
            reportPresenter: ReportProblemPresenter? = nil,
            diagnostics: (any DiagnosticsSource)? = nil,
            mail: (any MailComposer)? = nil,
            polish: PolishDependencies? = nil,
        ) {
            // In-process tests get inert polish: no review prompt, no test-run surprises.
            self.polish = polish ?? PolishDependencies(
                defaults: location.defaults,
                reviewRequester: SilentReviewRequester(),
                launch: PolishLaunch(isTestRun: true),
            )
            self.flavor = flavor
            self.reportPresenter = reportPresenter ?? ReportProblemPresenter()
            self.diagnostics = diagnostics ?? LocalDiagnostics(log: diagnosticLog, store: nil)
            self.mail = mail ?? SharingServiceMailComposer()
            self.live = live ?? LiveDependencies(settings: LiveSettingsStore(defaults: .standard))
            self.services = services ?? .inert()
            self.consent = consent ?? .inert()
            self.diagnosticLog = diagnosticLog
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

        public internal(set) var state: State = .starting
        /// The Welcome sheet's state (WS2b 4.1).
        public let onboarding = OnboardingModel()
        /// A Welcome flow or consent sheet was shown this launch: What's New waits for the
        /// next launch (never more than one of them per launch, 4.1).
        var launchPromptShown = false
        /// The What's New sheet's content while it is asked for (WS2b 4.3).
        public internal(set) var whatsNew: WhatsNewContent?
        /// A completed gig armed the review prompt; the main window fires it once the
        /// end-of-show flow is done (WS2b 4.5).
        public internal(set) var reviewPromptPending = false
        /// Files from Open With waiting for the library, the Welcome flow or a show (4.7).
        var pendingOpenURLs: [URL] = []
        /// Export Library Archive is writing the zip (WS2b 4.8).
        public internal(set) var isExporting = false
        /// The run on stage (gig or rehearsal), shown in the stage window while non-nil.
        public var live: LiveSession? {
            didSet {
                session?.library.isPerforming = live != nil
                SegueTips.isPerforming = live != nil
                // No model loads while a show runs (R65, R95).
                dependencies.ai.gate.isShowRunning = live != nil
                // No sound in a gig (R161, P8-6 section 9): before the stage is presented.
                sound.stageChanged(kind: live?.kind)
            }
        }

        /// File > Import Songs…: the open panel (or the E2E stand-in), then the import. During
        /// a show only from the main window (the panel never takes the keyboard from the
        /// stage), and only already-ChordPro files import (R109).
        public func importSongs() async {
            guard let session, !isStageKey else { return }
            await session.chooseAndImport()
        }

        let dependencies: AppDependencies
        @ObservationIgnored private var activationObservers: [any NSObjectProtocol] = []
        /// Heard chords and walk-ups (P8-6): the gate, Settings > Audio, the player.
        public let sound: SoundSession

        public init(dependencies: AppDependencies) {
            self.dependencies = dependencies
            let host = dependencies.audio
            let makeOutput = dependencies.makeSoundOutput
            sound = SoundSession(
                host: host,
                settings: AudioSettingsStore(defaults: dependencies.live.settings.defaults),
                clock: dependencies.live.scrollClock,
                makeOutput: { makeOutput(host) },
            )
            dependencies.polish.router.app = self
            OpenDocuments.shared.app = self
            observeAudio(host)
        }

        /// The engine's reports: an output change stops what was playing (and says so), a
        /// bank fallback is recorded once per launch (P8-6 8.1).
        private func observeAudio(_ host: AudioEngineHost) {
            host.onConfigurationChange = { [weak self] in
                Task { @MainActor in self?.sound.outputChanged() }
            }
            host.onBankFallback = { [weak self] in
                Task { @MainActor in self?.services.record(.errorOccurred(.soundBankLoad)) }
            }
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
            applyPolishPresets()
            if let override = dependencies.libraryOverride {
                await open(override, remember: dependencies.rememberLibraryOverride)
                await applyOnboardingOverride()
            } else {
                switch dependencies.location.resolveStored() {
                case .notChosen:
                    state = .needsLibrary(.firstLaunch)
                    beginOnboardingWithoutLibrary()
                case let .lost(url):
                    state = .needsLibrary(.accessLost(url))
                case let .resolved(url):
                    if await open(url, remember: false) {
                        continueOnboardingAfterStoredLibrary()
                    }
                }
            }
            await seedWelcomeForLaunchIfAsked()
            checkWhatsNewAtLaunch()
            runQueuedOpenRequests()
            recordLaunch()
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
                await adopt(url, created: true)
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
            await adopt(url, created: false)
        }

        /// Opens a folder the user just picked. The previous library's security scope is
        /// released only once the new library has opened; if opening fails, the previous
        /// library stays open and keeps its access.
        private func adopt(_ url: URL, created: Bool) async {
            let location = dependencies.location
            guard let access = location.startAccess(url) else {
                if await open(url, remember: true) {
                    recordLibraryChosen(url, created: created)
                }
                return
            }
            if await open(url, remember: true) {
                location.commit(access)
                recordLibraryChosen(url, created: created)
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
            let started = ContinuousClock.now
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
                if case let .ready(old) = previous, old !== session {
                    // Undo belongs to the library it was made in.
                    old.undoManager?.removeAllActions()
                    session.undoManager = old.undoManager
                }
                state = .ready(session)
                session.restoreState()
                await runShowLaunchCheck()
                await libraryOpened(session, elapsed: ContinuousClock.now - started)
                return true
            } catch {
                let inUse = (error as? LibraryLock.Failure) == .inUse
                recordError(.libraryOpenFailed, error)
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
        /// An answer to the first review is being written: the sheet disables its buttons
        /// and a second answer is ignored (R154, a double click answered twice).
        public internal(set) var isResolvingReview = false

        /// The pre-show checklist while it is shown (start of a show or rehearsal).
        public internal(set) var preShow: PreShowChecklist?

        /// Why the last start did not happen (every song missing, an engine error); shown as
        /// an alert until dismissed.
        public var startFailure: String?

        /// True while a start or resume is being prepared (blocks a second one).
        var isStartingShow = false {
            didSet {
                // A show starting first cancels an armed review prompt (the next completed
                // gig re-arms it, still once per version).
                if isStartingShow {
                    reviewPromptPending = false
                }
            }
        }

        /// Whether the stage is up (library commands are disabled meanwhile).
        public var isPerforming: Bool {
            live != nil
        }

        /// Settings > Live.
        public var liveSettings: LiveSettingsStore {
            dependencies.live.settings
        }

        /// Settings > Instrument (P8-4).
        public var instrumentProfile: InstrumentProfileStore {
            dependencies.live.instrument
        }
    }
#endif
