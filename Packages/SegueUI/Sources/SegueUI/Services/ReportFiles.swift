#if os(macOS)
    import AppKit
    import Foundation
    import Services

    /// The report as files (WS3 spec 8.4): `report.txt` (description, email and system info)
    /// plus every attachment, for "Email Instead" (a temp folder in the container, cleared at
    /// the next launch because the draft must outlive the sheet) and "Save Report…" (a
    /// folder the user picks).
    public enum ReportFiles {
        /// The temp folder for email drafts, inside the app's container.
        static var draftsFolder: URL {
            URL.cachesDirectory.appending(path: "ReportDrafts", directoryHint: .isDirectory)
        }

        /// Deletes the drafts of earlier launches (the app calls this at launch).
        public static func clearDrafts() {
            try? FileManager.default.removeItem(at: draftsFolder)
        }

        /// The plain-text report: exactly the fields the preview shows.
        static func text(_ report: FeedbackReport) -> String {
            var lines = ["What happened?", report.message, ""]
            if let email = FeedbackReportBuilder.normalizedEmail(report.email) {
                lines += ["Reply to: \(email)", ""]
            }
            lines += report.systemInfo.fields.map { "\($0.label): \($0.value)" }
            if !report.attachments.isEmpty {
                lines += ["", "Attached:"] + report.attachments.map { "- \($0.file.name)" }
            }
            return lines.joined(separator: "\n") + "\n"
        }

        /// Writes `report.txt` and the attachments into `folder` (created); returns the
        /// attachment files' URLs.
        @discardableResult
        static func write(_ report: FeedbackReport, to folder: URL) throws -> [URL] {
            let manager = FileManager.default
            try manager.createDirectory(at: folder, withIntermediateDirectories: true)
            try Data(text(report).utf8).write(to: folder.appending(path: "report.txt"))
            return try report.attachments.map { attachment in
                let url = folder.appending(path: attachment.file.name, directoryHint: .notDirectory)
                try attachment.file.data.write(to: url, options: .atomic)
                return url
            }
        }

        /// A fresh draft folder for one email (`ReportDrafts/<uuid>`).
        static func newDraftFolder() -> URL {
            draftsFolder.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        }

        /// "Save Report…": a save panel for the folder `Segue Report <date>`; returns whether
        /// it was written.
        @MainActor
        static func saveWithPanel(_ report: FeedbackReport, date: Date) async throws -> Bool {
            let panel = NSSavePanel()
            panel.title = "Save Report"
            panel.message = "Segue saves the report and its attachments in a new folder."
            panel.prompt = "Save"
            panel.canCreateDirectories = true
            panel.nameFieldStringValue = "Segue Report "
                + date.formatted(.iso8601.year().month().day())
            let response = if let window = NSApp.keyWindow {
                await panel.beginSheetModal(for: window)
            } else {
                panel.runModal()
            }
            guard response == .OK, let url = panel.url else { return false }
            try write(report, to: url)
            return true
        }
    }
#endif
