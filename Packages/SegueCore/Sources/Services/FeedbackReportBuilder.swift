import Foundation

// MARK: - Sentry User Feedback envelope: verified shape (WS3 step 1 spike, 2026-10-17)

//
// Bug reports are posted as our own Sentry envelope instead of through the SDK (spec 3.5,
// B-24) so the preview shows every byte that is sent. The shape below was checked against:
//
// - Protocol docs: https://develop.sentry.dev/sdk/telemetry/feedbacks/ (feedback item),
//   https://develop.sentry.dev/sdk/telemetry/attachments/ (attachment item),
//   https://develop.sentry.dev/sdk/foundations/envelopes/ (framing, endpoint, limits),
//   https://develop.sentry.dev/sdk/data-model/envelope-items/ (item types).
// - sentry-cocoa 9.30.2 (latest stable): `SentryFeedback.internalSerialize()` in
//   Sources/Swift/Integrations/UserFeedback/SentryFeedback.swift,
//   `captureSerializedFeedback` in Sources/Sentry/SentryClient+ReplayAndFeedback.m,
//   `SentryEnvelopeItem(event:)`, `SentryEnvelopeItemHeader.serialize()`,
//   `SentryEnvelopeAttachmentHeader.serialize()` and
//   `SentrySerializationSwift.writeEnvelopeData` in Sources/Swift/Tools and Helper.
//
// Framing: `Envelope = Headers { "\n" Item }`, `Item = Headers "\n" Payload`. Each header is
// one line of JSON. sentry-cocoa writes the envelope header, then for every item "\n",
// the item header, "\n", the payload bytes; no trailing newline. We do the same.
//
// Envelope header: `event_id` (the feedback event id, 32 lowercase hex, no dashes, as
// `SentryId.sentryIdString`) and `sdk` (`name`, `version`). `sent_at` is optional (clock
// drift correction only); we omit it because the bytes are frozen at preview time, long
// before Send. No `dsn` header: the sender authenticates with `X-Sentry-Auth` instead.
//
// Feedback item: header `{"type":"feedback","length":<payload bytes>}`. The payload is an
// event whose required attributes are `event_id`, `timestamp` (Unix seconds) and
// `platform`; sentry-cocoa also sets `"type":"feedback"` on the event. The feedback itself
// is `contexts.feedback`:
//   - `message` (required; Sentry rejects a missing or whitespace-only message and one over
//     4,096 Unicode code points: "MUST NOT exceed 4,096 Unicode code points", counted like
//     Python `len`, i.e. `unicodeScalars.count`; forms must not truncate)
//   - `contact_email`, `name`, `url`, `associated_event_id`, `replay_id` (all optional)
//   - sentry-cocoa additionally sends `source` (`widget` / `custom`); it is not in the
//     protocol table, so we leave it out.
//   Relay normalises the feedback context within a shared `max_bytes = 8192` budget, so we
//   reject (never trim) a description plus email above 8,192 UTF-8 bytes.
// We send `message` and, when given, `contact_email`. Everything else the SDK path would add
// (user / installation id, release, environment, tags, breadcrumbs, device and OS contexts,
// SDK scope) is absent. The previewed system info travels as one custom context,
// `contexts.segue`, a flat object of strings keyed as `FeedbackSystemInfo.fields`.
//
// Attachment items: "SDKs MUST send attachment items in the same envelope as the feedback
// item". Header keys: `type` = `attachment` (required), `length` (required), `filename`
// (required, no path component), `content_type` (default `application/octet-stream`),
// `attachment_type` (default `event.attachment`; sentry-cocoa always writes it). Payload is
// the raw file bytes. Per-attachment server limit 20 MiB, event item 1 MiB, envelope
// 200 MiB; our own cap is 5 MB total (spec 8.3).
//
// Transport (implemented by `SentryEnvelopeFeedbackSender` in VendorServices, not here):
// `POST https://<host>/api/<project id>/envelope/` with
// `Content-Type: application/x-sentry-envelope` and
// `X-Sentry-Auth: Sentry sentry_version=7, sentry_key=<public key>,
// sentry_client=segue-feedback/<version>`.
//
// Not verifiable offline (left for step 6, live): that the endpoint accepts this exact
// envelope with a 2xx and that the report shows in Sentry's User Feedback view with its
// attachments and `contexts.segue`. If it is rejected, stop and ask (spec 3.5); never fall
// back to `SentrySDK.capture(feedback:)`.

/// Builds the exact bytes of a bug report (a Sentry envelope) and the preview model from
/// one `FeedbackReport`, so what the user sees is what is sent.
public struct FeedbackReportBuilder: Sendable {
    /// Sentry's limit on the feedback message, in Unicode code points.
    public static let messageLimit = 4096
    /// Relay's normalisation budget for the feedback context, in UTF-8 bytes.
    public static let feedbackContextByteLimit = 8192
    /// Our total report cap (spec 8.3).
    public static let envelopeByteLimit = 5_000_000

    /// `sdk.name` in the envelope header and the `sentry_client` name.
    public static let clientName = "segue-feedback"

    private let clientVersion: String

    /// `clientVersion` is the app's `CFBundleShortVersionString`.
    public init(clientVersion: String) {
        self.clientVersion = clientVersion
    }

    /// Freezes `report` into the envelope Send will post.
    ///
    /// - Parameters:
    ///   - eventID: the feedback event id (a fresh random UUID per preview).
    ///   - timestamp: when the preview was built; becomes the event's `timestamp`.
    public func payload(
        for report: FeedbackReport,
        eventID: UUID,
        timestamp: Date,
    ) throws(FeedbackReportError) -> FeedbackPayload {
        let (message, email) = try Self.validated(report)
        let id = Self.sentryID(eventID)
        var feedback: [String: Any] = ["message": message]
        if let email {
            feedback["contact_email"] = email
        }
        var segue: [String: Any] = [:]
        for field in report.systemInfo.fields {
            segue[field.key] = field.value
        }
        let event: [String: Any] = [
            "event_id": id,
            "timestamp": timestamp.timeIntervalSince1970,
            "platform": "cocoa",
            "type": "feedback",
            "contexts": ["feedback": feedback, "segue": segue],
        ]

        var envelope = Self.json([
            "event_id": id,
            "sdk": ["name": Self.clientName, "version": clientVersion],
        ])
        Self.appendItem(
            header: ["type": "feedback"],
            payload: Self.json(event),
            to: &envelope,
        )
        for attachment in report.attachments {
            Self.appendItem(
                header: [
                    "type": "attachment",
                    "filename": attachment.file.name,
                    "content_type": attachment.file.contentType,
                    "attachment_type": "event.attachment",
                ],
                payload: attachment.file.data,
                to: &envelope,
            )
        }
        guard envelope.count <= Self.envelopeByteLimit else {
            throw .tooLarge(limit: Self.envelopeByteLimit)
        }
        return FeedbackPayload(report: report, eventID: id, envelope: envelope)
    }

    /// The message and email as they will be sent, or the reason the report cannot be sent.
    private static func validated(
        _ report: FeedbackReport,
    ) throws(FeedbackReportError) -> (message: String, email: String?) {
        let message = normalizedMessage(report.message)
        guard !message.isEmpty else { throw .emptyMessage }
        guard message.unicodeScalars.count <= messageLimit else {
            throw .messageTooLong(limit: messageLimit)
        }
        let email = normalizedEmail(report.email)
        guard message.utf8.count + (email?.utf8.count ?? 0) <= feedbackContextByteLimit else {
            throw .feedbackContextTooLarge(limit: feedbackContextByteLimit)
        }
        for attachment in report.attachments {
            let name = attachment.file.name
            guard !name.isEmpty, !name.contains("/"), !name.contains(":") else {
                throw .invalidAttachmentName
            }
        }
        return (message, email)
    }

    /// The description as it will be sent: leading and trailing whitespace removed.
    public static func normalizedMessage(_ message: String) -> String {
        message.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// The email as it will be sent, or nil when blank.
    public static func normalizedEmail(_ email: String?) -> String? {
        guard let trimmed = email?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty
        else {
            return nil
        }
        return trimmed
    }

    // MARK: Encoding

    private static func sentryID(_ uuid: UUID) -> String {
        uuid.uuidString.replacingOccurrences(of: "-", with: "").lowercased()
    }

    private static func appendItem(header: [String: Any], payload: Data, to envelope: inout Data) {
        var header = header
        header["length"] = payload.count
        envelope.append(0x0A)
        envelope.append(json(header))
        envelope.append(0x0A)
        envelope.append(payload)
    }

    /// Single-line JSON with sorted keys so the same report always yields the same bytes.
    private static func json(_ object: [String: Any]) -> Data {
        // Only strings, numbers and nested dictionaries of them reach here, all valid JSON.
        (try? JSONSerialization.data(
            withJSONObject: object,
            options: [.sortedKeys, .withoutEscapingSlashes],
        )) ?? Data("{}".utf8)
    }
}
