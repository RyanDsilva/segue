import Foundation
import Services
import Support

/// Batching, retry and the offline queue of the TelemetryDeck client (spec 3.9). All mutable
/// state of `TelemetryDeckIngestSink` lives here.
///
/// The on-disk queue is rewritten whenever the pending set changes (signals are rare: a few
/// per day), so it already holds everything unsent when the app terminates or crashes, and
/// termination needs no last-second work. It exists only while signals are pending, and only
/// while analytics consent is granted.
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

    private var pending: [Entry]
    private var failures = 0
    private var loop: Task<Void, Never>?
    private var isShutDown = false

    init(
        endpoint: URL,
        queueFile: URL,
        timing: IngestTiming,
        clock: any Clock,
        log: DiagnosticLog?,
        session: URLSession,
        first: IngestSignal,
    ) {
        self.endpoint = endpoint
        self.queueFile = queueFile
        self.timing = timing
        self.clock = clock
        self.log = log
        self.session = session
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

    func enqueue(_ signal: IngestSignal) {
        guard !isShutDown else { return }
        pending = Self.capped(
            pending + [Entry(signal: signal, queuedAt: clock.now())],
            timing.maxQueued,
        )
        persist()
        scheduleIfNeeded()
    }

    /// Stops for good. Discarding: the in-flight request is cancelled and the on-disk queue
    /// deleted, with no final flush. Otherwise the pending signals stay on disk for the next
    /// sink.
    func shutDown(discardingQueue: Bool) {
        guard !isShutDown else { return }
        if !discardingQueue {
            persist()
        }
        isShutDown = true
        loop?.cancel()
        loop = nil
        session.invalidateAndCancel()
        pending = []
        if discardingQueue {
            try? FileManager.default.removeItem(at: queueFile)
        }
    }

    /// Test observation: the signals not yet accepted by the server.
    var pendingSignals: [IngestSignal] {
        pending.map(\.signal)
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
        if !isShutDown {
            loop = nil
        }
    }

    private func sendBatch() async -> Disposition {
        let batch = Array(pending.prefix(timing.batchSize))
        guard let body = try? IngestBody.encode(batch.map(\.signal)) else {
            // Cannot happen for string-only values; never retry what cannot be encoded.
            pending.removeFirst(batch.count)
            persist()
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
        do {
            let (_, response) = try await session.data(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
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
        case .sent:
            pending.removeFirst(min(batch.count, pending.count))
            persist()
        case .retry:
            break
        }
        return disposition
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
