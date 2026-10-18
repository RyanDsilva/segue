import Foundation
import Services
import Support

/// Usage analytics through our own minimal client for TelemetryDeck's Ingest API v2
/// (spec 3.9, R34). No TelemetryDeck SDK: every byte sent is built by `IngestBody` from the
/// closed vocabulary plus five context keys.
///
/// Constructed only by `ServicesHub` once analytics consent is granted. Construction creates
/// the per-install ID (if needed), a new session ID, and queues one
/// `TelemetryDeck.Session.started` signal; the first request goes out `transmitInterval`
/// later. `send(_:)` is synchronous and never blocks: it hands the signal to the queue actor
/// through an `AsyncStream`.
public final class TelemetryDeckIngestSink: AnalyticsSink {
    private let queue: IngestQueue
    private let continuation: AsyncStream<IngestSignal>.Continuation
    private let identity: IngestIdentity
    private let context: IngestContext
    private let suiteName: String?

    /// Built by `VendorServicesFactory` (tests inject the timing, clock and a `URLProtocol`
    /// stub).
    /// - Parameters:
    ///   - suiteName: the UserDefaults suite holding `analytics.installID` (nil = standard).
    ///   - queueFile: `Application Support/<bundle id>/Analytics/queue.json`.
    init(
        endpoint: URL,
        appID: String,
        isTestMode: Bool,
        context: IngestContext,
        suiteName: String?,
        queueFile: URL,
        timing: IngestTiming,
        clock: any Clock,
        log: DiagnosticLog?,
        configureSession: (URLSessionConfiguration) -> Void,
    ) {
        self.suiteName = suiteName
        self.context = context
        let installID = Self.installID(suiteName: suiteName)
        identity = IngestIdentity(
            appID: appID,
            clientUser: TelemetryDeckIngest.clientUser(installID: installID),
            sessionID: UUID().uuidString,
            isTestMode: isTestMode,
        )

        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 15
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.urlCache = nil
        configuration.urlCredentialStorage = nil
        configuration.httpAdditionalHeaders = [:]
        configureSession(configuration)

        let queue = IngestQueue(
            endpoint: endpoint,
            queueFile: queueFile,
            timing: timing,
            clock: clock,
            log: log,
            session: URLSession(configuration: configuration),
            first: IngestBody.sessionStarted(context: context, identity: identity),
        )
        self.queue = queue
        let (stream, continuation) = AsyncStream.makeStream(of: IngestSignal.self)
        self.continuation = continuation
        Task {
            await queue.start()
            for await signal in stream {
                await queue.enqueue(signal)
            }
        }
    }

    /// `queue.json` inside the analytics directory.
    public static func queueFile(in directory: URL) -> URL {
        directory.appending(path: "queue.json", directoryHint: .notDirectory)
    }

    public func send(_ signal: AnalyticsSignal) {
        continuation.yield(
            IngestBody.make(
                type: signal.name,
                params: signal.params,
                context: context,
                identity: identity,
            ),
        )
    }

    /// Revoke: cancels the in-flight request, clears the queue in memory and on disk and
    /// deletes `analytics.installID`, so a later grant starts a fresh, unlinkable identity.
    /// No final flush.
    public func shutDown(discardingQueue: Bool) async {
        continuation.finish()
        await queue.shutDown(discardingQueue: discardingQueue)
        if discardingQueue {
            Self.defaults(suiteName).removeObject(forKey: TelemetryDeckIngest.installIDKey)
        }
    }

    // MARK: - Identity

    private static func defaults(_ suiteName: String?) -> UserDefaults {
        suiteName.flatMap(UserDefaults.init(suiteName:)) ?? .standard
    }

    /// The stored per-install ID, created now if this is a fresh grant.
    private static func installID(suiteName: String?) -> String {
        let defaults = defaults(suiteName)
        if let existing = defaults.string(forKey: TelemetryDeckIngest.installIDKey),
           !existing.isEmpty
        {
            return existing
        }
        let created = UUID().uuidString
        defaults.set(created, forKey: TelemetryDeckIngest.installIDKey)
        return created
    }

    /// Test observation: the signals not yet accepted by the server.
    var pendingSignals: [IngestSignal] {
        get async {
            await queue.pendingSignals
        }
    }

    /// Test observation: the client hash this sink sends.
    var clientUser: String {
        identity.clientUser
    }
}
