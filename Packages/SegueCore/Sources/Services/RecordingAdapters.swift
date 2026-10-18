import Foundation
import Synchronization

/// Appends one JSON object per line to a file: the Debug E2E seam for services (the
/// `-SegueServicesLog <file>` launch option) and the package tests' observation point, like
/// `RecordingShortcutRunner`. Line shapes (keys sorted):
/// - `{"kind":"signal","name":"Segue.Show.started","params":{...}}`
/// - `{"kind":"analytics.shutDown","discardingQueue":true}`
/// - `{"kind":"crash.start"}`, `{"kind":"crash.shutDown","discardingQueue":true}`
/// - `{"category":"segue","data":{...},"kind":"breadcrumb","message":"..."}`
/// - `{"bytes":1234,"kind":"feedback","sha256":"..."}`
public final class RecordingLog: Sendable {
    public let url: URL
    private let lock = Mutex(())

    public init(url: URL) {
        self.url = url
    }

    func append(_ object: [String: Any]) {
        guard var line = try? JSONSerialization.data(
            withJSONObject: object,
            options: [.sortedKeys, .withoutEscapingSlashes],
        ) else {
            return
        }
        line.append(0x0A)
        lock.withLock { _ in
            let path = url.path(percentEncoded: false)
            if !FileManager.default.fileExists(atPath: path) {
                FileManager.default.createFile(atPath: path, contents: nil)
            }
            guard let handle = try? FileHandle(forWritingTo: url) else { return }
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: line)
        }
    }

    /// Every recorded line, parsed (tests and E2E).
    public func entries() -> [[String: Any]] {
        lock.withLock { _ in
            guard let data = try? Data(contentsOf: url) else { return [] }
            return data.split(separator: 0x0A).compactMap { line in
                try? JSONSerialization.jsonObject(with: Data(line)) as? [String: Any]
            }
        }
    }
}

/// Records every signal instead of sending it.
public struct RecordingAnalyticsSink: AnalyticsSink {
    private let log: RecordingLog

    public init(log: RecordingLog) {
        self.log = log
    }

    public func send(_ signal: AnalyticsSignal) {
        log.append(["kind": "signal", "name": signal.name, "params": signal.params])
    }

    public func shutDown(discardingQueue: Bool) async {
        log.append(["kind": "analytics.shutDown", "discardingQueue": discardingQueue])
    }
}

/// Records the start (construction), breadcrumbs and shut down of crash reporting.
public struct RecordingCrashReporter: CrashReporter {
    private let log: RecordingLog

    /// Constructing it is "starting the SDK", so it logs `crash.start`.
    public init(log: RecordingLog) {
        self.log = log
        log.append(["kind": "crash.start"])
    }

    public func addBreadcrumb(_ crumb: Breadcrumb) {
        log.append([
            "kind": "breadcrumb",
            "category": crumb.category,
            "message": crumb.message,
            "data": crumb.data,
        ])
    }

    public func shutDown(discardingQueue: Bool) async {
        log.append(["kind": "crash.shutDown", "discardingQueue": discardingQueue])
    }

    public var installationID: String? {
        "00000000000000000000000000000000"
    }
}

/// Records a report's hash and size and answers with a chosen outcome.
public struct RecordingFeedbackSender: FeedbackSender {
    /// The `-SegueFeedbackResult` launch option values.
    public enum Outcome: String, Sendable, CaseIterable {
        case ok
        case offline
        case rejected
    }

    private let log: RecordingLog
    private let outcome: Outcome

    public init(log: RecordingLog, outcome: Outcome = .ok) {
        self.log = log
        self.outcome = outcome
    }

    public func send(_ payload: FeedbackPayload) async throws(FeedbackError) {
        switch outcome {
        case .ok:
            log.append([
                "kind": "feedback",
                "sha256": payload.sha256,
                "bytes": payload.envelope.count,
            ])
        case .offline:
            throw .offline
        case .rejected:
            throw .rejected(status: 400)
        }
    }
}

/// Builds Recording adapters and counts how many it built, so tests can prove no adapter
/// is constructed without consent.
public final class RecordingServicesFactory: ServicesFactory {
    public let log: RecordingLog
    private let counts = Mutex((analytics: 0, crashReporters: 0))

    public init(log: RecordingLog) {
        self.log = log
    }

    /// Analytics sinks built so far.
    public var analyticsMade: Int {
        counts.withLock { $0.analytics }
    }

    /// Crash reporters built so far.
    public var crashReportersMade: Int {
        counts.withLock { $0.crashReporters }
    }

    public func makeAnalytics() -> any AnalyticsSink {
        counts.withLock { $0.analytics += 1 }
        return RecordingAnalyticsSink(log: log)
    }

    public func makeCrashReporter() -> any CrashReporter {
        counts.withLock { $0.crashReporters += 1 }
        return RecordingCrashReporter(log: log)
    }
}
