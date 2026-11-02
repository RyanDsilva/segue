import Foundation
import Plugins
@testable import SeguePersonalModules
import Synchronization
import Testing

/// Spec 9 and 15.1: per-host gaps, Retry-After plus jitter, the lyrics host's five 503
/// retries and their cancellation, the 429 hold and the one-hour site back-off.
struct RequestPacerTests {
    static func ok(_ url: String) -> HTTPResponse {
        Pages.response(url)
    }

    @Test
    func `requests to one host keep their gap`() async throws {
        let clock = TestWebClock()
        let pacer = RequestPacer(clock: clock, random: { 0 })
        for _ in 0 ..< 3 {
            _ = try await pacer.perform(host: "example.com") { () async throws(ImportFailure) in 1 }
        }
        #expect(clock.sleeps == [.seconds(2), .seconds(2)])
        for _ in 0 ..< 2 {
            _ = try await pacer
                .perform(host: RequestPacer.lyricsHost) { () async throws(ImportFailure) in 1 }
        }
        #expect(clock.sleeps.suffix(1) == [.milliseconds(300)])
    }

    @Test
    func `different hosts do not wait for each other`() async throws {
        let clock = TestWebClock()
        let pacer = RequestPacer(clock: clock, random: { 0 })
        _ = try await pacer.perform(host: "a.com") { () async throws(ImportFailure) in 1 }
        _ = try await pacer.perform(host: "b.com") { () async throws(ImportFailure) in 1 }
        #expect(clock.sleeps.isEmpty)
    }

    @Test(arguments: [(0.0, 10.0), (1.0, 13.0), (0.5, 11.5)])
    func `a hold honours Retry-After plus at most 30 percent jitter`(
        random: Double,
        seconds: Double,
    ) async throws {
        let clock = TestWebClock()
        let pacer = RequestPacer(clock: clock, random: { random })
        await pacer.hold("example.com", for: .seconds(10))
        _ = try await pacer.perform(host: "example.com") { () async throws(ImportFailure) in 1 }
        #expect(abs(clock.elapsed - seconds) < 0.01)
    }

    @Test
    func `a lyrics 503 is retried five times, then returned`() async throws {
        let url = try #require(URL(string: "https://lrclib.net/api/search?q=x"))
        let busy = HTTPResponse(url: url, status: 503, headers: ["Retry-After": "1"])
        let transport = FixtureTransport([url: [busy]])
        let clock = TestWebClock()
        let pacer = RequestPacer(clock: clock, random: { 0 })
        let retries = RetryLog()
        let response = try await pacer.sendRetryingOverload(
            HTTPRequest(url: url), via: transport, onRetry: { retries.add($0) },
        )
        #expect(response.status == 503)
        #expect(transport.requests.count == 6)
        #expect(retries.values == [1, 2, 3, 4, 5])
        #expect(clock.elapsed < 15.01)
    }

    @Test
    func `a retried 503 that then answers returns the answer`() async throws {
        let url = try #require(URL(string: "https://lrclib.net/api/search?q=x"))
        let busy = HTTPResponse(url: url, status: 503, headers: ["Retry-After": "1"])
        let transport = FixtureTransport([url: [busy, busy, Self.ok(url.absoluteString)]])
        let pacer = RequestPacer(clock: TestWebClock(), random: { 0 })
        let response = try await pacer.sendRetryingOverload(HTTPRequest(url: url), via: transport)
        #expect(response.status == 200)
        #expect(transport.requests.count == 3)
    }

    @Test
    func `cancelling stops the retries`() async throws {
        let url = try #require(URL(string: "https://lrclib.net/api/search?q=x"))
        let busy = HTTPResponse(url: url, status: 503, headers: ["Retry-After": "1"])
        let transport = FixtureTransport([url: [busy]])
        let pacer = RequestPacer(clock: TestWebClock(), random: { 0 })
        let task = Task { () async -> ImportFailure? in
            withUnsafeCurrentTask { $0?.cancel() }
            do {
                _ = try await pacer.sendRetryingOverload(HTTPRequest(url: url), via: transport)
                return nil
            } catch {
                return error as? ImportFailure
            }
        }
        #expect(await task.value == .cancelled)
        #expect(transport.requests.count <= 1)
    }

    @Test
    func `the site back-off holds every request for an hour`() async throws {
        let clock = TestWebClock()
        let pacer = RequestPacer(clock: clock, random: { 0 })
        await pacer.startBackOff("e-chords.com")
        await #expect(throws: ImportFailure.backingOff(retryAfter: .seconds(3600))) {
            try await pacer.perform(host: "e-chords.com") { () async throws(ImportFailure) in 1 }
        }
        _ = try await pacer.perform(host: "other.com") { () async throws(ImportFailure) in 1 }
        clock.advance(.seconds(3599))
        #expect(await pacer.backOffEnd(for: "e-chords.com") != nil)
        clock.advance(.seconds(2))
        #expect(await pacer.backOffEnd(for: "e-chords.com") == nil)
        _ = try await pacer.perform(host: "e-chords.com") { () async throws(ImportFailure) in 1 }
    }
}

final class RetryLog: Sendable {
    private let list = Mutex<[Int]>([])
    func add(_ value: Int) {
        list.withLock { $0.append(value) }
    }

    var values: [Int] {
        list.withLock { $0 }
    }
}
