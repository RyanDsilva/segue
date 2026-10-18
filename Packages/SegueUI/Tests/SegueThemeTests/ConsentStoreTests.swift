import Foundation
@testable import SegueUI
import Services
import Support
import Testing

/// The consent store end to end with real parts (WS3 spec 4): a real defaults suite, the
/// real `ServicesHub` and the Recording adapters writing their JSON-lines file, the same seam
/// the E2E suite reads.
@MainActor
struct ConsentStoreTests {
    /// A defaults suite, a recording log and a hub built the way the app builds it.
    @MainActor
    final class Fixture {
        let suiteName = "dev.ryandsilva.segue.consent-tests.\(UUID().uuidString)"
        let defaults: UserDefaults
        let scratch: URL
        let recording: RecordingLog
        let factory: RecordingServicesFactory
        let clock = ManualClock()

        init() throws {
            defaults = try #require(UserDefaults(suiteName: suiteName))
            scratch = FileManager.default.temporaryDirectory
                .appending(
                    path: "ConsentStoreTests-\(UUID().uuidString)",
                    directoryHint: .isDirectory,
                )
            try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
            recording = RecordingLog(url: scratch.appending(path: "services.jsonl"))
            factory = RecordingServicesFactory(log: recording)
        }

        deinit {
            UserDefaults().removePersistentDomain(forName: suiteName)
            try? FileManager.default.removeItem(at: scratch)
        }

        /// A store and hub as `ServicesWiring` makes them at launch.
        func launch() -> (ConsentStore, ServicesHub) {
            let hub = ServicesHub(
                factory: factory,
                consent: ConsentStore.stored(in: defaults),
                throttle: AnalyticsThrottle(suiteName: suiteName, clock: clock),
            )
            let store = ConsentStore(
                defaults: defaults,
                hub: hub,
                clock: clock,
                isAvailable: true,
            )
            return (store, hub)
        }

        func kinds() -> [String] {
            recording.entries().compactMap { $0["kind"] as? String }
        }

        func signals() -> [String] {
            recording.entries().filter { $0["kind"] as? String == "signal" }
                .compactMap { $0["name"] as? String }
        }
    }

    @Test
    func `answers stay undecided until continue and only the granted side is built`() async throws {
        let fixture = try Fixture()
        var (store, hub) = fixture.launch()
        #expect(store.needsPrompt)

        // Answered but not continued (the app quit): nothing is stored or built.
        store.draft.analytics = true
        store.draft.crashReports = false
        (store, hub) = fixture.launch()
        #expect(store.needsPrompt)
        #expect(store.draft == ConsentStore.Draft())

        store.draft.analytics = true
        #expect(!store.draft.isComplete)
        store.commitDraft(source: .prompt)
        #expect(store.needsPrompt, "Continue does nothing until both are answered")
        store.draft.crashReports = false
        store.commitDraft(source: .prompt)
        await store.settle()

        #expect(!store.needsPrompt)
        #expect(hub.consent.analytics.isGranted)
        #expect(!hub.consent.crashReports.isGranted)
        #expect(fixture.factory.analyticsMade == 1)
        #expect(fixture.factory.crashReportersMade == 0)
        #expect(fixture.signals() == ["Segue.Privacy.analyticsEnabled"])
        let params = fixture.recording.entries().first?["params"] as? [String: String]
        #expect(params == ["segue.source": "prompt"])

        // The next launch builds the analytics sink straight away and does not ask again.
        let (relaunched, _) = fixture.launch()
        #expect(!relaunched.needsPrompt)
        #expect(fixture.factory.analyticsMade == 2)
    }

    @Test
    func `turning a toggle off stops sending at once and explains deletion`() async throws {
        let fixture = try Fixture()
        let (store, hub) = fixture.launch()
        store.set(true, for: .analytics, source: .settings)
        store.set(true, for: .crashReports, source: .settings)
        await store.settle()
        hub.record(.featureUsed(.transpose, .editor))
        #expect(fixture.signals().contains("Segue.Feature.used"))

        store.set(false, for: .analytics, source: .settings)
        // Applied synchronously: nothing recorded after the toggle reaches the sink.
        hub.record(.featureUsed(.capo, .editor))
        await store.settle()
        let featureSignals = fixture.recording.entries().filter {
            ($0["params"] as? [String: String])?["segue.feature"] == "capo"
        }
        #expect(!featureSignals.contains { $0["kind"] as? String == "signal" })
        #expect(fixture.kinds().contains("analytics.shutDown"))
        #expect(store.revokedThisSession == [.analytics])

        store.set(false, for: .crashReports, source: .settings)
        await store.settle()
        #expect(store.revokedThisSession == [.analytics, .crashReports])
        #expect(store.revokedDiagnosticsID == "00000000000000000000000000000000")
        #expect(fixture.kinds().contains("crash.shutDown"))
        #expect(!store.crashStartsAtNextLaunch)

        // A11: the crash reporter cannot start again in this process.
        store.set(true, for: .crashReports, source: .settings)
        await store.settle()
        #expect(store.crashStartsAtNextLaunch)
        #expect(store.revokedThisSession == [.analytics])

        // Analytics come back at once, and the grant is recorded with its source.
        store.set(true, for: .analytics, source: .settings)
        await store.settle()
        #expect(store.revokedThisSession.isEmpty)
        #expect(fixture.signals().last == "Segue.Privacy.analyticsEnabled")
    }

    @Test
    func `an outdated stored version and reset all settings ask again`() async throws {
        let fixture = try Fixture()
        let old = ConsentState(
            analytics: .granted(.now),
            crashReports: .declined(.now),
            version: ConsentState.currentVersion - 1,
        )
        try fixture.defaults.set(SegueJSON.encode(old), forKey: ConsentStore.defaultsKey)
        let (outdated, outdatedHub) = fixture.launch()
        #expect(outdated.needsPrompt)
        #expect(!outdated.isGranted(.analytics))
        #expect(!outdatedHub.consent.analytics.isGranted)
        #expect(fixture.factory.analyticsMade == 0)

        outdated.set(true, for: .analytics, source: .settings)
        outdated.set(true, for: .crashReports, source: .settings)
        await outdated.settle()
        #expect(!outdated.needsPrompt)

        outdated.resetToUndecided()
        await outdated.settle()
        #expect(outdated.needsPrompt)
        #expect(!outdatedHub.consent.analytics.isGranted)
        #expect(fixture.kinds().contains("analytics.shutDown"))
        #expect(fixture.kinds().contains("crash.shutDown"))
        let (relaunched, _) = fixture.launch()
        #expect(relaunched.needsPrompt)
    }
}
