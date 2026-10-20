import Foundation
import Services
import Synchronization
import Support

/// Batching, retry and the offline queue of the TelemetryDeck client (spec 3.9). All mutable
/// state of `TelemetryDeckIngestSink` lives here.
///
/// The on-disk queue is rewritten whenever the pending set changes (signals are rare: a few
/// per day), so it already holds everything unsent when the app terminates or crashes, and
/// termination needs no last-second work. It exists only while signals are pending, and only
/// while analytics consent is granted.
/// Signals handed to the sink that the queue has not taken yet. The queue takes the whole
/// buffer inside the actor (`IngestQueue.absorb()`), so order is preserved and a burst is one
/// persist.
final class IngestOutbox: Sendable {
    private struct State {
        var signals: [IngestSignal] = []
        var isClosed = false
    }

    private let state = Mutex(State())

    /// False once closed (the sink was shut down).
    func append(_ signal: IngestSignal) -> Bool {
        state.withLock { state in
            guard !state.isClosed else { return false }
            state.signals.append(signal)
            return true
        }
    }

    func close() {
        state.withLock { $0.isClosed = true }
    }

    func take() -> [IngestSignal] {
        state.withLock { state in
            defer { state.signals = [] }
            return state.signals
        }
    }
}

actor IngestQueue {
    /// One pending signal and when it was queued (for the 30-day cut-off on load).
    struct Entry: Codable, Equatable {
        let signal: IngestSignal
        let queuedAt: Date
    }

    enum Disposition: Equatable {
        case sent
        case dropped(status: Int)
        case retry
    }

    private let endpoint: URL
    private let queueFile: URL
    private let timing: IngestTiming
    private let clock: any Clock
    private let log: DiagnosticLog?
    private let session: URLSession
    private let outbox: IngestOutbox

    private var pending: [Entry]
    private var failures = 0
    private var loop: Task<Void, Never>?
    private var isShutDown = false
    private var drainWaiters: [CheckedContinuation<Void, Never>] = []

    init(
        endpoint: URL,
        queueFile: URL,
        timing: IngestTiming,
        clock: any Clock,
        log: DiagnosticLog?,
        session: URLSession,
        outbox: IngestOutbox,
        first: IngestSignal,
    ) {
        self.endpoint = endpoint
        self.queueFile = queueFile
        self.timing = timing
        self.clock = clock
        self.log = log
        self.session = session
        self.outbox = outbox
        let now = clock.now()
        let loaded = Self.load(queueFile, now: now, maxAge: timing.maxAge)
        pending = Self.capped(loaded + [Entry(signal: first, queuedAt: now)], timing.maxQueued)
    }

    // MARK: - Entry points

    /// Persists the first signal (and anything loaded from disk) and starts sending.
    func start() {
        persist()
        scheduleIfNeeded()
    }

    /// Queues everything the sink has buffered with one rewrite of the on-disk queue (it is
    /// rewritten as a whole, so persisting per signal would make a burst of n signals O(n^2)
    /// file I/O).
    func absorb() {
        let signals = outbox.take()
        guard !isShutDown, !signals.isEmpty else { return }
        let now = clock.now()
        pending = Self.capped(
            pending + signals.map { Entry(signal: $0, queuedAt: now) },
            timing.maxQueued,
        )
        persist()
        scheduleIfNeeded()
    }

    /// Stops for good. Discarding: the in-flight request is cancelled and the on-disk queue
    /// deleted, with no final flush. Otherwise the pending signals stay on disk for the next
    /// sink.
    ///
    /// Returns only once the send loop has wound down: cancelling a `URLSession` task is
    /// asynchronous, so without this wait a request this queue had already handed to the
    /// loading system could still start after shut-down (and, on a relaunch, go out next to
    /// the next sink's resend of the same signals).
    func shutDown(discardingQueue: Bool) async {
        guard !isShutDown else { return }
        if !discardingQueue {
            persist()
        }
        isShutDown = true
        let running = loop
        loop = nil
        running?.cancel()
        session.invalidateAndCancel()
        pending = []
        resumeDrainWaiters()
        if discardingQueue {
            try? FileManager.default.removeItem(at: queueFile)
        }
        await running?.value
    }

    /// Test observation: the signals not yet accepted by the server.
    var pendingSignals: [IngestSignal] {
        pending.map(\.signal)
    }

    /// Test observation: returns once no signal is pending (immediately if none is). Lets a
    /// test wait for the queue to empty as an event instead of polling the wall clock.
    func drained() async {
        guard !pending.isEmpty else { return }
        await withCheckedContinuation { drainWaiters.append($0) }
    }

    private func resumeDrainWaiters() {
        let waiters = drainWaiters
        drainWaiters = []
        for waiter in waiters {
            waiter.resume()
        }
    }

    // MARK: - Sending

    private func scheduleIfNeeded() {
        guard loop == nil, !isShutDown, !pending.isEmpty else { return }
        loop = Task { await self.run() }
    }

    /// Sends one batch every `transmitInterval` while signals remain, backing off
    /// exponentially on retryable failures.
    private func run() async {
        var delay = timing.transmitInterval
        while true {
            do {
                try await Task.sleep(for: delay)
            } catch {
                return
            }
            guard !isShutDown, !pending.isEmpty else { break }
            switch await sendBatch() {
            case .dropped, .sent:
                failures = 0
                delay = timing.transmitInterval
            case .retry:
                failures += 1
                delay = timing.backoff(failures: failures)
            }
            if isShutDown || pending.isEmpty {
                break
            }
        }
        loop = nil
    }

    private func sendBatch() async -> Disposition {
        let batch = Array(pending.prefix(timing.batchSize))
        guard let body = try? IngestBody.encode(batch.map(\.signal)) else {
            // Cannot happen for string-only values; never retry what cannot be encoded.
            pending.removeFirst(batch.count)
            persist()
            resumeDrainWaitersIfEmpty()
            return .dropped(status: 0)
        }
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.httpBody = body
        request.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
        // Replace the system's defaults, which would otherwise carry the Mac's preferred
        // languages and the app and Darwin versions in their own format.
        request.setValue("Segue", forHTTPHeaderField: "User-Agent")
        request.setValue("*", forHTTPHeaderField: "Accept-Language")

        let disposition: Disposition
        var status = 0
        do {
            let (_, response) = try await session.data(for: request)
            status = (response as? HTTPURLResponse)?.statusCode ?? 0
            disposition = Self.disposition(status: status)
        } catch {
            disposition = .retry
        }
        guard !isShutDown else { return disposition }
        switch disposition {
        case let .dropped(status):
            log?.notice(.analytics, "dropped", ["status": .int(status)])
            pending.removeFirst(min(batch.count, pending.count))
            persist()
            resumeDrainWaitersIfEmpty()
        case .sent:
            log?.info(.analytics, "sent", ["status": .int(status), "signals": .int(batch.count)])
            pending.removeFirst(min(batch.count, pending.count))
            persist()
            resumeDrainWaitersIfEmpty()
        case .retry:
            break
        }
        return disposition
    }

    private func resumeDrainWaitersIfEmpty() {
        if pending.isEmpty {
            resumeDrainWaiters()
        }
    }

    /// The SDK's response disposition (`SignalManager`): 2xx done; a request the server
    /// rejected is dropped, never retried; anything else is retried.
    static func disposition(status: Int) -> Disposition {
        switch status {
        case 200 ..< 300: .sent
        case 400, 401, 403, 404, 413, 422, 501, 505: .dropped(status: status)
        default: .retry
        }
    }

    // MARK: - Disk queue

    private func persist() {
        guard !isShutDown else { return }
        let manager = FileManager.default
        if pending.isEmpty {
            try? manager.removeItem(at: queueFile)
            return
        }
        do {
            try manager.createDirectory(
                at: queueFile.deletingLastPathComponent(),
                withIntermediateDirectories: true,
            )
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.sortedKeys]
            try encoder.encode(pending).write(to: queueFile, options: .atomic)
        } catch {
            log?.error(.analytics, "queue.writeFailed", ["error": .error(LoggedError(error))])
        }
    }

    private static func load(_ file: URL, now: Date, maxAge: TimeInterval) -> [Entry] {
        guard let data = try? Data(contentsOf: file) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let entries = try? decoder.decode([Entry].self, from: data) else { return [] }
        return entries.filter { now.timeIntervalSince($0.queuedAt) <= maxAge }
    }

    /// Keeps the newest `limit` entries (oldest dropped first).
    private static func capped(_ entries: [Entry], _ limit: Int) -> [Entry] {
        entries.count > limit ? Array(entries.suffix(limit)) : entries
    }
}

/// Timing and limits of the ingest client. Production values mirror the SDK
/// (`transmitInterval` 10 s, `maxBackoffInterval` 300 s, 100 signals per request); tests
/// shrink the intervals.
struct IngestTiming: Sendable {
    var transmitInterval: Duration = .seconds(10)
    var maxBackoff: Duration = .seconds(300)
    var batchSize = 100
    /// Several weeks of normal use.
    var maxQueued = 1000
    /// Signals older than this are dropped on load.
    var maxAge: TimeInterval = 30 * 24 * 60 * 60

    static let production = Self()

    /// `min(transmitInterval x 2^failures, maxBackoff)`.
    func backoff(failures: Int) -> Duration {
        let factor = 1 << min(failures, 16)
        return min(transmitInterval * factor, maxBackoff)
    }
}
