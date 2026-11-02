import Foundation
import Plugins
import SwiftSoup

/// Ultimate Guitar's tab page (spec 8.4, bake-off 1.2): the chart is JSON in
/// `<div class="js-store" data-content>` (or `window.UGAPP.store`, wrapped as `{store: ...}`,
/// from the hidden view), at `store.page.data.tab_view.wiki_tab.content`, written as
/// `[ch]Em[/ch]` markup laid over already-aligned text. Navigated by key path, never a strict
/// model, so added fields cannot break it.
enum TabJSONParser {
    static let chordTypes: Set = ["chords", "ukulele chords"]
    static let proTypes: Set = ["pro", "power", "official", "guitar pro"]

    static func read(_ text: String, url: URL) -> PageReading {
        guard let store = store(in: text, url: url) else { return .unreadable }
        let data = HTMLText.value(store, ["store", "page", "data"])
        let tab = HTMLText.value(data, ["tab"])
        if let type = HTMLText.string(tab, ["type"])?.lowercased(), !chordTypes.contains(type) {
            return .refused(proTypes.contains(type) ? .pro : .tab)
        }
        var foundByContentSearch = false
        var content = HTMLText.string(data, ["tab_view", "wiki_tab", "content"])
        if content == nil {
            content = searchContent(store)
            foundByContentSearch = content != nil
        }
        guard let content, let converted = convert(content) else { return .unreadable }
        return .chart(ParsedChart(
            text: converted,
            fields: fields(tab: tab, meta: HTMLText.value(data, ["tab_view", "meta"])),
            foundByContentSearch: foundByContentSearch,
        ))
    }

    /// The store JSON: the in-page `{store: ...}` text, else the `js-store` attribute
    /// (SwiftSoup decodes the attribute's entities).
    static func store(in text: String, url: URL) -> [String: Any]? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("{") {
            return json(trimmed)
        }
        guard let document = HTMLText.document(text, url: url),
              let element = try? document.select("div.js-store[data-content]").first(),
              let attribute = try? element.attr("data-content")
        else { return nil }
        return json(attribute)
    }

    private static func json(_ text: String) -> [String: Any]? {
        guard let data = text.data(using: .utf8) else { return nil }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }

    /// Prior-art 1.4 item 2: when the path moves, the first string under a `content` key that
    /// holds UG markup.
    static func searchContent(_ object: Any) -> String? {
        if let dict = object as? [String: Any] {
            if let text = dict["content"] as? String,
               text.contains("[ch]") || text.contains("[tab]")
            {
                return text
            }
            for key in dict.keys.sorted() {
                if let found = dict[key].flatMap(searchContent) {
                    return found
                }
            }
        } else if let array = object as? [Any] {
            for item in array {
                if let found = searchContent(item) {
                    return found
                }
            }
        }
        return nil
    }

    // MARK: Fields

    static func fields(tab: Any?, meta: Any?) -> SourceFields {
        let artist = HTMLText.string(tab, ["artist_name"])
        var fields = HTMLText.string(tab, ["song_name"])
            .map { SourceCredits.fields(songName: $0, artist: artist) } ?? SourceFields()
        // Spec 5.4: a placeholder artist's singer comes from UG's structured credits.
        let singers = ((HTMLText.value(tab, ["recording", "recording_artists"]) as? [Any]) ?? [])
            .compactMap { HTMLText.string($0, ["artist", "name"]) }
        if let credit = SourceCredits.credit(artist) {
            fields.artistCredit = credit
        } else if !singers.isEmpty {
            fields.artistCredit = singers.joined(separator: ", ")
        }
        fields.key = HTMLText.string(tab, ["tonality_name"]) ?? HTMLText.string(meta, ["tonality"])
        fields.capo = HTMLText.int(meta, ["capo"])
        return fields
    }

    // MARK: Converting the markup (spec 8.4 steps 1-5)

    /// The chart as chords over lyrics, or nil when the chord-integrity check fails (8.5).
    static func convert(_ raw: String) -> String? {
        try? converted(raw).get()
    }

    /// The conversion, or the first line whose chord tokens, as written, differ from the
    /// `[ch]` tokens of its markup (the chord-integrity check, 8.5).
    static func converted(_ raw: String) -> Result<String, IntegrityFailure> {
        var text = HTMLText.decodeEntities(raw)
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        text = rejoinSplitChords(text)
        var lines: [String] = []
        for source in droppingLeadingNotes(text.components(separatedBy: "\n")) {
            let line = convertLine(source)
            let expected = chordTokens(inMarkup: source)
            if !expected.isEmpty {
                let written = line.split(whereSeparator: \.isWhitespace).map(bareToken)
                    .filter { expected.contains($0) }
                guard written == expected else {
                    return .failure(IntegrityFailure(
                        line: source,
                        expected: expected,
                        written: written,
                    ))
                }
            }
            lines.append(line)
        }
        return .success(lines.joined(separator: "\n")
            .replacing(/\n{3,}/, with: "\n\n")
            .trimmingCharacters(in: .newlines))
    }

    /// The contributor's notes above the first section header ("This is a simplified
    /// version...", fingering tables, "CAPO: II") are not part of the chart (the owner's
    /// gold review, R194): before the first `[Section]` line only chord and tab lines stay.
    static func droppingLeadingNotes(_ lines: [String]) -> [String] {
        // The first header that a chart line follows ("[Coda]" inside a fingering note is
        // not one).
        let first = lines.indices.first { index in
            isSectionHeader(lines[index]) && lines[(index + 1)...]
                .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
                .prefix(4).contains { $0.contains("[ch]") || $0.contains("|-") }
        }
        guard let first else { return lines }
        let head = lines[..<first].filter { line in
            line.contains("[ch]") || line.contains("|-") || isCreditLine(line)
        }
        return head + lines[first...]
    }

    /// "Singers: ...", "By ...", "Movie: ..." and the like stay: the converter reads credits.
    private static func isCreditLine(_ line: String) -> Bool {
        let label = /^(singers?|sung by|artists?|by|music|movie|film|album|lyric(s|ist)|composer)\b/
        return line.trimmingCharacters(in: .whitespaces).lowercased().contains(label)
    }

    private static func isSectionHeader(_ line: String) -> Bool {
        line.trimmingCharacters(in: .whitespaces)
            .wholeMatch(of: /\[(?!ch\]|tab\]|\/)[A-Za-z][^\]]{0,30}\]/) != nil
    }

    struct IntegrityFailure: Error, Sendable {
        var line: String
        var expected: [String]
        var written: [String]
    }

    /// Step 1: `[ch]D[/ch]/[ch]F#[/ch]` and `[ch]D[/ch]/F#` become `[ch]D/F#[/ch]`;
    /// `[ch]A[/ch](add9)` becomes `[ch]A(add9)[/ch]`.
    static func rejoinSplitChords(_ text: String) -> String {
        text
            .replacing(/\[ch\]([^\[]+)\[\/ch\]\/\[ch\]([^\[]+)\[\/ch\]/) {
                "[ch]\($0.output.1)/\($0.output.2)[/ch]"
            }
            .replacing(/\[ch\]([^\[]+)\[\/ch\]\/([A-G][#b]?)(?![A-Za-z])/) {
                "[ch]\($0.output.1)/\($0.output.2)[/ch]"
            }
            .replacing(/\[ch\]([^\[]+)\[\/ch\](\([^)\s]{1,8}\))/) {
                "[ch]\($0.output.1)\($0.output.2)[/ch]"
            }
    }

    private static func convertLine(_ line: String) -> String {
        var line = line
        // Step 4: `[verse]`-style section tags and `[b]`, `[i]`, `[u]` control tags.
        line = line
            .replacing(/(?i)\[(verse|chorus|bridge|intro|outro|pre-chorus|solo)\]/) { match in
                let name = match.output.1
                return "[\(name.prefix(1).uppercased())\(name.dropFirst().lowercased())]"
            }
        line = line.replacing(
            /(?i)\[\/(verse|chorus|bridge|intro|outro|pre-chorus|solo)\]/,
            with: "",
        )
        line = line.replacing(/\[\/?(b|i|u)\]/, with: "")
        line = line.replacingOccurrences(of: "[tab]", with: "").replacingOccurrences(
            of: "[/tab]",
            with: "",
        )
        // Step 2: re-space glued chords on chord-only lines only, so lyric columns never move.
        if isChordOnly(line) {
            line = line.replacing(/\[\/ch\]\[ch\]/, with: "[/ch] [ch]")
                .replacing(/\[\/ch\](?=\w)/, with: "[/ch] ")
        }
        // Step 3: the markers are laid over aligned text, so dropping them keeps the columns.
        return line.replacingOccurrences(of: "[ch]", with: "").replacingOccurrences(
            of: "[/ch]",
            with: "",
        )
    }

    private static func isChordOnly(_ line: String) -> Bool {
        guard line.contains("[ch]") else { return false }
        let rest = line.replacing(/\[ch\][^\[]*\[\/ch\]/, with: " ")
        return rest.allSatisfy { $0.isWhitespace || "|-/.()x0123456789:".contains($0) }
    }

    /// A written token without the brackets, bars and commas a chart puts around chords
    /// (`(G)`, `|C`, `D,`).
    static func bareToken(_ token: Substring) -> String {
        var bare = String(token).trimmingCharacters(in: CharacterSet(charactersIn: "[]|,"))
        if bare.hasPrefix("("), bare.hasSuffix(")") {
            bare = String(bare.dropFirst().dropLast())
        } else if bare.hasPrefix("(") {
            bare = String(bare.dropFirst())
        } else if bare.hasSuffix(")"), !bare.contains("(") {
            bare = String(bare.dropLast())
        }
        return bare
    }

    /// The `[ch]` tokens of the markup, in order.
    static func chordTokens(inMarkup text: String) -> [String] {
        text.matches(of: /\[ch\]([^\[]*)\[\/ch\]/)
            .map { String($0.output.1).trimmingCharacters(in: .whitespaces) }
    }
}
