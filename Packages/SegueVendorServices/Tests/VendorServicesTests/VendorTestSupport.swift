import Foundation
import Services
import Support
import Synchronization
import Testing
@testable import VendorServices

/// One ingest client under test: its own stub route (a unique TelemetryDeck namespace), a
/// throwaway defaults suite and a temp directory for `queue.json`.
struct IngestHarness {
    static let appID = "CDF7AF01-FB23-4A30-AFAB-8EAB4BF6EFB5"
    /// Lowercased header names a request may carry.
    static let allowedHeaders: Set = [
        "content-type", "user-agent", "accept-language", "content-length",
    ]

    let namespace = "test-\(UUID().uuidString.lowercased())"
    let suiteName = "segue.vendor.tests.\(UUID().uuidString)"
    let directory: URL
    let endpoint: URL

    init() throws {
        directory = FileManager.default.temporaryDirectory
            .appending(path: "segue-vendor-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        endpoint = try #require(TelemetryDeckIngest.endpoint(namespace: namespace))
    }

    static let context = IngestContext(
        systemMajorMinorVersion: "26.6",
        appVersion: "0.5",
        buildNumber: "42",
        region: "US",
    )

    static let fastTiming = IngestTiming(
        transmitInterval: .milliseconds(20),
        maxBackoff: .milliseconds(80),
    )

    var defaults: UserDefaults {
        UserDefaults(suiteName: suiteName) ?? .standard
    }

    var queueFile: URL {
        TelemetryDeckIngestSink.queueFile(in: directory)
    }

    var queueFileExists: Bool {
        FileManager.default.fileExists(atPath: queueFile.path(percentEncoded: false))
    }

    /// The signal objects stored in `queue.json`, if it exists.
    func queuedSignals() throws -> [[String: Any]]? {
        guard queueFileExists else { return nil }
        let data = try Data(contentsOf: queueFile)
        return try (JSONSerialization.jsonObject(with: data) as? [[String: Any]])?
            .compactMap { $0["signal"] as? [String: Any] }
    }

    func route(
        replies: [StubURLProtocol.Reply] = [],
        fallback: StubURLProtocol.Reply = .status(200),
    ) -> StubURLProtocol.Route {
        StubURLProtocol.route(endpoint.path, replies: replies, fallback: fallback)
    }

    /// A stub route of its own (a fresh namespace) for a sink that shares this harness's
    /// install ID and queue file, such as the next launch of the app.
    func relaunchRoute(
        fallback: StubURLProtocol.Reply = .status(200),
    ) throws -> (endpoint: URL, route: StubURLProtocol.Route) {
        let endpoint = try #require(
            TelemetryDeckIngest.endpoint(namespace: "test-\(UUID().uuidString.lowercased())"),
        )
        return (endpoint, StubURLProtocol.route(endpoint.path, fallback: fallback))
    }

    func sink(
        isTestMode: Bool = false,
        clock: any Clock = SystemClock(),
        endpoint: URL? = nil,
    ) -> TelemetryDeckIngestSink {
        TelemetryDeckIngestSink(
            endpoint: endpoint ?? self.endpoint,
            appID: Self.appID,
            isTestMode: isTestMode,
            context: Self.context,
            suiteName: suiteName,
            queueFile: queueFile,
            timing: Self.fastTiming,
            clock: clock,
            log: nil,
            configureSession: Self.stubbed,
        )
    }

    /// A factory whose analytics adapter posts to this harness's stub route.
    func factory(config: VendorConfig) -> VendorServicesFactory {
        var factory = VendorServicesFactory(
            config: config,
            environment: .debug,
            suiteName: suiteName,
            analyticsDirectory: directory,
            log: nil,
        )
        factory.timing = Self.fastTiming
        factory.configureSession = Self.stubbed
        return factory
    }

    @Sendable
    static func stubbed(_ configuration: URLSessionConfiguration) {
        configuration.protocolClasses = [StubURLProtocol.self]
    }

    func cleanUp() {
        try? FileManager.default.removeItem(at: directory)
        UserDefaults.standard.removePersistentDomain(forName: suiteName)
    }
}

/// Wraps the real factory and records every adapter the hub asks it for. The hub reaches a
/// vendor only through its factory, so an empty record proves that no vendor code ran: a
/// synchronous fact, with no waiting for something not to happen.
final class RecordingFactory: ServicesFactory {
    enum Made: Equatable {
        case analytics
        case crashReporter
    }

    private let base: VendorServicesFactory
    private let record = Mutex<[Made]>([])

    init(_ base: VendorServicesFactory) {
        self.base = base
    }

    var made: [Made] {
        record.withLock { $0 }
    }

    func makeAnalytics() -> any AnalyticsSink {
        record.withLock { $0.append(.analytics) }
        return base.makeAnalytics()
    }

    func makeCrashReporter() -> any CrashReporter {
        record.withLock { $0.append(.crashReporter) }
        return base.makeCrashReporter()
    }
}

struct CannotWatch: Error {
    let path: String
}

/// Returns once `condition` holds, re-checking it each time an entry of `directory` is
/// added, removed or renamed (a kqueue vnode event on the directory, not a timer). For state
/// a vendor SDK writes to disk from its own background queue with no completion callback.
/// The watch is armed before the first check, so a change that lands in between still wakes
/// it.
func whenDirectoryChanges(
    _ directory: URL,
    until condition: @escaping @Sendable () -> Bool,
) async throws {
    let path = directory.path(percentEncoded: false)
    let descriptor = open(path, O_EVTONLY)
    guard descriptor >= 0 else { throw CannotWatch(path: path) }
    let (changes, continuation) = AsyncStream.makeStream(
        of: Void.self,
        bufferingPolicy: .bufferingNewest(1),
    )
    let source = DispatchSource.makeFileSystemObjectSource(
        fileDescriptor: descriptor,
        eventMask: [.write, .link, .rename, .delete],
        queue: .global(),
    )
    source.setEventHandler { continuation.yield() }
    source.setCancelHandler { close(descriptor) }
    source.resume()
    defer {
        source.cancel()
        continuation.finish()
    }
    if condition() {
        return
    }
    for await _ in changes where condition() {
        return
    }
}

extension ConsentState {
    static let date = Date(timeIntervalSince1970: 1_792_224_000)
    static let allDeclined = ConsentState(
        analytics: .declined(date),
        crashReports: .declined(date),
    )
    static let analyticsOnly = ConsentState(
        analytics: .granted(date),
        crashReports: .declined(date),
    )
}

/// Every event case with every value of its enum parameters at least once.
enum VocabularySample {
    static var all: [AnalyticsEvent] {
        var events: [AnalyticsEvent] = []
        events += ConsentSource.allCases.map(AnalyticsEvent.analyticsEnabled)
        events += AppFlavor.allCases.flatMap { flavor in
            LaunchLibraryState.allCases.map {
                .appLaunched(daysSinceFirstLaunch: .zero, flavor: flavor, library: $0)
            }
        }
        events += DaysBucket.allCases.map {
            .appLaunched(daysSinceFirstLaunch: $0, flavor: .appStore, library: .open)
        }
        events += SongBucket.allCases.map {
            .librarySnapshot(LibrarySnapshot(
                songs: $0,
                setlists: .zero,
                gigs: .zero,
                welcomeSongsLeft: .all,
                customShapes: true,
            ))
        }
        events += WelcomeSongsLeft.allCases.map {
            .librarySnapshot(LibrarySnapshot(
                songs: .zero,
                setlists: .zero,
                gigs: .zero,
                welcomeSongsLeft: $0,
                customShapes: false,
            ))
        }
        events += LibraryLocation.allCases.map(AnalyticsEvent.libraryCreated)
        events += SongSource.allCases.map { AnalyticsEvent.songCreated($0) }
        events += SongSource.allCases.map { AnalyticsEvent.songCreated($0, nearDuplicate: true) }
        events += ImportMethod.allCases.flatMap { method in
            ImportOutcome.allCases.map {
                .songImported(method: method, files: .zero, outcome: $0, nonUTF8: true)
            }
        }
        events += SmallBucket.allCases.map { AnalyticsEvent.songDeleted(count: $0) }
        events += FeatureKey.allCases.flatMap { feature in
            FeatureContext.allCases.map { AnalyticsEvent.featureUsed(feature, $0) }
        }
        events += EditorMode.allCases.map(AnalyticsEvent.editorOpened)
        events += SetlistSource.allCases.map(AnalyticsEvent.setlistCreated)
        events += AnalyticsShowKind.allCases.map {
            .showStarted(kind: $0, songs: .zero, resumed: true, shortcutsOn: false)
        }
        events += DurationBucket.allCases.flatMap { duration in
            ShowEndReason.allCases.map {
                .showEnded(ShowSummary(
                    kind: .gig,
                    duration: duration,
                    played: .zero,
                    skipped: .zero,
                    requestsUsed: true,
                    autoScrollUsed: false,
                    reordered: true,
                    endedBy: $0,
                ))
            }
        }
        events += Milestone.allCases.map {
            .milestoneReached($0, daysSinceFirstLaunch: .zero)
        }
        events += HelpItem.allCases.map { AnalyticsEvent.helpOpened($0) }
        events += HelpRoute.allCases.map { AnalyticsEvent.helpOpened(.contextHelp, via: $0) }
        events += HelpOrigin.allCases.map { AnalyticsEvent.helpOpened(.reportProblem, from: $0) }
        for page in HelpPage.allCases {
            events.append(.helpOpened(.contextHelp, via: .book, page: page))
        }
        events += FeedbackTransport.allCases.map {
            .feedbackSent(FeedbackSentSummary(
                transport: $0,
                logs: true,
                metricKit: false,
                song: true,
                email: false,
            ))
        }
        events += ErrorCode.allCases.map(AnalyticsEvent.errorOccurred)
        events += SearchContext.allCases.flatMap { context in
            SearchMatchTier.allCases.map {
                .searchPerformed(context: context, matchTier: $0, results: .zero)
            }
        }
        events += PaletteAction.allCases.map {
            .editorChordPalette(action: $0, chords: .zero)
        }
        events += AISample.all
        return events
    }
}

/// Phase 3 AI rows (R74, R98): every enum value and bucket at least once.
enum AISample {
    static var all: [AnalyticsEvent] {
        var events: [AnalyticsEvent] = []
        let providers = AIProviderUsed.allCases
        let rows = [
            PasteSource.allCases.count, PasteFallback.allCases.count,
            LatencyBucket.allCases.count, PasteOutcome.allCases.count,
            CorrectionBucket.allCases.count, providers.count,
        ].max() ?? 0
        for row in 0 ..< rows {
            events.append(.aiPasteFinished(PasteFinishedSummary(
                source: pick(PasteSource.allCases, row),
                provider: pick(providers, row),
                fallback: pick(PasteFallback.allCases, row),
                latency: pick(LatencyBucket.allCases, row),
                outcome: pick(PasteOutcome.allCases, row),
                correction: pick(CorrectionBucket.allCases, row),
                romanHindi: row.isMultiple(of: 2),
            )))
        }
        let downloads = max(
            ModelDownloadResult.allCases.count,
            DownloadDurationBucket.allCases.count,
        )
        for row in 0 ..< downloads {
            events.append(.aiModelDownload(ModelDownloadSummary(
                result: pick(ModelDownloadResult.allCases, row),
                kind: pick(ModelDownloadKind.allCases, row),
                duration: pick(DownloadDurationBucket.allCases, row),
                ramUnder16: row.isMultiple(of: 2),
            )))
        }
        let buckets = SmallBucket.allCases
        for row in buckets.indices {
            events.append(.aiAssistantUsed(AssistantUsedSummary(
                context: pick(AssistantContext.allCases, row),
                lexiconChips: buckets[row],
                suggestedShown: pick(buckets, row + 1),
                suggestedAccepted: pick(buckets, row + 2),
                provider: pick(providers, row),
                rebuilt: row.isMultiple(of: 2),
            )))
        }
        for action in SmartFilterAction.allCases {
            events += buckets.map { .aiSmartFilterUsed(action: action, conditions: $0) }
        }
        return events
    }

    private static func pick<T>(_ values: [T], _ row: Int) -> T {
        values[row % values.count]
    }
}
