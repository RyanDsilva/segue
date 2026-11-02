import Foundation
import Plugins

/// Time for the pacer: the wall-clock instant (for back-off deadlines shown to the user) and
/// a cancellable sleep. Injected, so pacer tests run instantly and deterministically.
protocol WebClock: Sendable {
    func now() -> Date
    /// Throws `CancellationError` when the task is cancelled.
    func sleep(for duration: Duration) async throws
}

struct SystemWebClock: WebClock {
    func now() -> Date {
        Date()
    }

    func sleep(for duration: Duration) async throws {
        try await Task.sleep(for: duration)
    }
}

/// Spec 9: one request in flight per host; at least 300 ms between requests to the lyrics
/// host and 2 s to any other host; `Retry-After` honoured plus up to 30% jitter; the lyrics
/// host's 503s retried up to 5 times; and a one-hour back-off for a chord site after a hard
/// block, during which nothing at all is sent to it. In memory for the launch.
actor RequestPacer {
    static let lyricsHost = "lrclib.net"
    static let lyricsGap: Duration = .milliseconds(300)
    static let siteGap: Duration = .seconds(2)
    static let backOff: Duration = .seconds(3600)
    static let maxOverloadRetries = 5
    static let maxJitter = 0.3

    private let clock: any WebClock
    /// A fraction in 0...1, scaled by `maxJitter`. Injected for deterministic tests.
    private let random: @Sendable () -> Double
    private var busy: Set<String> = []
    private var waiters: [String: [CheckedContinuation<Void, Never>]] = [:]
    private var nextAllowed: [String: Date] = [:]
    private var backOffUntil: [String: Date] = [:]

    init(
        clock: any WebClock = SystemWebClock(),
        random: @escaping @Sendable () -> Double = { Double.random(in: 0 ... 1) },
    ) {
        self.clock = clock
        self.random = random
    }

    /// The minimum gap between two requests to `host`.
    static func gap(for host: String) -> Duration {
        host == lyricsHost ? lyricsGap : siteGap
    }

    /// Runs `operation` as the only request to `host` once its gap has passed.
    func perform<T: Sendable>(
        host: String,
        _ operation: @Sendable () async throws(ImportFailure) -> T,
    ) async throws(ImportFailure) -> T {
        try await acquire(host)
        defer { release(host) }
        if Task.isCancelled {
            throw .cancelled
        }
        return try await operation()
    }

    /// Sends through `transport`, retrying a 503 up to `maxOverloadRetries` times, each after
    /// its `Retry-After` (default 1 s) plus jitter. `onRetry` hears each retry's number, for
    /// the "busy, retrying" line and the `lyricsRetries` count. Any other response returns.
    func sendRetryingOverload(
        _ request: HTTPRequest,
        via transport: any HTTPTransport,
        onRetry: @escaping @Sendable (Int) -> Void = { _ in },
    ) async throws(ImportFailure) -> HTTPResponse {
        let host = request.url.host(percentEncoded: false)?.lowercased() ?? ""
        var retries = 0
        while true {
            let response = try await perform(host: host) { () async throws(ImportFailure) in
                try await transport.send(request)
            }
            guard response.status == 503, retries < Self.maxOverloadRetries else { return response }
            retries += 1
            onRetry(retries)
            hold(host, for: response.retryAfter ?? .seconds(1))
        }
    }

    /// Holds `host` for `duration` plus jitter (a 429 or 503 `Retry-After`).
    func hold(_ host: String, for duration: Duration) {
        let seconds = duration.seconds * (1 + random() * Self.maxJitter)
        let until = clock.now().addingTimeInterval(seconds)
        nextAllowed[host] = max(nextAllowed[host] ?? .distantPast, until)
    }

    /// Starts the one-hour back-off for `host` (a hard block on its last load path).
    func startBackOff(_ host: String) {
        backOffUntil[host] = clock.now().addingTimeInterval(Self.backOff.seconds)
    }

    /// When the back-off for `host` ends, or nil when it is not backing off.
    func backOffEnd(for host: String) -> Date? {
        guard let until = backOffUntil[host] else { return nil }
        if until <= clock.now() {
            backOffUntil[host] = nil
            return nil
        }
        return until
    }

    private func acquire(_ host: String) async throws(ImportFailure) {
        if let end = backOffEnd(for: host) {
            throw .backingOff(retryAfter: .seconds(end.timeIntervalSince(clock.now())))
        }
        while busy.contains(host) {
            await withCheckedContinuation { waiters[host, default: []].append($0) }
        }
        busy.insert(host)
        let wait = (nextAllowed[host] ?? .distantPast).timeIntervalSince(clock.now())
        if wait > 0 {
            do {
                try await clock.sleep(for: .milliseconds(Int((wait * 1000).rounded(.up))))
            } catch {
                release(host, spaced: false)
                throw .cancelled
            }
        }
    }

    private func release(_ host: String, spaced: Bool = true) {
        if spaced {
            let earliest = clock.now().addingTimeInterval(Self.gap(for: host).seconds)
            nextAllowed[host] = max(nextAllowed[host] ?? .distantPast, earliest)
        }
        busy.remove(host)
        if var queue = waiters[host], !queue.isEmpty {
            let next = queue.removeFirst()
            waiters[host] = queue
            next.resume()
        }
    }
}

extension Duration {
    /// The duration in seconds, as a `TimeInterval`.
    var seconds: TimeInterval {
        Double(components.seconds) + Double(components.attoseconds) / 1e18
    }
}
