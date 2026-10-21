import Foundation
import SentrySwift
import Services
import Support
import Testing
@testable import VendorServices

/// The real vendor adapters behind the consent gate: nothing is constructed, written or sent
/// before consent, and revoking stops everything. Serialized because the Sentry SDK is
/// process-wide state. Every wait is on an event (a request arriving, a cancellation, a
/// directory change); the time limit is only a backstop against a hang.
@Suite(.serialized, .timeLimit(.minutes(1)))
struct VendorConsentTests {
    /// A config whose DSN points at this Mac, so the started SDK can never reach Sentry.
    /// Its TelemetryDeck namespace routes the analytics adapter to the harness's stub.
    static func config(namespace: String = "") throws -> VendorConfig {
        try #require(VendorConfig(
            sentryDSN: "https://0123456789abcdef@localhost/1",
            telemetryDeckAppID: IngestHarness.appID,
            telemetryDeckNamespace: namespace,
            bundleIdentifier: "dev.ryandsilva.segue.tests",
            appVersion: "0.5",
            buildNumber: "42",
        ))
    }

    static func hub(
        _ harness: IngestHarness,
        _ consent: ConsentState,
        factory: RecordingFactory? = nil,
    ) throws -> ServicesHub {
        let throttle = AnalyticsThrottle(suiteName: harness.suiteName, clock: SystemClock())
        return try ServicesHub(
            factory: factory ?? recording(harness),
            consent: consent,
            throttle: throttle,
        )
    }

    static func recording(_ harness: IngestHarness) throws -> RecordingFactory {
        try RecordingFactory(harness.factory(config: config(namespace: harness.namespace)))
    }

    @Test(arguments: [ConsentState.undecided, ConsentState.allDeclined])
    func `no vendor is touched before consent`(consent: ConsentState) throws {
        let harness = try IngestHarness()
        defer { harness.cleanUp() }
        let route = harness.route()
        let factory = try Self.recording(harness)
        let hub = try Self.hub(harness, consent, factory: factory)

        let sample = VocabularySample.all
        for index in 0 ..< 200 {
            hub.record(sample[index % sample.count])
        }
        for crumb in LifecycleCrumb.allCases {
            hub.record(crumb)
        }

        // No adapter was ever built, so nothing exists that could send later.
        #expect(factory.made.isEmpty)
        #expect(route.captured.isEmpty)
        #expect(!SentrySDK.isEnabled)
        #expect(hub.installationID == nil)
        #expect(!harness.queueFileExists)
        #expect(harness.defaults.string(forKey: TelemetryDeckIngest.installIDKey) == nil)
    }

    @Test
    func `granting analytics sends, revoking stops at once and leaves nothing behind`()
        async throws
    {
        let harness = try IngestHarness()
        defer { harness.cleanUp() }
        let route = harness.route()
        let hub = try Self.hub(harness, .undecided)

        await hub.apply(.analyticsOnly)
        hub.record(.helpOpened(.reportProblem))
        await route.waitForSignals(2)
        let types = route.captured.flatMap(\.signals).compactMap { $0["type"] as? String }
        #expect(types == ["TelemetryDeck.Session.started", "Segue.Help.opened"])
        #expect(!SentrySDK.isEnabled)

        route.setFallback(.hang)
        hub.record(.helpOpened(.requestFeature))
        // On the wire, so already on disk: the queue persists before it sends.
        await route.waitForSignals(3)
        #expect(harness.queueFileExists)
        await hub.apply(.allDeclined)
        // Revoking cancelled the hanging request instead of waiting it out.
        await route.waitForCancelled(1)
        hub.record(.helpOpened(.privacyPolicy))

        // The hub swapped the Null sink in before shutting the old one down, and `apply`
        // returned only once the old send loop had wound down: nothing is left that could
        // still send, so there is nothing to wait for.
        #expect(route.captured.flatMap(\.signals).count == 3)
        #expect(!route.captured.flatMap(\.signals).contains { signal in
            (signal["payload"] as? [String: String])?["segue.item"] == "privacyPolicy"
        })
        #expect(!harness.queueFileExists)
        #expect(harness.defaults.string(forKey: TelemetryDeckIngest.installIDKey) == nil)
    }

    @Test @MainActor
    func `the Sentry reporter starts once, and revoking deletes its queue but keeps the ID`()
        async throws
    {
        let cache = FileManager.default.temporaryDirectory
            .appending(path: "segue-sentry-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: cache, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: cache) }
        let cachePath = cache.path(percentEncoded: false)

        let reporter = try SentryCrashReporter(
            config: Self.config(),
            environment: .debug,
            cacheDirectory: cachePath,
        )
        #expect(SentrySDK.isEnabled)
        #expect(!SentryCrashReporter.startsAtNextLaunch)
        // The SDK writes `INSTALLATION` from its own background queue, with no callback.
        try await whenDirectoryChanges(cache) { reporter.installationID != nil }
        let diagnosticsID = reporter.installationID
        reporter.addBreadcrumb(Services.Breadcrumb(.helpOpened(.help)))

        // Something waiting to be sent.
        let pending = cache.appending(path: "io.sentry/pending/envelopes")
        try FileManager.default.createDirectory(at: pending, withIntermediateDirectories: true)
        try Data("{}".utf8).write(to: pending.appending(path: "envelope"))

        await reporter.shutDown(discardingQueue: true)
        #expect(!SentrySDK.isEnabled)
        #expect(!FileManager.default.fileExists(atPath: cache.appending(path: "io.sentry").path))
        #expect(reporter.installationID == diagnosticsID)
        #expect(SentryCrashReporter.startsAtNextLaunch)

        // A re-grant in the same process does not restart the SDK (A11).
        let regranted = try SentryCrashReporter(
            config: Self.config(),
            environment: .debug,
            cacheDirectory: cachePath,
        )
        regranted.addBreadcrumb(Services.Breadcrumb(.helpOpened(.help)))
        #expect(!SentrySDK.isEnabled)
        await regranted.shutDown(discardingQueue: true)
    }
}
