#if os(macOS)
    import Foundation
    import Observation

    /// WS2b's first-run, discovery and polish dependencies: the preference stores (one writer
    /// per key, all in the launch's defaults suite), the bundled resources and the Debug
    /// test switches. Built by the app target; in-process tests use `init(defaults:)`.
    @MainActor
    public struct PolishDependencies {
        public var onboarding: OnboardingStore
        public var whatsNew: WhatsNewStore
        public var review: ReviewPromptStore
        public var reviewRequester: any ReviewRequester
        public var appearance: AppearanceStore
        public var preferences: PolishPreferences
        /// The bundled generated `changelog.json` (or `-SegueChangelogPath`).
        public var changelogURL: URL?
        /// The running marketing version (or `-SegueAppVersion`).
        public var appVersion: String
        /// The Welcome library's manifest folder (SegueUI resources).
        public var welcomeFolder: URL?
        public var launch: PolishLaunch
        /// Lets the app target's `AppHooks` reach the model once it exists.
        public let router: PolishRouter

        public init(
            defaults: UserDefaults,
            reviewRequester: (any ReviewRequester)? = nil,
            appearance: AppearanceStore? = nil,
            changelogURL: URL? = Bundle.main.url(forResource: "changelog", withExtension: "json"),
            appVersion: String? = nil,
            welcomeFolder: URL? = Self.bundledWelcomeFolder,
            launch: PolishLaunch = PolishLaunch(),
            router: PolishRouter = PolishRouter(),
        ) {
            onboarding = OnboardingStore(defaults: defaults)
            whatsNew = WhatsNewStore(defaults: defaults)
            review = ReviewPromptStore(defaults: defaults)
            preferences = PolishPreferences(defaults: defaults)
            self.reviewRequester = reviewRequester ?? SystemReviewRequester()
            self.appearance = appearance ?? AppearanceStore(defaults: defaults)
            self.changelogURL = changelogURL
            self.appVersion = appVersion ?? Self.bundleVersion
            self.welcomeFolder = welcomeFolder
            self.launch = launch
            self.router = router
        }

        /// The Welcome library shipped in the SegueUI resource bundle (B-18).
        public static var bundledWelcomeFolder: URL? {
            Bundle.module.url(forResource: "WelcomeLibrary", withExtension: nil)
        }

        /// `CFBundleShortVersionString` of the app.
        static var bundleVersion: String {
            Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
        }
    }

    /// The Debug launch switches WS2b honours (all false or nil in a release build).
    public struct PolishLaunch: Sendable, Equatable {
        /// `-SegueOnboarding`.
        public enum Onboarding: String, Sendable {
            /// Run the full flow again for the override library (from page 2).
            case fresh
            /// Mark it done.
            case done
        }

        /// TipKit in test runs (`-SegueTips`).
        public enum Tips: String, Sendable {
            /// Normal rules (a real launch).
            case standard
            /// `showAllTipsForTesting`.
            case show
            /// `hideAllTipsForTesting` (every test run without `-SegueTips show`).
            case hide
        }

        /// Any Debug test switch was given: onboarding, What's New, tips and the review
        /// prompt stay out of the way unless a flag asks for them.
        public var isTestRun = false
        public var onboarding: Onboarding?
        /// `-SegueSeedWelcome YES`: seed the Welcome songs once the library opens.
        public var seedWelcome = false
        /// `-SegueExportPath`: Export Library Archive writes here without the save panel.
        public var exportPath: URL?
        public var tips: Tips = .standard
        /// `-SegueResetState`: also reset the TipKit datastore.
        public var resetTips = false
        /// `-SegueCompletedGigs <n>`.
        public var completedGigs: Int?
        /// `-SegueLastSeenVersion <v>`.
        public var lastSeenVersion: String?
        /// What's New may show in a test run only when a test sets it up.
        public var allowsWhatsNew = false
        /// Seed manifest folders seeded after the Welcome library, in order (Debug captures:
        /// WS5's screenshot-only songs and setlist).
        public var extraSeedFolders: [URL] = []

        public init(
            isTestRun: Bool = false,
            onboarding: Onboarding? = nil,
            seedWelcome: Bool = false,
            exportPath: URL? = nil,
            tips: Tips = .standard,
            resetTips: Bool = false,
            completedGigs: Int? = nil,
            lastSeenVersion: String? = nil,
            allowsWhatsNew: Bool = false,
            extraSeedFolders: [URL] = [],
        ) {
            self.isTestRun = isTestRun
            self.onboarding = onboarding
            self.seedWelcome = seedWelcome
            self.exportPath = exportPath
            self.tips = tips
            self.resetTips = resetTips
            self.completedGigs = completedGigs
            self.lastSeenVersion = lastSeenVersion
            self.allowsWhatsNew = allowsWhatsNew
            self.extraSeedFolders = extraSeedFolders
        }
    }

    /// Small UI preferences: the last Settings pane and the pending TipKit reset.
    @MainActor
    @Observable
    public final class PolishPreferences {
        static let selectedPaneKey = "settings.selectedPane"
        static let tipsResetKey = "tips.resetPending"

        @ObservationIgnored private let defaults: UserDefaults

        /// The Settings pane shown last (restored when Settings reopens, HIG).
        public var selectedPane: String? {
            didSet {
                if let selectedPane {
                    defaults.set(selectedPane, forKey: Self.selectedPaneKey)
                } else {
                    defaults.removeObject(forKey: Self.selectedPaneKey)
                }
            }
        }

        /// TipKit's datastore is reset at the next launch (it must happen before
        /// `Tips.configure`).
        public private(set) var tipsResetPending: Bool

        public init(defaults: UserDefaults) {
            self.defaults = defaults
            selectedPane = defaults.string(forKey: Self.selectedPaneKey)
            tipsResetPending = defaults.bool(forKey: Self.tipsResetKey)
        }

        func requestTipsReset() {
            tipsResetPending = true
            defaults.set(true, forKey: Self.tipsResetKey)
        }

        func clearTipsReset() {
            tipsResetPending = false
            defaults.removeObject(forKey: Self.tipsResetKey)
        }
    }

    /// The app target's hooks (Help > Welcome to Segue…, Help > What's New in Segue, File >
    /// Export Library Archive…) are built before `AppModel`; they reach it through this.
    @MainActor
    public final class PolishRouter {
        weak var app: AppModel?

        public init() {}

        /// Fills WS2a's slots, keeping everything else in `hooks` (I-5, B-17).
        public func filling(_ hooks: AppHooks) -> AppHooks {
            var hooks = hooks
            hooks.showWelcome = { [weak self] _ in self?.app?.showWelcomeRevisit() }
            hooks.showWhatsNew = { [weak self] workspace in
                guard let app = self?.app else {
                    AppHooks.openChangelog(workspace)
                    return
                }
                app.showWhatsNewFromHelp()
            }
            hooks.exportArchive = { [weak self] _ in
                guard let app = self?.app else { return }
                Task { await app.exportLibraryArchive() }
            }
            return hooks
        }
    }
#endif
