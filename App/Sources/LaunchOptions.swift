import AppKit
import Foundation
import SegueUI
import Services
import Support
import VendorServices

// Debug builds only (WS1 4.8f): Release has no launch-option parser, flag strings or test
// doubles compiled in; scripts/verify-appstore.sh and verify-archive check the binary.
#if DEBUG
    /// Test-only launch arguments (used by XCUITests to start from a clean baseline):
    ///
    /// - `-SegueLibraryPath <path>`: use `<path>` as the library folder, bypassing the open panel
    ///   and the stored bookmark.
    /// - `-SegueResetState YES`: wipe UserDefaults (including the library bookmark) at launch.
    /// - `-SegueRememberLibrary YES`: also store `-SegueLibraryPath` as the library bookmark (in
    ///   the test defaults suite), as if the user had chosen it in the open panel.
    /// - `-SegueTestDefaults YES`: use the test defaults suite without any other override, so a
    ///   relaunch opens the library from the bookmark stored by an earlier test launch.
    /// - `-SegueShapeLibraryPath <file>`: read the user chord shape library from `<file>`. Test
    ///   runs without it use no shape library, so they never see the user's real shapes.
    /// - `-SegueShortcutLog <file>`: never contact Shortcuts Events; record each Shortcut the
    ///   app would run as one line in `<file>` and answer it like Shortcuts Events would by its
    ///   name's prefix (`RecordingShortcutsEvents`: fail, missing, denied, hang).
    /// - `-SegueLiveTimeScale <n>`: auto-scroll runs `n` times faster than real time (E2E #3).
    /// - `-SegueBindingsPath <file>`: read key bindings from `<file>` instead of Application
    ///   Support. Test runs without it use the default keys only.
    /// - `-SegueStartShortcut <name>` / `-SegueEndShortcut <name>`: store these Gig Mode
    ///   Shortcut names in the test suite's Live settings at launch, as if the user had set
    ///   them in Settings > Live (the Shortcuts are off by default, R18).
    /// - `-SegueWorkspaceLog <file>`: open no links and reveal nothing in Finder; record each
    ///   call as one JSON line in `<file>` (Help links, Show in Finder).
    /// - `-SegueTrashPath <dir>`: move deleted items into `<dir>` instead of the user's Trash.
    ///   Must be under `/private/tmp/segue-e2e/` (the sandbox exception).
    /// - `-SegueImportPanelPaths <p1:p2>`: File > Import Songs… "chooses" these paths instead
    ///   of showing the open panel.
    /// - `-SegueAutosaveDelay <seconds>`: the autosave idle debounce (E2E uses 0.3).
    /// - `-SegueServicesLog <file>`: Recording services adapters (WS3 14.1): every analytics
    ///   signal, breadcrumb, crash-reporter start and stop and sent report is one JSON line
    ///   in `<file>`; the diagnostic log rotates in a `Logs` folder beside it.
    /// - `-SegueFeedbackResult <ok|offline|rejected>`: how the recording report sender answers.
    /// - `-SegueMailLog <file>`: Report a Problem's "Email Instead" opens no draft; each
    ///   draft is one JSON line in `<file>` (recipient, subject, attachment names).
    /// - `-SegueServicesLive YES`: the real vendors from Info.plist (Sentry environment
    ///   `debug`, TelemetryDeck test mode), for manual live checks only. Not a test run.
    /// - `-SegueConsent <undecided|granted|declined|analyticsOnly|crashOnly|asStored>`: set
    ///   both consent decisions at launch, as if answered in the prompt (nothing is
    ///   recorded); `asStored` keeps what an earlier launch stored. Test runs without it
    ///   decline any decision still undecided, so the consent prompt only appears in the
    ///   tests that ask for it (`undecided`, or `asStored` after an unanswered prompt).
    /// - `-SegueAppearance <light|dark>`: force the app's appearance whatever the system
    ///   uses (the screenshot pass needs both).
    /// - `-SegueOnboarding <fresh|done>` (WS2b 4.1): `fresh` runs the Welcome flow again for
    ///   the override library, from page 2; `done` marks it finished. Test runs with a
    ///   library path and without this flag treat onboarding as done.
    /// - `-SegueSeedWelcome YES`: seed the Welcome songs and setlist once the library opens
    ///   (never wipes anything). Without `-SegueLibraryPath` it seeds and opens
    ///   `screenshotLibraryFolder` in the container (WS5's screenshots compose it).
    /// - `-SegueChangelogPath <file>`: read What's New from `<file>` instead of the bundle.
    /// - `-SegueLastSeenVersion <v>`: store `<v>` as the last version whose notes were seen.
    /// - `-SegueAppVersion <v>`: the running version for What's New and the review prompt.
    /// - `-SegueReviewLog <file>`: never ask the system for a review; append one line per
    ///   request to `<file>`. Test runs without it never request a review.
    /// - `-SegueTips <show|hide>`: show every tip, or none (test runs hide them by default).
    /// - `-SegueExportPath <file>`: Export Library Archive writes `<file>` without the panel.
    /// - `-SegueCompletedGigs <n>`: preset the completed-gig counter of the review prompt.
    /// (Capture flags: LaunchOptions+Capture.swift.)
    struct LaunchOptions: Sendable, Equatable {
        static let libraryPathFlag = "-SegueLibraryPath"
        static let resetStateFlag = "-SegueResetState"
        static let rememberLibraryFlag = "-SegueRememberLibrary"
        static let testDefaultsFlag = "-SegueTestDefaults"
        static let shapeLibraryPathFlag = "-SegueShapeLibraryPath"
        static let shortcutLogFlag = "-SegueShortcutLog"
        static let liveTimeScaleFlag = "-SegueLiveTimeScale"
        static let bindingsPathFlag = "-SegueBindingsPath"
        static let startShortcutFlag = "-SegueStartShortcut"
        static let endShortcutFlag = "-SegueEndShortcut"
        static let workspaceLogFlag = "-SegueWorkspaceLog"
        static let trashPathFlag = "-SegueTrashPath"
        static let importPanelPathsFlag = "-SegueImportPanelPaths"
        static let autosaveDelayFlag = "-SegueAutosaveDelay"
        static let servicesLogFlag = "-SegueServicesLog"
        static let feedbackResultFlag = "-SegueFeedbackResult"
        static let mailLogFlag = "-SegueMailLog"
        static let servicesLiveFlag = "-SegueServicesLive"
        static let consentFlag = "-SegueConsent"
        static let appearanceFlag = "-SegueAppearance"
        static let onboardingFlag = "-SegueOnboarding"
        static let seedWelcomeFlag = "-SegueSeedWelcome"
        static let changelogPathFlag = "-SegueChangelogPath"
        static let lastSeenVersionFlag = "-SegueLastSeenVersion"
        static let appVersionFlag = "-SegueAppVersion"
        static let reviewLogFlag = "-SegueReviewLog"
        static let tipsFlag = "-SegueTips"
        static let exportPathFlag = "-SegueExportPath"
        static let completedGigsFlag = "-SegueCompletedGigs"

        /// Where `-SegueSeedWelcome` puts the library when no library path is given: inside
        /// the app's own container, so no sandbox exception is needed and the user's real
        /// library bookmark is never touched (WS2b 4.2, I-4; WS5's `-SegueScreenshotLibrary`
        /// wipes and reuses it).
        static var screenshotLibraryFolder: URL {
            URL.applicationSupportDirectory
                .appending(path: "Segue-Screenshots", directoryHint: .isDirectory)
                .appending(path: "Library", directoryHint: .isDirectory)
        }

        /// `-SegueConsent` values.
        enum ConsentPreset: String, Sendable, CaseIterable {
            case undecided
            case granted
            case declined
            case analyticsOnly
            case crashOnly
            case asStored
        }

        var libraryPath: URL?
        var resetState = false
        var rememberLibrary = false
        var testDefaults = false
        var shapeLibraryPath: URL?
        var shortcutLog: URL?
        var liveTimeScale: Double?
        var bindingsPath: URL?
        var startShortcut: String?
        var endShortcut: String?
        var workspaceLog: URL?
        var trashPath: URL?
        var importPanelPaths: [URL]?
        var autosaveDelay: Double?
        var servicesLog: URL?
        var feedbackResult: RecordingFeedbackSender.Outcome?
        var mailLog: URL?
        var servicesLive = false
        var consentPreset: ConsentPreset?
        /// `-SegueAppearance`: `light` or `dark`; nil follows the system.
        var appearance: String?
        var onboarding: PolishLaunch.Onboarding?
        var seedWelcome = false
        var changelogPath: URL?
        var lastSeenVersion: String?
        var appVersion: String?
        var reviewLog: URL?
        var tips: PolishLaunch.Tips?
        var exportPath: URL?
        var completedGigs: Int?
        var screenshotLibrary = false
        /// `-SegueWindowFrame`, top-left origin on the main screen.
        var windowFrame: CGRect?
        var stageWindowed = false
        var fixedClock: Date?
        var scriptedAI: URL?
        var guideFixtures = false
        var clockRate: Double?

        init(
            libraryPath: URL? = nil,
            resetState: Bool = false,
            rememberLibrary: Bool = false,
            testDefaults: Bool = false,
            shapeLibraryPath: URL? = nil,
            shortcutLog: URL? = nil,
            liveTimeScale: Double? = nil,
            bindingsPath: URL? = nil,
            startShortcut: String? = nil,
            endShortcut: String? = nil,
            workspaceLog: URL? = nil,
            trashPath: URL? = nil,
            importPanelPaths: [URL]? = nil,
            autosaveDelay: Double? = nil,
            servicesLog: URL? = nil,
            feedbackResult: RecordingFeedbackSender.Outcome? = nil,
            servicesLive: Bool = false,
            consentPreset: ConsentPreset? = nil,
        ) {
            self.libraryPath = libraryPath
            self.resetState = resetState
            self.rememberLibrary = rememberLibrary
            self.testDefaults = testDefaults
            self.shapeLibraryPath = shapeLibraryPath
            self.shortcutLog = shortcutLog
            self.liveTimeScale = liveTimeScale
            self.bindingsPath = bindingsPath
            self.startShortcut = startShortcut
            self.endShortcut = endShortcut
            self.workspaceLog = workspaceLog
            self.trashPath = trashPath
            self.importPanelPaths = importPanelPaths
            self.autosaveDelay = autosaveDelay
            self.servicesLog = servicesLog
            self.feedbackResult = feedbackResult
            self.servicesLive = servicesLive
            self.consentPreset = consentPreset
        }

        /// Parses `arguments` (as in `ProcessInfo.arguments`; the first element is the
        /// executable). Unknown arguments are ignored; a flag without a value is ignored.
        init(arguments: [String]) {
            let values = Self.flagValues(arguments)
            libraryPath = Self.path(values[Self.libraryPathFlag], directoryHint: .isDirectory)
            shapeLibraryPath = Self.path(
                values[Self.shapeLibraryPathFlag],
                directoryHint: .notDirectory,
            )
            resetState = values[Self.resetStateFlag].map(Self.isTruthy) ?? false
            rememberLibrary = values[Self.rememberLibraryFlag].map(Self.isTruthy) ?? false
            testDefaults = values[Self.testDefaultsFlag].map(Self.isTruthy) ?? false
            shortcutLog = Self.path(values[Self.shortcutLogFlag], directoryHint: .notDirectory)
            bindingsPath = Self.path(values[Self.bindingsPathFlag], directoryHint: .notDirectory)
            startShortcut = Self.name(values[Self.startShortcutFlag])
            endShortcut = Self.name(values[Self.endShortcutFlag])
            liveTimeScale = values[Self.liveTimeScaleFlag].flatMap(Double.init).flatMap { scale in
                scale > 0 ? scale : nil
            }
            workspaceLog = Self.path(values[Self.workspaceLogFlag], directoryHint: .notDirectory)
            trashPath = Self.path(values[Self.trashPathFlag], directoryHint: .isDirectory)
            importPanelPaths = values[Self.importPanelPathsFlag].map { list in
                list.split(separator: ":").compactMap { part in
                    Self.path(String(part), directoryHint: .inferFromPath)
                }
            }
            autosaveDelay = values[Self.autosaveDelayFlag].flatMap(Double.init).flatMap { delay in
                delay >= 0 ? delay : nil
            }
            servicesLog = Self.path(values[Self.servicesLogFlag], directoryHint: .notDirectory)
            feedbackResult = values[Self.feedbackResultFlag]
                .flatMap(RecordingFeedbackSender.Outcome.init(rawValue:))
            mailLog = Self.path(values[Self.mailLogFlag], directoryHint: .notDirectory)
            servicesLive = values[Self.servicesLiveFlag].map(Self.isTruthy) ?? false
            consentPreset = values[Self.consentFlag].flatMap(ConsentPreset.init(rawValue:))
            appearance = values[Self.appearanceFlag]
                .flatMap { ["light", "dark"].contains($0) ? $0 : nil }
            onboarding = values[Self.onboardingFlag].flatMap(PolishLaunch.Onboarding.init)
            seedWelcome = values[Self.seedWelcomeFlag].map(Self.isTruthy) ?? false
            changelogPath = Self.path(values[Self.changelogPathFlag], directoryHint: .notDirectory)
            lastSeenVersion = Self.name(values[Self.lastSeenVersionFlag])
            appVersion = Self.name(values[Self.appVersionFlag])
            reviewLog = Self.path(values[Self.reviewLogFlag], directoryHint: .notDirectory)
            tips = values[Self.tipsFlag].flatMap(PolishLaunch.Tips.init)
            exportPath = Self.path(values[Self.exportPathFlag], directoryHint: .notDirectory)
            completedGigs = values[Self.completedGigsFlag].flatMap(Int.init).flatMap { count in
                count >= 0 ? count : nil
            }
            parseCapture(values)
        }

        static let flags: Set = [
            libraryPathFlag, resetStateFlag, rememberLibraryFlag, testDefaultsFlag,
            shapeLibraryPathFlag, shortcutLogFlag, liveTimeScaleFlag, bindingsPathFlag,
            startShortcutFlag, endShortcutFlag, workspaceLogFlag, trashPathFlag,
            importPanelPathsFlag, autosaveDelayFlag, servicesLogFlag, feedbackResultFlag,
            servicesLiveFlag, consentFlag, appearanceFlag, mailLogFlag,
            onboardingFlag, seedWelcomeFlag, changelogPathFlag, lastSeenVersionFlag,
            appVersionFlag, reviewLogFlag, tipsFlag, exportPathFlag, completedGigsFlag,
            screenshotLibraryFlag, windowFrameFlag, stageWindowedFlag, fixedClockFlag,
            scriptedAIFlag, guideFixturesFlag, clockRateFlag,
        ]

        /// A Shortcut name with surrounding blanks removed; nil when blank.
        private static func name(_ value: String?) -> String? {
            guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !trimmed.isEmpty
            else { return nil }
            return trimmed
        }

        static func path(_ value: String?, directoryHint: URL.DirectoryHint) -> URL? {
            guard let value, !value.isEmpty else { return nil }
            return URL(filePath: value, directoryHint: directoryHint).standardizedFileURL
        }

        /// Whether any test-only argument was passed.
        var isTestRun: Bool {
            libraryPath != nil || resetState || rememberLibrary || testDefaults
                || shapeLibraryPath != nil || shortcutLog != nil || liveTimeScale != nil
                || bindingsPath != nil || startShortcut != nil || endShortcut != nil
                || workspaceLog != nil || trashPath != nil || importPanelPaths != nil
                || autosaveDelay != nil || servicesLog != nil || feedbackResult != nil
                || consentPreset != nil || mailLog != nil
                || onboarding != nil || seedWelcome || changelogPath != nil
                || lastSeenVersion != nil || appVersion != nil || reviewLog != nil
                || tips != nil || exportPath != nil || completedGigs != nil
                || screenshotLibrary || windowFrame != nil || stageWindowed
                || fixedClock != nil || scriptedAI != nil || guideFixtures || clockRate != nil
        }

        /// The library folder this launch opens without the bookmark: `-SegueLibraryPath`, or
        /// the screenshot folder for `-SegueSeedWelcome` without a path.
        var libraryOverride: URL? {
            if let libraryPath {
                return libraryPath
            }
            guard seedWelcome else { return nil }
            let folder = Self.screenshotLibraryFolder
            try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            return folder
        }

        static func isTruthy(_ value: String) -> Bool {
            ["yes", "true", "1"].contains(value.lowercased())
        }
    }

    /// Where app state lives, and clearing it for `-SegueResetState`.
    enum AppStateReset {
        /// Suffix of the separate defaults suite used by test runs.
        static let testSuiteSuffix = ".uitest"

        /// The defaults store for this launch. Test runs (any test launch argument) use their own
        /// suite, so running the E2E suite never touches the real library bookmark.
        static func defaults(for options: LaunchOptions, bundleID: String?) -> UserDefaults {
            guard options.isTestRun, let bundleID,
                  let suite = UserDefaults(suiteName: bundleID + testSuiteSuffix)
            else { return .standard }
            return suite
        }

        /// Wipes the test suite. `-SegueResetState` always makes this a test run, so it can never
        /// clear the user's real defaults.
        static func wipeTestState(_ defaults: UserDefaults, bundleID: String?) {
            guard let bundleID else { return }
            defaults.removePersistentDomain(forName: bundleID + testSuiteSuffix)
        }

        /// AppKit autosaves window frames (`NSWindow Frame <name>`) into the app's standard
        /// defaults, never into the test suite, so a test launch would start from whatever frame
        /// the same bundle ID last saved (a real Personal session's 1440x900, a previous run's
        /// moved window). `-SegueResetState` forgets them so every reset launch opens at the
        /// scene's default size. Relaunches without a reset keep them: that is the restore test.
        static func forgetWindowFrames(in defaults: UserDefaults = .standard) {
            for key in defaults.dictionaryRepresentation().keys
                where key.hasPrefix("NSWindow Frame ")
            {
                defaults.removeObject(forKey: key)
            }
        }
    }

    // MARK: - Dependencies for a Debug launch

    @MainActor
    extension LaunchOptions {
        /// The app's dependencies for this launch: the real ones, or the test doubles and
        /// isolated defaults suite a test run asks for.
        func dependencies(
            fileSystem: any FileSystem,
            clock: any Support.Clock,
            ids: any IDGenerator,
            real: (UserDefaults) -> LiveDependencies,
        ) -> AppDependencies {
            let bundleID = Bundle.main.bundleIdentifier
            let defaults = AppStateReset.defaults(for: self, bundleID: bundleID)
            if resetState {
                AppStateReset.wipeTestState(defaults, bundleID: bundleID)
                AppStateReset.forgetWindowFrames()
            }
            if screenshotLibrary {
                Self.wipeScreenshotLibrary()
            }
            if guideFixtures {
                GuideFixtures.write()
            }
            let services = servicesWiring(defaults: defaults, bundleID: bundleID)
            let polish = polishDependencies(defaults: defaults)
            return AppDependencies(
                fileSystem: fileSystem,
                clock: clock,
                ids: ids,
                location: LibraryLocation(defaults: defaults),
                libraryOverride: libraryOverride,
                rememberLibraryOverride: rememberLibrary,
                shapeLibraryURL: isTestRun ? shapeLibraryPath : SegueApp.realShapeLibraryURL,
                live: isTestRun ? liveDependencies(defaults: defaults) : real(defaults),
                hooks: polish.router.filling(services.hooks),
                workspace: workspaceLog.map(RecordingWorkspaceActions.init),
                importPanel: importPanelPaths.map(FixedImportPanel.init),
                autosaveDelay: autosaveDelay.map { .milliseconds(Int(($0 * 1000).rounded())) },
                services: services.services,
                consent: services.consent,
                diagnosticLog: services.log,
                flavor: SegueApp.flavor,
                reportPresenter: services.reportPresenter,
                diagnostics: services.diagnostics,
                mail: mailLog.map(RecordingMailComposer.init),
                polish: polish,
            )
        }

        /// WS2b's stores and switches for this launch. A test run never asks the system for
        /// a review, shows no tips and no What's New unless a flag asks for them.
        private func polishDependencies(defaults: UserDefaults) -> PolishDependencies {
            let requester: any ReviewRequester = if let reviewLog {
                LogReviewRequester(log: reviewLog)
            } else if isTestRun {
                SilentReviewRequester()
            } else {
                SystemReviewRequester()
            }
            let forced = appearance.flatMap(AppearanceMode.init)
            var polish = PolishDependencies(
                defaults: defaults,
                reviewRequester: requester,
                appearance: AppearanceStore(defaults: defaults, forced: forced),
                appVersion: appVersion,
                launch: PolishLaunch(
                    isTestRun: isTestRun,
                    onboarding: onboarding,
                    seedWelcome: seedWelcome,
                    exportPath: exportPath,
                    tips: tips ?? (isTestRun ? .hide : .standard),
                    resetTips: resetState,
                    completedGigs: completedGigs,
                    lastSeenVersion: lastSeenVersion,
                    allowsWhatsNew: changelogPath != nil || lastSeenVersion != nil,
                    extraSeedFolders: screenshotLibrary
                        ? [ScreenshotSongs.writeSeedFolder()].compactMap(\.self) : [],
                ),
            )
            if let changelogPath {
                polish.changelogURL = changelogPath
            }
            return polish
        }

        /// The services for a Debug launch: Recording adapters for E2E, the real vendors for a
        /// manual live check, otherwise Null adapters. Then the consent preset.
        private func servicesWiring(defaults: UserDefaults, bundleID: String?) -> ServicesWiring {
            let mode: ServicesWiring.Mode = if let servicesLog {
                .recording(RecordingLog(url: servicesLog), feedback: feedbackResult ?? .ok)
            } else if servicesLive, let config = VendorConfig.load(from: .main) {
                .vendor(config, .fixed(.debug))
            } else {
                .null
            }
            let suiteName = isTestRun ? bundleID.map { $0 + AppStateReset.testSuiteSuffix } : nil
            let wiring = ServicesWiring(
                mode: mode,
                defaults: defaults,
                suiteName: suiteName,
                logDirectory: servicesLog.map { log in
                    log.deletingLastPathComponent().appending(
                        path: "Logs",
                        directoryHint: .isDirectory,
                    )
                },
            )
            apply(consentPreset, to: wiring.consent)
            return wiring
        }

        private func apply(_ preset: ConsentPreset?, to store: ConsentStore) {
            switch preset {
            case .undecided:
                store.resetToUndecided()
            case .asStored:
                return
            case .analyticsOnly, .crashOnly, .declined, .granted:
                let analytics = preset == .granted || preset == .analyticsOnly
                let crash = preset == .granted || preset == .crashOnly
                store.set(analytics, for: .analytics, source: nil)
                store.set(crash, for: .crashReports, source: nil)
            case nil:
                // A test run that did not ask for the prompt never sees it.
                guard isTestRun else { return }
                for toggle in ConsentStore.Toggle.allCases where !store.isDecided(toggle) {
                    store.set(false, for: toggle, source: nil)
                }
            }
        }

        /// The file system for this launch: deleted items go to `-SegueTrashPath` when given.
        var fileSystem: LiveFileSystem {
            trashPath.map { LiveFileSystem(trash: .directory($0)) } ?? LiveFileSystem()
        }

        /// Live mode for a test run: the recording runner and scaled clock when asked for,
        /// and only the explicit bindings file.
        private func liveDependencies(defaults: UserDefaults) -> LiveDependencies {
            let shortcuts: any ShortcutRunner = shortcutLog.map(RecordingShortcutRunner.init)
                ?? AppleEventShortcutRunner()
            let scrollClock: any Support.Clock = liveTimeScale.map { ScaledClock(scale: $0) }
                ?? MonotonicClock()
            let settings = LiveSettingsStore(defaults: defaults)
            if let startShortcut {
                settings.settings.startShortcut = startShortcut
            }
            if let endShortcut {
                settings.settings.endShortcut = endShortcut
            }
            return LiveDependencies(
                settings: settings,
                shortcuts: shortcuts,
                scrollClock: scrollClock,
                bindingsURL: bindingsPath,
            )
        }
    }
#endif
