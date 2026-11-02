import Foundation
import Plugins
import SwiftSoup

/// Chordie's song page (spec 8.4, verified 3.6): an aggregator that re-renders other sites'
/// charts as `div.chordline` lines with each chord in `span.absc` between bracket spans, and
/// `div.textline` for plain lines. Written as inline `[X]` chords for the converter.
enum ChordSpansParser {
    /// Bake-off 2.1: a song the site blocked after a copyright letter, served with HTTP 200.
    static let removalNotice = "claiming that this song violates their copyright"

    static func read(_ html: String, url: URL) -> PageReading {
        guard let document = HTMLText.document(html, url: url) else { return .unreadable }
        if (try? document.body()?.text())?.contains(removalNotice) == true {
            return .refused(.removed)
        }
        let lines = (try? document.select("div.chordline, div.textline").array()) ?? []
        guard !lines.isEmpty else { return .unreadable }
        let text = lines.map(line).joined(separator: "\n")
            .replacing(/\n{3,}/, with: "\n\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return .chart(ParsedChart(text: text, fields: fields(document)))
    }

    /// One line: text as written, each `span.absc` chord as `[X]` in place, the bracket spans
    /// dropped; Chordie's one leading space removed.
    static func line(_ element: Element) -> String {
        let text = HTMLText.wholeText(of: element) { child in
            if child.hasClass("bracket") {
                return ""
            }
            if child.hasClass("absc") {
                return "[" + ((try? child.text()) ?? "") + "]"
            }
            return nil
        }
        let trimmed = text.replacingOccurrences(of: "\u{A0}", with: " ")
        let line = trimmed.hasPrefix(" ") ? String(trimmed.dropFirst()) : trimmed
        return line.trimmingCharacters(in: .whitespaces).isEmpty ? "" : line
    }

    /// The heading `<h1>Title&nbsp;&nbsp;<a><span>Artist</span></a></h1>`, else the
    /// `<title>` "<Title> <Artist> Chords and Lyrics for Guitar" (title only, since the split
    /// is ambiguous without the heading).
    static func fields(_ document: Document) -> SourceFields {
        var fields = SourceFields()
        if let heading = try? document.select("h1").first() {
            let artist = try? heading.select("a").first()?.text()
            fields.title = heading.ownText().replacingOccurrences(of: "\u{A0}", with: " ")
                .trimmingCharacters(in: .whitespaces)
            fields.artistCredit = artist.flatMap { $0.isEmpty ? nil : $0 }
        }
        if fields.title?.isEmpty ?? true, let title = HTMLText.title(document) {
            fields.title = title.replacing(/(?i)\s*chords and lyrics( for guitar)?\s*$/, with: "")
        }
        return fields
    }
}
