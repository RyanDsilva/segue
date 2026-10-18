#if os(macOS)
    import Foundation
    import Observation
    import Services
    import Support

    /// Report a Problem's state (WS3 spec 8.2-8.4): the form, the frozen preview, sending and
    /// the fallbacks. What Send posts is always the `FeedbackPayload` the preview showed; any
    /// change after the preview needs a new one.
    @MainActor
    @Observable
    final class ReportProblemModel {
        /// Where the sheet is.
        enum Phase: Equatable {
            case editing
            /// The frozen payload, shown in full.
            case preview(FeedbackPayload)
            case sending(FeedbackPayload)
            /// Sent: the Sentry event id, copyable.
            case sent(eventID: String)
            /// Not sent; the content stays and the fallbacks are offered.
            case failed(FeedbackError, FeedbackPayload)
        }

        /// The current song's files, if a song is selected and readable.
        struct SongFiles: Equatable {
            var title: String
            var files: [FeedbackAttachment]
        }

        /// What the model needs from the app.
        struct Context {
            var services: ServicesHub
            var consent: ConsentState
            var diagnostics: any DiagnosticsSource
            var mail: any MailComposer
            var clock: any Clock
            var flavor: AppFlavor
            var library: SystemInfo.LibraryCounts
            /// Reads the selected song's `.cho` and sidecar.
            var currentSong: @MainActor () -> SongFiles?
            var log: DiagnosticLog?
        }

        static let messageLimit = FeedbackReportBuilder.messageLimit

        var message = ""
        var email = ""
        var attachLogs = false
        var attachMetricKit = false
        /// Off every time the sheet opens (R22).
        var attachSong = false

        private(set) var logs: [DiagnosticFile] = []
        private(set) var metricKit: DiagnosticFile?
        private(set) var song: SongFiles?
        private(set) var phase: Phase = .editing
        /// Why the report cannot be built as it stands (shown under the form).
        private(set) var problem: String?
        /// The logs were cut to their newest lines to fit the size cap (the preview says so).
        private(set) var trimmedLogs = false
        /// "Email Instead" could not open a draft (no mail account): offer Save Report.
        private(set) var mailUnavailable = false

        let context: Context
        private let builder: FeedbackReportBuilder
        private var sendTask: Task<Void, Never>?

        init(context: Context) {
            self.context = context
            let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
            builder = FeedbackReportBuilder(clientVersion: version ?? "0")
        }

        /// Reads the logs, the MetricKit payload and the current song; sets the defaults
        /// (logs and MetricKit on when present, the song always off).
        func load() async {
            logs = await context.diagnostics.recentLogFiles()
            metricKit = await context.diagnostics.latestMetricKitPayload()
            song = context.currentSong()
            attachLogs = !logs.isEmpty
            attachMetricKit = metricKit != nil
            attachSong = false
        }

        // MARK: Form state

        /// Unicode code points, as Sentry counts them.
        var messageCount: Int {
            FeedbackReportBuilder.normalizedMessage(message).unicodeScalars.count
        }

        var isOverLimit: Bool {
            messageCount > Self.messageLimit
        }

        var isEmailValid: Bool {
            let trimmed = email.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty || trimmed.wholeMatch(of: /[^@\s]+@[^@\s]+\.[^@\s]+/) != nil
        }

        var canSend: Bool {
            messageCount > 0 && !isOverLimit && isEmailValid
        }

        /// The report as the form stands.
        var report: FeedbackReport {
            var attachments: [FeedbackAttachment] = []
            if attachLogs {
                attachments += logs.map { FeedbackAttachment(kind: .log, file: $0) }
            }
            if attachMetricKit, let metricKit {
                attachments.append(FeedbackAttachment(kind: .metricKit, file: metricKit))
            }
            if attachSong, let song {
                attachments += song.files
            }
            return FeedbackReport(
                message: FeedbackReportBuilder.normalizedMessage(message),
                email: FeedbackReportBuilder.normalizedEmail(email),
                systemInfo: SystemInfo.make(
                    flavor: context.flavor,
                    library: context.library,
                    consent: context.consent,
                    logBytes: logs.reduce(0) { $0 + $1.data.count },
                ),
                attachments: attachments,
            )
        }

        // MARK: Preview and send

        /// Freezes the form into the payload Send will post and shows it.
        func preview() {
            guard canSend else { return }
            problem = nil
            do {
                phase = try .preview(freeze(report))
            } catch {
                problem = Self.describe(error)
            }
        }

        /// The form's Send: sends only what was previewed; anything else is previewed first.
        func sendFromForm() {
            if case let .preview(payload) = lastPreview, payload.report == report {
                send(payload)
            } else {
                preview()
            }
        }

        /// The last payload the user saw (kept while back at the form).
        private var lastPreview: Phase?

        /// Back from the preview (or a failure) to the form, keeping the content.
        func backToForm() {
            if case .preview = phase {
                lastPreview = phase
            }
            phase = .editing
        }

        func send(_ payload: FeedbackPayload) {
            guard sendTask == nil else { return }
            phase = .sending(payload)
            let sender = context.services.feedback
            sendTask = Task {
                defer { sendTask = nil }
                do throws(FeedbackError) {
                    try await sender.send(payload)
                    phase = .sent(eventID: payload.eventID)
                    recordSent(payload.report, transport: .sentry)
                } catch {
                    phase = .failed(error, payload)
                    context.log?.notice(.feedback, "fallback.offered")
                }
            }
        }

        func tryAgain() {
            if case let .failed(_, payload) = phase {
                send(payload)
            }
        }

        // MARK: Fallbacks

        /// "Email Instead": a draft to support with the report as text and the attachments
        /// from a temp folder (cleared at the next launch).
        func emailInstead() {
            let report = report
            do {
                let attachments = try ReportFiles.write(report, to: ReportFiles.newDraftFolder())
                let info = Bundle.main.infoDictionary ?? [:]
                let version = info["CFBundleShortVersionString"] as? String ?? "?"
                let build = info["CFBundleVersion"] as? String ?? "?"
                let opened = context.mail.compose(
                    to: SegueLinks.supportAddress,
                    subject: "Segue \(version) (\(build)) problem",
                    body: ReportFiles.text(report),
                    attachments: attachments,
                )
                mailUnavailable = !opened
                if opened {
                    recordSent(report, transport: .email)
                }
            } catch {
                problem = "Segue could not prepare the email (\(UserMessage.describe(error)))."
            }
        }

        /// "Save Report…": a folder with `report.txt` and the attachments.
        func saveReport() async {
            let report = report
            do {
                if try await ReportFiles.saveWithPanel(report, date: context.clock.now()) {
                    recordSent(report, transport: .file)
                }
            } catch {
                problem = "Segue could not save the report (\(UserMessage.describe(error)))."
            }
        }

        // MARK: Internals

        /// Builds the payload; when only the size cap is in the way, trims the logs to their
        /// newest lines and says so.
        private func freeze(_ report: FeedbackReport) throws(FeedbackReportError)
            -> FeedbackPayload
        {
            trimmedLogs = false
            do {
                return try builder.payload(
                    for: report,
                    eventID: UUID(),
                    timestamp: context.clock.now(),
                )
            } catch .tooLarge {
                var trimmed = report
                let others = report.attachments.filter { $0.kind != .log }
                let otherBytes = others.reduce(0) { $0 + $1.file.data.count }
                // Room for the event, headers and the email/description.
                let budget = FeedbackReportBuilder.envelopeByteLimit - otherBytes - 64 * 1024
                let logs = report.attachments.filter { $0.kind == .log }
                let share = max(0, budget / max(1, logs.count))
                trimmed.attachments = logs.map { log in
                    var log = log
                    log.file.data = Self.newestLines(of: log.file.data, fitting: share)
                    return log
                } + others
                trimmedLogs = true
                return try builder.payload(
                    for: trimmed,
                    eventID: UUID(),
                    timestamp: context.clock.now(),
                )
            }
        }

        /// The last whole lines of `data` within `limit` bytes.
        static func newestLines(of data: Data, fitting limit: Int) -> Data {
            guard data.count > limit else { return data }
            let tail = data.suffix(limit)
            guard let newline = tail.firstIndex(of: 0x0A) else { return Data() }
            return Data(tail[tail.index(after: newline)...])
        }

        private func recordSent(_ report: FeedbackReport, transport: FeedbackTransport) {
            let kinds = Set(report.attachments.map(\.kind))
            context.services.record(.feedbackSent(FeedbackSentSummary(
                transport: transport,
                logs: kinds.contains(.log),
                metricKit: kinds.contains(.metricKit),
                song: kinds.contains(.songFile),
                email: report.email != nil,
            )))
            let token: StaticString = switch transport {
            case .sentry: "sentry"
            case .email: "email"
            case .file: "file"
            }
            context.log?.notice(.feedback, "sent", ["transport": .token(token)])
        }

        static func describe(_ error: FeedbackReportError) -> String {
            switch error {
            case .emptyMessage:
                "Describe what happened first."
            case let .messageTooLong(limit):
                "Shorten the description to \(limit.formatted()) characters."
            case .feedbackContextTooLarge:
                "Shorten the description or the email address."
            case let .tooLarge(limit):
                "The report is over \(limit / 1_000_000) MB even with the logs shortened. "
                    + "Leave out the song file or the diagnostics."
            case .invalidAttachmentName:
                "One of the attachments has a name Segue cannot send."
            }
        }
    }
#endif
