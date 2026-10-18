import Foundation
import Services
import Testing
@testable import VendorServices

/// `SentryEnvelopeFeedbackSender` against a real `URLSession` with the `URLProtocol` stub:
/// it posts exactly the previewed bytes to the DSN's envelope endpoint with only the
/// documented headers, and maps every failure to an outcome that offers the fallback.
struct FeedbackSenderTests {
    static let report = FeedbackReport(
        message: "The stage froze after the third song.",
        email: "player@example.com",
        systemInfo: FeedbackSystemInfo(
            appVersion: "0.5",
            buildNumber: "12",
            flavor: "appStore",
            macOSVersion: "26.6",
            modelIdentifier: "Mac15,3",
            architecture: "arm64",
            preferredLanguage: "en-US",
            songs: .tenTo49,
            setlists: .one,
            gigs: .zero,
            analyticsConsent: "declined",
            crashReportsConsent: "declined",
            logBytes: 1200,
        ),
        attachments: [FeedbackAttachment(kind: .log, file: DiagnosticFile(
            name: "segue-0.log",
            contentType: "text/plain",
            data: Data("2026-10-17T21:03:11.402Z notice app launched\n".utf8),
        ))],
    )

    /// A DSN whose project id is unique per test, so routes never collide.
    static func sender(project: String) throws -> SentryEnvelopeFeedbackSender {
        let dsn = try #require(SentryDSN("https://abc123@o1.ingest.us.sentry.io/\(project)"))
        return SentryEnvelopeFeedbackSender(
            dsn: dsn,
            clientVersion: "0.5",
            log: nil,
            configureSession: IngestHarness.stubbed,
        )
    }

    static func payload() throws -> FeedbackPayload {
        try FeedbackReportBuilder(clientVersion: "0.5").payload(
            for: report,
            eventID: UUID(),
            timestamp: Date(timeIntervalSince1970: 1_792_224_000),
        )
    }

    @Test
    func `a report posts exactly the previewed envelope with the documented headers`()
        async throws
    {
        let project = String(Int.random(in: 100_000 ... 999_999))
        let route = StubURLProtocol.route("/api/\(project)/", fallback: .status(200))
        let payload = try Self.payload()
        try await Self.sender(project: project).send(payload)

        let request = try #require(route.captured.first)
        #expect(route.captured.count == 1)
        #expect(request.method == "POST")
        #expect(request.url.absoluteString
            == "https://o1.ingest.us.sentry.io/api/\(project)/envelope/")
        #expect(request.body == payload.envelope)
        #expect(request.headers["Content-Type"] == "application/x-sentry-envelope")
        #expect(request.headers["X-Sentry-Auth"]
            == "Sentry sentry_version=7, sentry_key=abc123, sentry_client=segue-feedback/0.5")
        #expect(request.headers["User-Agent"] == "Segue")
        #expect(request.headers["Accept-Language"] == "*")
        let allowed: Set = [
            "Content-Type", "X-Sentry-Auth", "User-Agent", "Accept-Language", "Content-Length",
        ]
        #expect(Set(request.headers.keys).isSubset(of: allowed), "\(request.headers.keys)")
    }

    @Test(arguments: [
        (StubURLProtocol.Reply.offline, FeedbackError.offline),
        (.status(503), .offline),
        (.status(400), .rejected(status: 400)),
        (.status(413), .tooLarge),
    ])
    func `failures offer the fallback`(reply: StubURLProtocol.Reply, expected: FeedbackError)
        async throws
    {
        let project = String(Int.random(in: 100_000 ... 999_999))
        _ = StubURLProtocol.route("/api/\(project)/", fallback: reply)
        let sender = try Self.sender(project: project)
        let payload = try Self.payload()
        await #expect(throws: expected) {
            try await sender.send(payload)
        }
    }
}
