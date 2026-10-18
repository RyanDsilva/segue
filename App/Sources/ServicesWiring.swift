import AppKit
import Foundation
import SegueUI
import Services
import StoreKit
import Support
import Synchronization
import VendorServices

/// Builds the hosted services for this launch (WS3 spec 3.1): which adapters (Null,
/// Recording or the real vendors), the consent store, the diagnostic log and the lifecycle
/// hooks. The only place that picks adapters, so swapping a vendor is one line here.
///
/// Nothing reaches a vendor before consent: `ServicesHub` calls the factory only for a
/// granted consent, and the vendor factory is never even constructed in Debug builds unless
/// `-SegueServicesLive YES` asks for it.
@MainActor
struct ServicesWiring {
    /// Which adapters this launch uses.
    enum Mode {
        /// No vendor config (Debug without `-SegueServicesLive`): Null adapters; Settings >
        /// Privacy says the services are not part of this build.
        case null
        /// Debug E2E (`-SegueServicesLog`): every signal, breadcrumb and report is a JSON
        /// line in `log`; reports answer with `feedback`.
        case recording(RecordingLog, feedback: RecordingFeedbackSender.Outcome)
        /// The real vendors (both Release flavours, and Debug with `-SegueServicesLive`).
        case vendor(VendorConfig, VendorEnvironment.Source)

        /// Whether analytics and crash reporting exist in this build (Settings > Privacy).
        var hasServices: Bool {
            if case .null = self {
                return false
            }
            return true
        }
    }

    let services: ServicesHub
    let consent: ConsentStore
    let log: DiagnosticLog
    /// Report a Problem: the presenter the Help hook calls, and what a report may attach.
    let reportPresenter = ReportProblemPresenter()
    let diagnostics: LocalDiagnostics
    private let metricKit: MetricKitCollector

    /// - Parameters:
    ///   - defaults: the app's defaults (consent, throttle, install ID).
    ///   - suiteName: the name of `defaults`' suite (nil = standard), for the
    ///     `Sendable` parts that reopen it by name.
    ///   - logDirectory: where the diagnostic log rotates (default: Application Support).
    init(mode: Mode, defaults: UserDefaults, suiteName: String?, logDirectory: URL? = nil) {
        let bundleID = Bundle.main.bundleIdentifier ?? "dev.ryandsilva.segue"
        let support = URL.applicationSupportDirectory
            .appending(path: bundleID, directoryHint: .isDirectory)
        let clock = SystemClock()
        let log = DiagnosticLog(
            directory: logDirectory ?? support.appending(path: "Logs", directoryHint: .isDirectory),
            clock: clock,
        )
        let (factory, feedback) = Self.adapters(
            mode: mode,
            defaults: defaults,
            suiteName: suiteName,
            support: support,
            log: log,
        )
        let stored = ConsentStore.stored(in: defaults)
        let hub = ServicesHub(
            factory: factory,
            consent: stored,
            throttle: AnalyticsThrottle(suiteName: suiteName, clock: clock),
            feedback: feedback,
        )
        services = hub
        self.log = log
        consent = ConsentStore(
            defaults: defaults,
            hub: hub,
            log: log,
            clock: clock,
            isAvailable: mode.hasServices,
        )
        let store = DiagnosticStore(
            directory: support.appending(path: "Diagnostics", directoryHint: .isDirectory),
            log: log,
        )
        diagnostics = LocalDiagnostics(log: log, store: store)
        metricKit = MetricKitCollector(store: store)
        metricKit.subscribe()
        // Email drafts of earlier launches (they had to outlive the compose window).
        ReportFiles.clearDrafts()
        Self.logLaunch(log, mode: mode)
        hub.record(LifecycleCrumb.appLaunched)
        Self.observeTermination(hub: hub, log: log)
    }

    /// The analytics/crash factory and the bug-report sender for `mode`.
    private static func adapters(
        mode: Mode,
        defaults: UserDefaults,
        suiteName: String?,
        support: URL,
        log: DiagnosticLog,
    ) -> (any ServicesFactory, any FeedbackSender) {
        switch mode {
        case .null:
            return (NullServicesFactory(), NullFeedbackSender())
        case let .recording(recording, outcome):
            return (
                RecordingServicesFactory(log: recording),
                RecordingFeedbackSender(log: recording, outcome: outcome),
            )
        case let .vendor(config, source):
            let factory = EnvironmentResolvingFactory(
                config: config,
                source: source,
                defaults: defaults,
                suiteName: suiteName,
                analyticsDirectory: support.appending(
                    path: "Analytics",
                    directoryHint: .isDirectory,
                ),
                log: log,
            )
            return (factory, SentryEnvelopeFeedbackSender(config: config, log: log))
        }
    }

    /// The launch line: version, build, flavour and macOS major version as typed values.
    private static func logLaunch(_ log: DiagnosticLog, mode: Mode) {
        let info = Bundle.main.infoDictionary ?? [:]
        let version = (info["CFBundleShortVersionString"] as? String ?? "")
            .split(separator: ".").compactMap { Int($0) }
        let build = Int(info["CFBundleVersion"] as? String ?? "") ?? 0
        let os = ProcessInfo.processInfo.operatingSystemVersion
        let services: StaticString = switch mode {
        case .null: "none"
        case .recording: "recording"
        case .vendor: "vendor"
        }
        log.notice(.app, "launched", [
            "versionMajor": .int(version.first ?? 0),
            "versionMinor": .int(version.dropFirst().first ?? 0),
            "build": .int(build),
            "flavor": .token(flavorToken),
            "macOS": .int(os.majorVersion),
            "services": .token(services),
        ])
    }

    private static var flavorToken: StaticString {
        #if SEGUE_PERSONAL
            "personal"
        #else
            "appStore"
        #endif
    }

    /// `app.willTerminate` breadcrumb and a last flush of the log file.
    private static func observeTermination(hub: ServicesHub, log: DiagnosticLog) {
        NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification,
            object: nil,
            queue: .main,
        ) { _ in
            hub.record(LifecycleCrumb.appWillTerminate)
            log.notice(.app, "terminating")
            let done = DispatchSemaphore(value: 0)
            Task.detached {
                await log.flush()
                done.signal()
            }
            _ = done.wait(timeout: .now() + 1)
        }
    }
}

// MARK: - Hooks

extension ServicesWiring {
    /// The Help menu hooks WS3 fills (WS2a 3.5.6): Report a Problem opens the native sheet;
    /// Request a Feature keeps WS2a's board link (the menu records the analytics).
    var hooks: AppHooks {
        let presenter = reportPresenter
        return AppHooks(reportProblem: { _ in presenter.present() })
    }
}

// MARK: - Release

extension ServicesWiring {
    /// Both Release flavours: the real vendors when the build carries a vendor config.
    static func release(defaults: UserDefaults) -> ServicesWiring {
        let mode: Mode = VendorConfig.load(from: .main).map { config in
            #if SEGUE_PERSONAL
                .vendor(config, .fixed(.personal))
            #else
                .vendor(config, .appStore)
            #endif
        } ?? .null
        return ServicesWiring(mode: mode, defaults: defaults, suiteName: nil)
    }
}

// MARK: - Vendor environment

extension VendorEnvironment {
    /// How a launch learns its environment.
    enum Source {
        /// Known up front (Release-Personal, Debug with `-SegueServicesLive`).
        case fixed(VendorEnvironment)
        /// The App Store flavour: `production` when installed from the App Store, `testflight`
        /// when its `AppTransaction` environment is sandbox, or when it carries no App Store
        /// receipt at all (a locally built Release, so it never counts as production).
        case appStore
    }
}

/// Builds the vendor adapters with the environment known at the moment of the grant. The
/// App Store flavour learns it from `AppTransaction`, which is asynchronous, so the last
/// resolved value is cached in the defaults for the next launch (a TestFlight build first
/// launches with consent undecided, so the first grant always sees the resolved value).
final class EnvironmentResolvingFactory: ServicesFactory {
    static let cacheKey = "services.environment"

    private let config: VendorConfig
    private let suiteName: String?
    private let analyticsDirectory: URL
    private let log: DiagnosticLog
    private let environment: Mutex<VendorEnvironment>

    init(
        config: VendorConfig,
        source: VendorEnvironment.Source,
        defaults: UserDefaults,
        suiteName: String?,
        analyticsDirectory: URL,
        log: DiagnosticLog,
    ) {
        self.config = config
        self.suiteName = suiteName
        self.analyticsDirectory = analyticsDirectory
        self.log = log
        switch source {
        case let .fixed(value):
            environment = Mutex(value)
        case .appStore:
            let cached = defaults.string(forKey: Self.cacheKey).flatMap(VendorEnvironment.init)
            environment = Mutex(cached ?? Self.receiptlessDefault)
            Task { [weak self] in
                let resolved = await Self.resolveAppStoreEnvironment()
                self?.environment.withLock { $0 = resolved }
                UserDefaults(suiteName: suiteName)?.set(resolved.rawValue, forKey: Self.cacheKey)
            }
        }
    }

    /// Before resolution: a build with no receipt is never production.
    private static var receiptlessDefault: VendorEnvironment {
        hasAppStoreReceipt ? .production : .testflight
    }

    /// The vendor factory for the environment known now.
    private var current: VendorServicesFactory {
        VendorServicesFactory(
            config: config,
            environment: environment.withLock { $0 },
            suiteName: suiteName,
            analyticsDirectory: analyticsDirectory,
            log: log,
        )
    }

    func makeAnalytics() -> any AnalyticsSink {
        current.makeAnalytics()
    }

    func makeCrashReporter() -> any CrashReporter {
        current.makeCrashReporter()
    }

    /// Mac App Store and TestFlight installs carry `Contents/_MASReceipt/receipt`; a locally
    /// built Release does not. Checked as a file so no deprecated receipt API is needed.
    private static var hasAppStoreReceipt: Bool {
        let receipt = Bundle.main.bundleURL
            .appending(path: "Contents/_MASReceipt/receipt", directoryHint: .notDirectory)
        return FileManager.default.fileExists(atPath: receipt.path(percentEncoded: false))
    }

    private static func resolveAppStoreEnvironment() async -> VendorEnvironment {
        // Asking StoreKit without a receipt can prompt for an Apple Account: never do that.
        guard hasAppStoreReceipt else { return .testflight }
        do {
            let transaction = try await AppTransaction.shared
            let environment = switch transaction {
            case let .unverified(value, _), let .verified(value): value.environment
            }
            return environment == .production ? .production : .testflight
        } catch {
            return .production
        }
    }
}
