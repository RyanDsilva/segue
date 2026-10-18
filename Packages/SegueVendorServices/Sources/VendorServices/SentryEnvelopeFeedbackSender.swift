import Foundation
import Services

/// Bug reports as Sentry User Feedback, posted as our own envelope (WS3 spec 3.5, B-24): the
/// bytes sent are exactly the `FeedbackPayload` the user previewed, with no SDK scope added,
/// and they go out whether or not crash reports are on (sending a previewed report is its
/// own explicit act). Constructing the sender opens no connection; it posts only on `send`.
///
/// `POST https://<host>/api/<project id>/envelope/` with
/// `Content-Type: application/x-sentry-envelope` and
/// `X-Sentry-Auth: Sentry sentry_version=7, sentry_key=<public key>,
/// sentry_client=segue-feedback/<version>`, through an ephemeral session with no cookies,
/// cache or credentials; the system User-Agent and Accept-Language are replaced (R54).
public final class SentryEnvelopeFeedbackSender: FeedbackSender {
    /// How long Send waits before offering the fallback (spec 8.4).
    public static let timeout: TimeInterval = 20

    private let endpoint: URL
    private let auth: String
    private let session: URLSession
    private let log: DiagnosticLog?

    /// - Parameter configureSession: test seam (a `URLProtocol` stub).
    public init(
        dsn: SentryDSN,
        clientVersion: String,
        log: DiagnosticLog?,
        configureSession: (URLSessionConfiguration) -> Void = { _ in },
    ) {
        endpoint = dsn.envelopeURL
        auth = "Sentry sentry_version=7, sentry_key=\(dsn.publicKey), "
            + "sentry_client=\(FeedbackReportBuilder.clientName)/\(clientVersion)"
        self.log = log
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = Self.timeout
        configuration.timeoutIntervalForResource = Self.timeout
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.urlCache = nil
        configuration.urlCredentialStorage = nil
        configuration.httpAdditionalHeaders = [:]
        configuration.waitsForConnectivity = false
        configureSession(configuration)
        session = URLSession(configuration: configuration)
    }

    public convenience init(config: VendorConfig, log: DiagnosticLog?) {
        self.init(dsn: config.sentryDSN, clientVersion: config.appVersion, log: log)
    }

    public func send(_ payload: FeedbackPayload) async throws(FeedbackError) {
        guard payload.envelope.count <= FeedbackReportBuilder.envelopeByteLimit else {
            throw .tooLarge
        }
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.httpBody = payload.envelope
        request.setValue("application/x-sentry-envelope", forHTTPHeaderField: "Content-Type")
        request.setValue(auth, forHTTPHeaderField: "X-Sentry-Auth")
        request.setValue("Segue", forHTTPHeaderField: "User-Agent")
        request.setValue("*", forHTTPHeaderField: "Accept-Language")

        let status: Int
        do {
            let (_, response) = try await session.data(for: request)
            status = (response as? HTTPURLResponse)?.statusCode ?? 0
        } catch {
            log?.notice(.feedback, "send.failed", ["error": .error(LoggedError(error))])
            throw .offline
        }
        log?.notice(.feedback, "send", ["status": .int(status)])
        switch status {
        case 200 ..< 300:
            return
        case 413:
            throw .tooLarge
        case 500...:
            // The service is having trouble: offer the fallback like being offline.
            throw .offline
        default:
            throw .rejected(status: status)
        }
    }
}
