import Foundation
import Plugins
import SwiftSoup

/// E-Chords' song page, read through the hidden view (spec 8.4, bake-off 2.2): a `<pre>` of
/// chords over lyrics with each chord as `<span data-chord="F#m">F#m</span>` at its column,
/// inline `<b>(2x)</b>` and `<i>Intro:</i>`, tab blocks in a nested `div.tabs`. Fields from
/// JSON-LD `MusicComposition`, then the inline `window.SONG_METADATA` object.
enum ChordPreParser {
    static func read(_ html: String, url: URL) -> PageReading {
        guard let document = HTMLText.document(html, url: url),
              let pre = try? document.select("pre").first()
        else { return .unreadable }
        // Spans and markup are written as their text: a span on a line whose other tokens
        // are words (the site tags the Hindi word "Ab" as A-flat) stays lyric text, which is
        // how the converter then reads that line.
        let text = HTMLText.wholeText(of: pre)
            .replacingOccurrences(of: "\u{A0}", with: " ")
            .replacing(/[ \t]+\n/, with: "\n")
            .trimmingCharacters(in: .newlines)
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else { return .unreadable }
        let spans = (try? pre.select("span[data-chord]").array().count) ?? 0
        return .chart(ParsedChart(
            text: text,
            fields: fields(document, html: html),
            chordMarks: spans,
        ))
    }

    static func fields(_ document: Document, html: String) -> SourceFields {
        let composition = HTMLText.jsonLD(document, types: ["MusicComposition", "MusicRecording"])
        let metadata = songMetadata(html)
        let name = HTMLText.string(composition, ["name"]) ?? metadata["NAME"]
        let byArtist = HTMLText.value(composition, ["recordedAs", "byArtist"])
        let artist = HTMLText.string(byArtist, ["name"])
            ?? ((byArtist as? [Any])?.first).flatMap { HTMLText.string($0, ["name"]) }
            ?? metadata["ARTIST_NAME"]
        var fields = SourceFields()
        if let name {
            let split = SourceCredits.titleAndAlbum(songName: name, artist: artist)
            fields.title = split.title
            fields.album = split.album
        }
        fields.artistCredit = SourceCredits.credit(artist)
        fields.key = metadata["CHORDS_KEY"] ?? HTMLText.string(composition, ["musicalKey"])
        fields.capo = metadata["CAPO"].flatMap { Int($0) }
        return fields
    }

    /// `KEY: 'value'` or `KEY: value,` pairs of the inline `window.SONG_METADATA` object.
    static func songMetadata(_ html: String) -> [String: String] {
        guard let start = html.range(of: "SONG_METADATA") else { return [:] }
        let tail = html[start.upperBound...].prefix(4000)
        var result: [String: String] = [:]
        for match in tail
            .matches(of: /([A-Z_]+)\s*:\s*(?:'((?:[^'\\]|\\.)*)'|"((?:[^"\\]|\\.)*)"|(-?\d+))/)
        {
            let key = String(match.output.1)
            guard result[key] == nil else { continue }
            let value = match.output.2 ?? match.output.3 ?? match.output.4
            if let value {
                result[key] = String(value)
            }
        }
        return result
    }
}
