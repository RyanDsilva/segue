// Owner: P9-1 (spec 5.11). File names for exported PDFs.

import Foundation

public enum PrintFileName {
    public static let maximumLength = 120

    /// "<title>.pdf", "<setlist name>.pdf" or "Songbook (N songs).pdf", with " (Bass)" or
    /// " (Lyrics)" by part; "/" and ":" become "-"; trimmed to 120 characters before the
    /// extension; an untitled export is "Untitled.pdf".
    public static func name(title: String, part: PrintPart) -> String {
        var base = title
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if base.isEmpty {
            base = "Untitled"
        }
        let suffix = part.fileSuffix.map { " (\($0))" } ?? ""
        let room = maximumLength - suffix.count
        if base.count > room {
            base = String(base.prefix(room)).trimmingCharacters(in: .whitespaces)
        }
        return base + suffix + ".pdf"
    }

    /// A library selection's songbook: "Songbook (12 songs)".
    public static func selectionTitle(songs: Int) -> String {
        songs == 1 ? "Songbook (1 song)" : "Songbook (\(songs) songs)"
    }
}
