import Foundation
import Services
import Support
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

    func sink(
        isTestMode: Bool = false,
        clock: any Clock = SystemClock(),
    ) -> TelemetryDeckIngestSink {
        TelemetryDeckIngestSink(
            endpoint: endpoint,
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

struct TimedOut: Error {}

/// Polls `condition` until it holds, failing after `timeout`.
nonisolated(nonsending) func eventually(
    timeout: Duration = .seconds(10),
    _ condition: () async -> Bool,
) async throws {
    let deadline = ContinuousClock.now + timeout
    while await !condition() {
        guard ContinuousClock.now < deadline else {
            Issue.record("condition not met within \(timeout)")
            throw TimedOut()
        }
        try await Task.sleep(for: .milliseconds(10))
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
        events += SongSource.allCases.map(AnalyticsEvent.songCreated)
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
        events += ShowKind.allCases.map {
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
        events += HelpItem.allCases.map(AnalyticsEvent.helpOpened)
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
        return events
    }
}
