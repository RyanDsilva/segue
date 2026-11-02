import Foundation
import Ingest
import Plugins
import SeguePersonalModules

/// One corpus page: its address (from `urls.tsv`), saved file and hand-written gold.
struct EvalRow {
    var site: String
    var lang: String
    var url: URL
    var file: URL
    var gold: Gold?
}

/// `gold/<slug>.json`, written by hand (spec 16.1). Lyrics live in gitignored files only.
struct Gold: Decodable {
    /// "chart", or the refusal the page must get: "notFound", "tab", "pro", "removed".
    var kind: String
    var title: String?
    var artists: [String]?
    var album: String?
    var key: String?
    var capo: Int?
    /// The chart's lyric words, in order (from an independent extraction, hand-checked).
    var lyrics: [String]?
    /// The chart's chords, in order.
    var chords: [String]?
    /// Lines the chart must contain (generic pages, where a full transcription is not kept).
    var mustContain: [String]?
    /// Generic pages: the least a found chart must hold (no full transcription is kept).
    var minChords: Int?
    var minLyricWords: Int?
}

enum EvalCorpus {
    static func load(root: URL) throws -> [EvalRow] {
        let table = try String(contentsOf: root.appending(path: "urls.tsv"), encoding: .utf8)
        var rows: [EvalRow] = []
        for line in table.split(separator: "\n") where !line.hasPrefix("#") {
            let parts = line.split(separator: "\t", omittingEmptySubsequences: false)
                .map(String.init)
            guard parts.count >= 4, parts[1] == "page",
                  let url = URL(string: parts[3]) else { continue }
            let slug = slug(parts[3])
            let file = root.appending(path: "pages/\(parts[0])/\(slug).html")
            guard FileManager.default.fileExists(atPath: file.path) else { continue }
            let goldURL = root.appending(path: "gold/\(slug).json")
            let data = try? Data(contentsOf: goldURL)
            let gold = data.flatMap { try? JSONDecoder().decode(Gold.self, from: $0) }
            rows.append(EvalRow(site: parts[0], lang: parts[2], url: url, file: file, gold: gold))
        }
        return rows
    }

    /// The collector's file name for an address (scripts/collect-import-corpus.sh `slug`).
    static func slug(_ text: String) -> String {
        guard let parts = URLComponents(string: text) else { return text }
        var raw = (parts.percentEncodedHost ?? "") + parts.percentEncodedPath
        if let query = parts.percentEncodedQuery {
            raw += "_" + query
        }
        return String(String(raw
                .map { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-") ? $0 : "_" })
            .prefix(150))
    }
}
