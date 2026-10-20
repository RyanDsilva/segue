import Foundation
import Services
import Support
import Testing
@testable import VendorServices

/// Spec 14.2-9 and 14.2-10: the ingest client against a `URLProtocol` stub (real
/// `URLSession`, real files on temp dirs). No request ever leaves the process.
@Suite(.timeLimit(.minutes(1)))
struct TelemetryDeckIngestTests {
    @Test
    func `every request carries only the allowlisted keys`() async throws {
        let harness = try IngestHarness()
        defer { harness.cleanUp() }
        let route = harness.route()
        let sink = harness.sink(isTestMode: true)
        let signals = VocabularySample.all.map { $0.render() }
        for signal in signals {
            sink.send(signal)
        }

        await sink.drained()
        let requests = route.captured
        #expect(requests.count >= 2)
        #expect(StubURLProtocol.unrouted.allSatisfy { !$0.path.contains(harness.namespace) })

        let installID = try #require(harness.defaults
            .string(forKey: TelemetryDeckIngest.installIDKey))
        for request in requests {
            #expect(request.method == "POST")
            #expect(request.url == harness.endpoint)
            #expect(request.headers["Content-Type"] == "application/json; charset=utf-8")
            // Only the content type and our two replacements of system defaults.
            let headers = Set(request.headers.keys.map { $0.lowercased() })
            #expect(headers.isSubset(of: IngestHarness.allowedHeaders), "\(headers)")
            let objects = request.signals
            #expect(!objects.isEmpty)
            #expect(objects.count <= 100)
            for object in objects {
                #expect(Set(object.keys) == IngestSignal.keys)
                #expect(object["appID"] as? String == IngestHarness.appID)
                #expect(object["isTestMode"] as? Bool == true)
                let clientUser = try #require(object["clientUser"] as? String)
                #expect(clientUser.wholeMatch(of: /[0-9a-f]{64}/) != nil)
                #expect(clientUser != installID)
                #expect(!clientUser.contains(installID.lowercased()))
                let payload = try #require(object["payload"] as? [String: String])
                for (key, value) in payload {
                    #expect(key.hasPrefix("segue.") || IngestContext.keys.contains(key), "\(key)")
                    #expect(value.wholeMatch(of: /[A-Za-z0-9+<>._-]{1,24}/) != nil, "\(value)")
                }
                // The context keys, exactly.
                #expect(Set(payload.keys.filter { !$0.hasPrefix("segue.") }) == IngestContext.keys)
            }
        }

        let all = requests.flatMap(\.signals)
        let first = try #require(all.first)
        #expect(first["type"] as? String == "TelemetryDeck.Session.started")
        #expect(Set((first["payload"] as? [String: String] ?? [:]).keys) == IngestContext.keys)
        #expect(Set(all.compactMap { $0["sessionID"] as? String }).count == 1)
        #expect(Set(all.compactMap { $0["type"] as? String }.dropFirst()) ==
            Set(signals.map(\.name)))
        await sink.shutDown(discardingQueue: true)
    }

    @Test
    func `the namespace endpoint and the bare v2 endpoint`() {
        #expect(
            TelemetryDeckIngest.endpoint(namespace: "dev.ryandsilva")?.absoluteString
                == "https://nom.telemetrydeck.com/v2/namespace/dev.ryandsilva/",
        )
        #expect(
            TelemetryDeckIngest.endpoint(namespace: nil)?.absoluteString
                == "https://nom.telemetrydeck.com/v2/",
        )
    }

    @Test
    func `a server error is retried with backoff and sent once`() async throws {
        let harness = try IngestHarness()
        defer { harness.cleanUp() }
        let route = harness.route(replies: [.status(503)])
        let sink = harness.sink()
        sink.send(AnalyticsEvent.helpOpened(.help).render())

        // Drained means the retry was accepted; nothing is pending to send a third time.
        await sink.drained()
        #expect(route.captured.count == 2)
        #expect(route.captured[0].body == route.captured[1].body)
        #expect(await sink.pendingSignals.isEmpty)
        #expect(!harness.queueFileExists)
        await sink.shutDown(discardingQueue: true)
    }

    @Test
    func `a rejected batch is dropped, never retried`() async throws {
        let harness = try IngestHarness()
        defer { harness.cleanUp() }
        let route = harness.route(replies: [.status(400)])
        let sink = harness.sink()
        sink.send(AnalyticsEvent.helpOpened(.help).render())

        // Drained means the rejected batch was dropped; nothing is left to retry.
        await sink.drained()
        #expect(route.captured.count == 1)
        #expect(!harness.queueFileExists)
        await sink.shutDown(discardingQueue: true)
    }

    @Test
    func `offline signals survive termination and go out in batches of 100`() async throws {
        let harness = try IngestHarness()
        defer { harness.cleanUp() }
        _ = harness.route(fallback: .offline)
        let offline = harness.sink()
        let event = AnalyticsEvent.featureUsed(.transpose, .editor).render()
        for _ in 0 ..< 149 {
            offline.send(event)
        }
        // Shutting down keeps (and persists) every signal sent before it: 149 + the session
        // signal.
        await offline.shutDown(discardingQueue: false)
        let stored = try #require(try harness.queuedSignals())
        #expect(stored.count == 150)
        #expect(harness.defaults.string(forKey: TelemetryDeckIngest.installIDKey) != nil)

        // Next launch, back online: the stored 150 plus the new session signal. The relaunch
        // posts to a route of its own, because the offline sink's last attempt can still
        // reach the stub after shut-down (it was already on the wire when cancelled).
        let (endpoint, route) = try harness.relaunchRoute()
        let online = harness.sink(endpoint: endpoint)
        await online.drained()
        let sent = route.captured
        #expect(sent.map(\.signals.count) == [100, 51])
        let types = sent.flatMap(\.signals).compactMap { $0["type"] as? String }
        #expect(types.filter { $0 == event.name }.count == 149)
        #expect(types.filter { $0 == "TelemetryDeck.Session.started" }.count == 2)
        #expect(!harness.queueFileExists)
        await online.shutDown(discardingQueue: true)
    }

    @Test
    func `the queue keeps the newest 1000 and drops signals older than 30 days`() async throws {
        let harness = try IngestHarness()
        defer { harness.cleanUp() }
        _ = harness.route(fallback: .offline)
        let clock = ManualClock()
        let first = harness.sink(clock: clock)
        let event = AnalyticsEvent.featureUsed(.capo, .editor).render()
        for _ in 0 ..< 1100 {
            first.send(event)
        }
        await first.shutDown(discardingQueue: false)
        let stored = try harness.queuedSignals()
        #expect(stored?.count == 1000)

        clock.advance(by: 31 * 24 * 60 * 60)
        let later = harness.sink(clock: clock)
        // Everything stored is too old; only the new session signal remains.
        #expect(await later.pendingSignals.map(\.type) == ["TelemetryDeck.Session.started"])
        await later.shutDown(discardingQueue: true)
    }

    @Test
    func `revoking cancels the request in flight and deletes the queue and identity`()
        async throws
    {
        let harness = try IngestHarness()
        defer { harness.cleanUp() }
        let route = harness.route(fallback: .hang)
        let sink = harness.sink()
        let firstUser = sink.clientUser
        sink.send(AnalyticsEvent.helpOpened(.help).render())
        await route.waitForCaptured(1)
        #expect(harness.queueFileExists)

        await sink.shutDown(discardingQueue: true)
        await route.waitForCancelled(1)
        #expect(!harness.queueFileExists)
        #expect(harness.defaults.string(forKey: TelemetryDeckIngest.installIDKey) == nil)

        // Sending after shutdown reaches nothing.
        // The sink is closed, so the signal never reaches the queue, the disk or the wire.
        sink.send(AnalyticsEvent.helpOpened(.help).render())
        #expect(await sink.pendingSignals.isEmpty)
        #expect(route.captured.count == 1)
        #expect(!harness.queueFileExists)

        // A re-grant is a fresh, unlinkable identity.
        let regranted = harness.sink()
        #expect(regranted.clientUser != firstUser)
        await regranted.shutDown(discardingQueue: true)
    }

    @Test(arguments: [
        (200, IngestQueue.Disposition.sent), (204, .sent), (400, .dropped(status: 400)),
        (401, .dropped(status: 401)), (403, .dropped(status: 403)),
        (404, .dropped(status: 404)), (413, .dropped(status: 413)),
        (422, .dropped(status: 422)), (501, .dropped(status: 501)),
        (505, .dropped(status: 505)), (429, .retry), (500, .retry), (503, .retry), (0, .retry),
    ])
    func `response disposition mirrors the SDK`(status: Int, expected: IngestQueue.Disposition) {
        #expect(IngestQueue.disposition(status: status) == expected)
    }

    @Test
    func `backoff doubles up to the cap`() {
        let timing = IngestTiming.production
        #expect(timing.backoff(failures: 1) == .seconds(20))
        #expect(timing.backoff(failures: 4) == .seconds(160))
        #expect(timing.backoff(failures: 5) == .seconds(300))
        #expect(timing.backoff(failures: 60) == .seconds(300))
    }

    @Test
    func `client user is the salted SHA-256 of the install ID`() {
        let hash = TelemetryDeckIngest.clientUser(installID: "A")
        #expect(hash.count == 64)
        #expect(hash == TelemetryDeckIngest.clientUser(installID: "A"))
        #expect(hash != TelemetryDeckIngest.clientUser(installID: "B"))
        #expect(TelemetryDeckIngest.salt.count == 64)
    }

    @Test
    func `context values outside the allowlist are left out`() {
        let context = IngestContext(
            systemMajorMinorVersion: "26.6",
            appVersion: "0.5",
            buildNumber: "12",
            region: "not a region!",
        )
        #expect(context.payload[IngestContext.regionKey] == nil)
        #expect(context.payload[IngestContext.operatingSystemKey] == "macOS")
        #expect(context.payload.count == 4)
    }
}
