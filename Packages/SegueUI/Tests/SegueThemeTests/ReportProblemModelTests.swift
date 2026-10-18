import Foundation
@testable import SegueUI
import Services
import Support
import Testing

/// Report a Problem's model with the real builder, the Recording sender and real files:
/// nothing is sent unseen, the song file is off by default, oversized logs are trimmed to
/// their newest lines (and say so), and the saved folder holds exactly the report.
@MainActor
struct ReportProblemModelTests {
    struct Diagnostics: DiagnosticsSource {
        var logs: [DiagnosticFile]

        func recentLogFiles() async -> [DiagnosticFile] {
            logs
        }

        func latestMetricKitPayload() async -> DiagnosticFile? {
            nil
        }
    }

    static func model(logs: [DiagnosticFile], scratch: URL) -> (ReportProblemModel, RecordingLog) {
        let recording = RecordingLog(url: scratch.appending(path: "services.jsonl"))
        let hub = ServicesHub(
            factory: NullServicesFactory(),
            consent: .undecided,
            throttle: AnalyticsThrottle(suiteName: nil, clock: ManualClock()),
            feedback: RecordingFeedbackSender(log: recording),
        )
        let song = ReportProblemModel.SongFiles(title: "Pyaar Ki Raah", files: [
            FeedbackAttachment(kind: .songFile, file: DiagnosticFile(
                name: "pyaar-ki-raah.cho",
                contentType: "text/plain",
                data: Data("{title: Pyaar Ki Raah}\n".utf8),
            )),
        ])
        let model = ReportProblemModel(context: ReportProblemModel.Context(
            services: hub,
            consent: .undecided,
            diagnostics: Diagnostics(logs: logs),
            mail: SharingServiceMailComposer(),
            clock: ManualClock(),
            flavor: .personal,
            library: SystemInfo.LibraryCounts(songs: 12, setlists: 1),
            currentSong: { song },
            log: nil,
        ))
        return (model, recording)
    }

    static func scratch() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appending(path: "ReportProblemModelTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @Test
    func `send previews first and then posts exactly the previewed bytes`() async throws {
        let scratch = try Self.scratch()
        defer { try? FileManager.default.removeItem(at: scratch) }
        let log = DiagnosticFile(
            name: "segue-0.log",
            contentType: "text/plain",
            data: Data("a\n".utf8),
        )
        let (model, recording) = Self.model(logs: [log], scratch: scratch)
        await model.load()
        #expect(model.attachLogs)
        #expect(!model.attachSong, "the song file is attached by default")
        #expect(!model.canSend)

        model.message = "  It froze.  "
        model.sendFromForm()
        guard case let .preview(payload) = model.phase else {
            Issue.record("Send did not preview first: \(model.phase)")
            return
        }
        #expect(payload.report.message == "It froze.")
        #expect(payload.report.attachments.map(\.file.name) == ["segue-0.log"])
        #expect(recording.entries().isEmpty)

        // Changing anything after the preview needs a new one.
        model.backToForm()
        model.attachSong = true
        model.sendFromForm()
        guard case let .preview(second) = model.phase else {
            Issue.record("a changed report was sent without a new preview")
            return
        }
        #expect(second.report.attachments.map(\.file.name).contains("pyaar-ki-raah.cho"))
        model.send(second)
        for _ in 0 ..< 200 where model.phase != .sent(eventID: second.eventID) {
            try await Task.sleep(for: .milliseconds(10))
        }
        let sent = recording.entries().first { $0["kind"] as? String == "feedback" }
        #expect(sent?["sha256"] as? String == second.sha256)
        #expect(model.phase == .sent(eventID: second.eventID))
    }

    @Test
    func `oversized logs are trimmed to their newest whole lines`() async throws {
        let scratch = try Self.scratch()
        defer { try? FileManager.default.removeItem(at: scratch) }
        let line = String(repeating: "x", count: 99) + "\n"
        let big = Data(String(repeating: line, count: 30000).utf8) + Data("newest line\n".utf8)
        let logs = (0 ..< 2).map {
            DiagnosticFile(name: "segue-\($0).log", contentType: "text/plain", data: big)
        }
        let (model, _) = Self.model(logs: logs, scratch: scratch)
        await model.load()
        model.message = "Big logs."
        model.preview()
        guard case let .preview(payload) = model.phase else {
            Issue.record("no preview: \(String(describing: model.problem))")
            return
        }
        #expect(model.trimmedLogs)
        #expect(payload.envelope.count <= FeedbackReportBuilder.envelopeByteLimit)
        for attachment in payload.report.attachments {
            let text = try #require(String(bytes: attachment.file.data, encoding: .utf8))
            #expect(text.hasSuffix("newest line\n"))
            #expect(text.hasPrefix("x"), "a partial first line was kept")
        }
    }

    @Test
    func `the saved folder holds the report text and every attachment`() throws {
        let scratch = try Self.scratch()
        defer { try? FileManager.default.removeItem(at: scratch) }
        let report = FeedbackReport(
            message: "It froze.",
            email: "me@example.com",
            systemInfo: SystemInfo.make(
                flavor: .appStore,
                library: SystemInfo.LibraryCounts(songs: 3),
                consent: .undecided,
                logBytes: 2,
            ),
            attachments: [FeedbackAttachment(kind: .log, file: DiagnosticFile(
                name: "segue-0.log", contentType: "text/plain", data: Data("a\n".utf8),
            ))],
        )
        let folder = scratch.appending(path: "Segue Report")
        let urls = try ReportFiles.write(report, to: folder)
        #expect(urls.map(\.lastPathComponent) == ["segue-0.log"])
        let text = try String(contentsOf: folder.appending(path: "report.txt"), encoding: .utf8)
        #expect(text.contains("It froze."))
        #expect(text.contains("Reply to: me@example.com"))
        #expect(text.contains("Mac model: "))
        #expect(text.contains("Usage analytics: not asked yet"))
    }
}
