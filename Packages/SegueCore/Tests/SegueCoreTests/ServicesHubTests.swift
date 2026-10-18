import Foundation
import Services
import Support
import Testing

/// The consent gate end to end with the Recording adapters on real files (spec 14.2-1..3,
/// plus the throttle budget of 3.4).
@Suite(.serialized)
struct ServicesHubTests {
    private static func drive(_ hub: ServicesHub, count: Int) {
        let sample = VocabularySample.all
        for index in 0 ..< count {
            hub.record(sample[(index * 37) % sample.count])
        }
        for crumb in LifecycleCrumb.allCases {
            hub.record(crumb)
        }
    }

    @Test(arguments: [ConsentState.undecided, ConsentState.allDeclined])
    func `nothing is recorded or constructed before consent`(consent: ConsentState) async throws {
        let sandbox = try ServicesSandbox()
        defer { sandbox.cleanUp() }
        let hub = sandbox.hub(consent)

        Self.drive(hub, count: 200)
        await hub.apply(.allDeclined)
        Self.drive(hub, count: 200)

        #expect(sandbox.log.entries().isEmpty)
        #expect(sandbox.factory.analyticsMade == 0)
        #expect(sandbox.factory.crashReportersMade == 0)
        #expect(hub.installationID == nil)
        #expect(UserDefaults(suiteName: sandbox.suiteName)?
            .data(forKey: AnalyticsThrottle.defaultsKey) == nil)
    }

    @Test
    func `analytics and crash reports are independent`() async throws {
        let analytics = try ServicesSandbox()
        defer { analytics.cleanUp() }
        Self.drive(analytics.hub(.analyticsOnly), count: 200)
        #expect(!analytics.entries("signal").isEmpty)
        #expect(analytics.entries("breadcrumb").isEmpty)
        #expect(analytics.entries("crash.start").isEmpty)
        #expect(analytics.factory.analyticsMade == 1)
        #expect(analytics.factory.crashReportersMade == 0)

        let crash = try ServicesSandbox()
        defer { crash.cleanUp() }
        let hub = crash.hub(.undecided)
        await hub.apply(.crashOnly)
        Self.drive(hub, count: 200)
        #expect(crash.entries("signal").isEmpty)
        #expect(crash.entries("crash.start").count == 1)
        // Breadcrumbs are not throttled: every event and lifecycle moment is kept locally.
        #expect(crash.entries("breadcrumb").count == 200 + LifecycleCrumb.allCases.count)
        #expect(crash.entries("breadcrumb").allSatisfy { $0["category"] as? String == "segue" })
        #expect(crash.factory.analyticsMade == 0)
        #expect(crash.factory.crashReportersMade == 1)
        #expect(hub.installationID != nil)
    }

    @Test
    func `revocation is immediate even with a concurrent sender`() async throws {
        let sandbox = try ServicesSandbox()
        defer { sandbox.cleanUp() }
        let hub = sandbox.hub(.undecided)
        await hub.apply(.allGranted)
        hub.record(.featureUsed(.transpose, .editor))
        #expect(sandbox.entries("signal").count == 1)
        #expect(UserDefaults(suiteName: sandbox.suiteName)?
            .data(forKey: AnalyticsThrottle.defaultsKey) != nil)

        let event = AnalyticsEvent.showStarted(
            kind: .gig,
            songs: .tenTo19,
            resumed: false,
            shortcutsOn: true,
        )
        let sender = Task.detached {
            while !Task.isCancelled {
                hub.record(event)
                await Task.yield()
            }
        }
        try await Task.sleep(for: .milliseconds(20))
        await hub.apply(.allDeclined)
        let signalsAtRevoke = sandbox.entries("signal").count
        let crumbsAtRevoke = sandbox.entries("breadcrumb").count
        try await Task.sleep(for: .milliseconds(50))
        hub.record(event)
        sender.cancel()
        await sender.value

        #expect(signalsAtRevoke > 1)
        #expect(sandbox.entries("signal").count == signalsAtRevoke)
        #expect(sandbox.entries("breadcrumb").count == crumbsAtRevoke)
        #expect(sandbox.entries("analytics.shutDown").count == 1)
        #expect(sandbox.entries("crash.shutDown").count == 1)
        #expect(sandbox.entries("analytics.shutDown").first?["discardingQueue"] as? Bool == true)
        // Nothing reached an adapter after it was shut down.
        let kinds = sandbox.log.entries().compactMap { $0["kind"] as? String }
        let shutDown = try #require(kinds.firstIndex(of: "analytics.shutDown"))
        #expect(!kinds[shutDown...].contains("signal"))
        #expect(!kinds[shutDown...].contains("breadcrumb"))
        // The throttle state is gone, so a re-grant starts fresh.
        #expect(UserDefaults(suiteName: sandbox.suiteName)?
            .data(forKey: AnalyticsThrottle.defaultsKey) == nil)
        await hub.apply(.analyticsOnly)
        hub.record(.featureUsed(.transpose, .editor))
        #expect(sandbox.entries("signal").last?["name"] as? String == "Segue.Feature.used")
        #expect(sandbox.factory.analyticsMade == 2)
        #expect(sandbox.factory.crashReportersMade == 1)
    }

    @Test
    func `an outdated consent version counts as undecided`() throws {
        let sandbox = try ServicesSandbox()
        defer { sandbox.cleanUp() }
        let stale = ConsentState(
            analytics: .granted(ConsentState.date),
            crashReports: .granted(ConsentState.date),
            version: 0,
        )
        #expect(stale.needsPrompt)
        #expect(!ConsentState.allDeclined.needsPrompt)
        let hub = sandbox.hub(stale)
        Self.drive(hub, count: 50)
        #expect(sandbox.log.entries().isEmpty)
        #expect(hub.consent == .undecided)
    }

    @Test
    func `throttle keeps the daily and once budgets across days and relaunches`() async throws {
        let sandbox = try ServicesSandbox()
        defer { sandbox.cleanUp() }
        let declined = sandbox.hub(.allDeclined)
        // Events while declined never consume the budget.
        declined.record(.featureUsed(.capo, .editor))
        await declined.apply(.analyticsOnly)
        declined.record(.featureUsed(.capo, .editor))
        #expect(sandbox.entries("signal").count == 1)

        let hub = sandbox.hub(.analyticsOnly)
        for _ in 0 ..< 3 {
            hub.record(.featureUsed(.transpose, .editor))
            hub.record(.featureUsed(.transpose, .stage))
            hub.record(.milestoneReached(.firstSong, daysSinceFirstLaunch: .zero))
            hub.record(.showStarted(
                kind: .rehearsal,
                songs: .one,
                resumed: false,
                shortcutsOn: false,
            ))
        }
        func names() -> [String] {
            sandbox.entries("signal").compactMap { entry in
                let params = entry["params"] as? [String: String] ?? [:]
                let name = entry["name"] as? String ?? ""
                return [name, params["segue.feature"] ?? "", params["segue.context"] ?? ""]
                    .joined(separator: "|")
            }
        }
        #expect(names().count(where: { $0 == "Segue.Feature.used|transpose|editor" }) == 1)
        #expect(names().count(where: { $0 == "Segue.Feature.used|transpose|stage" }) == 1)
        #expect(names().count(where: { $0 == "Segue.Milestone.reached||" }) == 1)
        #expect(names().count(where: { $0 == "Segue.Show.started||" }) == 3)

        // A relaunch the same day remembers; the next local day admits daily events again.
        let relaunched = sandbox.hub(.analyticsOnly)
        relaunched.record(.featureUsed(.transpose, .editor))
        #expect(names().count(where: { $0 == "Segue.Feature.used|transpose|editor" }) == 1)
        sandbox.clock.advance(by: 24 * 3600)
        relaunched.record(.featureUsed(.transpose, .editor))
        relaunched.record(.milestoneReached(.firstSong, daysSinceFirstLaunch: .one))
        #expect(names().count(where: { $0 == "Segue.Feature.used|transpose|editor" }) == 2)
        #expect(names().count(where: { $0 == "Segue.Milestone.reached||" }) == 1)
    }
}
