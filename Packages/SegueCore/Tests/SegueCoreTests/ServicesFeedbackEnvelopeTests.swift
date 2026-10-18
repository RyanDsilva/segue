import Foundation
import Services
import Testing

/// Envelope builder (spec 14.2-8): the bytes for a report carry exactly what the preview
/// shows, in the Sentry feedback envelope shape verified in step 1.
struct ServicesFeedbackEnvelopeTests {
    private struct Item {
        let header: [String: Any]
        let payload: Data
    }

    private static let systemInfo = FeedbackSystemInfo(
        appVersion: "0.5",
        buildNumber: "12",
        flavor: "appStore",
        macOSVersion: "26.6",
        modelIdentifier: "Mac15,3",
        architecture: "arm64",
        preferredLanguage: "en-US",
        songs: SongBucket(57),
        setlists: SmallBucket(3),
        gigs: SmallBucket(0),
        analyticsConsent: "granted",
        crashReportsConsent: "declined",
        logBytes: 2048,
    )

    private static let log = FeedbackAttachment(
        kind: .log,
        file: DiagnosticFile(
            name: "segue-0.log",
            contentType: "text/plain",
            data: Data("2026-10-17T21:03:11.402Z notice library opened songs=50-99\n".utf8),
        ),
    )

    private static let song = FeedbackAttachment(
        kind: .songFile,
        file: DiagnosticFile(
            name: "dil-kabhie.cho",
            contentType: "text/plain",
            data: Data("{title: Dil Kabhie}\n[G]dil kabhie\n".utf8),
        ),
    )

    private static let eventID = UUID(uuid: (
        0x0F, 0x1E, 0x2D, 0x3C, 0x4B, 0x5A, 0x69, 0x78,
        0x87, 0x96, 0xA5, 0xB4, 0xC3, 0xD2, 0xE1, 0xF0,
    ))

    private func parse(_ envelope: Data) throws -> (header: [String: Any], items: [Item]) {
        var rest = envelope[...]
        func line() throws -> Data {
            let end = rest.firstIndex(of: 0x0A) ?? rest.endIndex
            let value = Data(rest[rest.startIndex ..< end])
            rest = end == rest.endIndex ? rest[end...] : rest[rest.index(after: end)...]
            return value
        }
        func object(_ data: Data) throws -> [String: Any] {
            try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        }
        let header = try object(line())
        var items: [Item] = []
        while !rest.isEmpty {
            let itemHeader = try object(line())
            let length = try #require(itemHeader["length"] as? Int)
            let payload = Data(rest.prefix(length))
            #expect(payload.count == length)
            rest = rest.dropFirst(length)
            if rest.first == 0x0A {
                rest = rest.dropFirst()
            }
            items.append(Item(header: itemHeader, payload: payload))
        }
        return (header, items)
    }

    private func build(_ report: FeedbackReport) throws -> FeedbackPayload {
        try FeedbackReportBuilder(clientVersion: "0.5").payload(
            for: report,
            eventID: Self.eventID,
            timestamp: Date(timeIntervalSince1970: 1000),
        )
    }

    @Test
    func `envelope carries exactly the previewed fields and attachments`() throws {
        let report = FeedbackReport(
            message: "  Stage view froze after zoom\n",
            email: " me@example.com ",
            systemInfo: Self.systemInfo,
            attachments: [Self.log],
        )
        let payload = try build(report)
        let (header, items) = try parse(payload.envelope)

        #expect(Set(header.keys) == ["event_id", "sdk"])
        #expect(header["event_id"] as? String == "0f1e2d3c4b5a69788796a5b4c3d2e1f0")
        #expect(payload.eventID == "0f1e2d3c4b5a69788796a5b4c3d2e1f0")
        #expect(items.count == 2)

        let feedback = try #require(items.first)
        #expect(Set(feedback.header.keys) == ["type", "length"])
        #expect(feedback.header["type"] as? String == "feedback")
        let event = try #require(
            JSONSerialization.jsonObject(with: feedback.payload) as? [String: Any],
        )
        #expect(Set(event.keys) == ["event_id", "timestamp", "platform", "type", "contexts"])
        let contexts = try #require(event["contexts"] as? [String: Any])
        #expect(Set(contexts.keys) == ["feedback", "segue"])
        let feedbackContext = try #require(contexts["feedback"] as? [String: String])
        #expect(feedbackContext == [
            "message": "Stage view froze after zoom", "contact_email": "me@example.com",
        ])
        let segue = try #require(contexts["segue"] as? [String: String])
        let previewRows = Dictionary(
            uniqueKeysWithValues: report.systemInfo.fields.map { ($0.key, $0.value) },
        )
        #expect(segue == previewRows)

        let attachment = items[1]
        #expect(attachment.header["type"] as? String == "attachment")
        #expect(attachment.header["filename"] as? String == "segue-0.log")
        #expect(attachment.header["content_type"] as? String == "text/plain")
        #expect(attachment.header["attachment_type"] as? String == "event.attachment")
        #expect(attachment.payload == Self.log.file.data)
    }

    @Test
    func `song file is sent only when attached and the bytes are stable`() throws {
        let without = FeedbackReport(
            message: "Crash on save",
            email: nil,
            systemInfo: Self.systemInfo,
            attachments: [Self.log],
        )
        let first = try build(without)
        #expect(try build(without).envelope == first.envelope)
        #expect(try build(without).sha256 == first.sha256)
        #expect(first.sha256.count == 64)
        #expect(!first.envelope.contains(Data("dil kabhie".utf8)))
        let (_, items) = try parse(first.envelope)
        let event = try #require(
            JSONSerialization.jsonObject(with: items[0].payload) as? [String: Any],
        )
        let contexts = try #require(event["contexts"] as? [String: Any])
        #expect(contexts["feedback"] as? [String: String] == ["message": "Crash on save"])

        var with = without
        with.attachments.append(Self.song)
        let second = try build(with)
        #expect(second.sha256 != first.sha256)
        let (_, withItems) = try parse(second.envelope)
        #expect(withItems.map { $0.header["filename"] as? String } == [
            nil, "segue-0.log", "dil-kabhie.cho",
        ])
        #expect(withItems[2].payload == Self.song.file.data)
    }

    @Test
    func `invalid reports are rejected, never truncated`() {
        let builder = FeedbackReportBuilder(clientVersion: "0.5")
        func report(_ message: String, _ attachments: [FeedbackAttachment] = []) -> FeedbackReport {
            FeedbackReport(
                message: message,
                email: nil,
                systemInfo: Self.systemInfo,
                attachments: attachments,
            )
        }
        func attempt(_ report: FeedbackReport) -> FeedbackReportError? {
            do {
                _ = try builder.payload(for: report, eventID: Self.eventID, timestamp: .now)
                return nil
            } catch {
                return error
            }
        }
        #expect(attempt(report(" \n\t ")) == .emptyMessage)
        #expect(attempt(report(String(repeating: "a", count: 4096))) == nil)
        #expect(
            attempt(report(String(repeating: "a", count: 4097))) == .messageTooLong(limit: 4096),
        )
        // Devanagari: 3 UTF-8 bytes per code point, under the code point limit but over the
        // context byte budget.
        #expect(
            attempt(report(String(repeating: "\u{0926}", count: 3000)))
                == .feedbackContextTooLarge(limit: 8192),
        )
        let pathName = FeedbackAttachment(
            kind: .log,
            file: DiagnosticFile(name: "Logs/segue-0.log", contentType: "text/plain", data: Data()),
        )
        #expect(attempt(report("x", [pathName])) == .invalidAttachmentName)
        let huge = FeedbackAttachment(
            kind: .log,
            file: DiagnosticFile(
                name: "segue-1.log",
                contentType: "text/plain",
                data: Data(count: 5_000_001),
            ),
        )
        #expect(attempt(report("x", [huge])) == .tooLarge(limit: 5_000_000))
    }
}
