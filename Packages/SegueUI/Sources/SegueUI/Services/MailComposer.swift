#if os(macOS)
    import AppKit
    import Foundation

    /// Opens a draft email (Report a Problem's "Email Instead", WS3 spec 8.4). The live one
    /// is the system's Share > Mail; the E2E double records the draft.
    @MainActor
    public protocol MailComposer: AnyObject {
        /// Whether a draft with these attachments can be opened at all (a mail account
        /// exists).
        func canCompose(attachments: [URL]) -> Bool
        /// Opens a draft to `recipient`; returns whether it opened.
        @discardableResult
        func compose(to recipient: String, subject: String, body: String, attachments: [URL])
            -> Bool
    }

    /// `NSSharingService(named: .composeEmail)` with recipients and subject set.
    @MainActor
    public final class SharingServiceMailComposer: MailComposer {
        public init() {}

        public func canCompose(attachments: [URL]) -> Bool {
            NSSharingService(named: .composeEmail)?.canPerform(withItems: attachments) ?? false
        }

        public func compose(
            to recipient: String,
            subject: String,
            body: String,
            attachments: [URL],
        ) -> Bool {
            guard let service = NSSharingService(named: .composeEmail) else { return false }
            service.recipients = [recipient]
            service.subject = subject
            let items: [Any] = [body] + attachments
            guard service.canPerform(withItems: items) else { return false }
            service.perform(withItems: items)
            return true
        }
    }

    #if DEBUG
        /// Test-only (`-SegueMailLog <file>`): opens nothing; appends one JSON line per draft,
        /// `{"attachments":["segue-0.log"],"subject":"…","to":"…"}`.
        @MainActor
        public final class RecordingMailComposer: MailComposer {
            public let log: URL

            public init(log: URL) {
                self.log = log
            }

            public func canCompose(attachments _: [URL]) -> Bool {
                true
            }

            public func compose(
                to recipient: String,
                subject: String,
                body: String,
                attachments: [URL],
            ) -> Bool {
                let entry: [String: Any] = [
                    "to": recipient,
                    "subject": subject,
                    "bodyLines": body.split(separator: "\n").count,
                    "attachments": attachments.map(\.lastPathComponent),
                    "attachmentsExist": attachments.allSatisfy {
                        FileManager.default.fileExists(atPath: $0.path(percentEncoded: false))
                    },
                ]
                guard var line = try? JSONSerialization.data(
                    withJSONObject: entry,
                    options: [.sortedKeys, .withoutEscapingSlashes],
                ) else { return false }
                line.append(0x0A)
                if let handle = try? FileHandle(forWritingTo: log) {
                    defer { try? handle.close() }
                    _ = try? handle.seekToEnd()
                    try? handle.write(contentsOf: line)
                } else {
                    try? line.write(to: log, options: .atomic)
                }
                return true
            }
        }
    #endif
#endif
