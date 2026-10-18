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
            // Every flag takes one value: collect the last value given for each.
            var values: [String: String] = [:]
            var iterator = arguments.dropFirst().makeIterator()
            while let argument = iterator.next() {
                guard Self.flags.contains(argument), let value = iterator.next() else { continue }
                values[argument] = value
            }
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
        }

        private static let flags: Set = [
            libraryPathFlag, resetStateFlag, rememberLibraryFlag, testDefaultsFlag,
            shapeLibraryPathFlag, shortcutLogFlag, liveTimeScaleFlag, bindingsPathFlag,
            startShortcutFlag, endShortcutFlag, workspaceLogFlag, trashPathFlag,
            importPanelPathsFlag, autosaveDelayFlag, servicesLogFlag, feedbackResultFlag,
            servicesLiveFlag, consentFlag, appearanceFlag, mailLogFlag,
        ]

        /// A Shortcut name with surrounding blanks removed; nil when blank.
        private static func name(_ value: String?) -> String? {
            guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !trimmed.isEmpty
            else { return nil }
            return trimmed
        }

        private static func path(_ value: String?, directoryHint: URL.DirectoryHint) -> URL? {
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
        }

        private static func isTruthy(_ value: String) -> Bool {
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
            }
            let services = servicesWiring(defaults: defaults, bundleID: bundleID)
            if let appearance {
                NSApplication.shared.appearance = NSAppearance(
                    named: appearance == "dark" ? .darkAqua : .aqua,
                )
            }
            return AppDependencies(
                fileSystem: fileSystem,
                clock: clock,
                ids: ids,
                location: LibraryLocation(defaults: defaults),
                libraryOverride: libraryPath,
                rememberLibraryOverride: rememberLibrary,
                shapeLibraryURL: isTestRun ? shapeLibraryPath : SegueApp.realShapeLibraryURL,
                live: isTestRun ? liveDependencies(defaults: defaults) : real(defaults),
                hooks: services.hooks,
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
            )
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
