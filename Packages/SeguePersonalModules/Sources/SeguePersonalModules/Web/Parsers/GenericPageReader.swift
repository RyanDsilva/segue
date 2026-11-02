import Foundation
import Ingest
import Plugins
import SwiftSoup

/// Any other page (spec 8.4): drop the page furniture, gather candidate blocks (`<pre>`,
/// `<textarea>`, `<code>`, chord- or lyric-named elements, elements with 4+ `<br>`), render
/// each to text, score it with the paste pipeline's own line classifier and keep the best.
/// A plain-text page (a `.txt` sheet) is its own single candidate.
enum GenericPageReader {
    static let droppedTags = [
        "script", "style", "noscript", "template", "svg", "iframe", "form", "nav", "header",
        "footer", "aside", "button", "select",
    ]
    /// Whole class or id words that mark page furniture.
    static let furnitureWords: Set = [
        "ad", "ads", "advert", "advertisement", "adsbygoogle", "comment", "comments", "share",
        "sharing", "social", "related", "menu", "cookie", "cookies", "banner", "sidebar",
        "widget", "breadcrumb", "breadcrumbs", "newsletter", "popup", "modal",
    ]
    static let candidateWords = [
        "chord",
        "lyric",
        "tab",
        "song",
        "sheet",
        "chart",
        "entry-content",
        "post-body",
    ]
    static let blockTags: Set = [
        "p", "div", "li", "h1", "h2", "h3", "h4", "h5", "h6", "tr", "pre", "section", "article",
        "blockquote", "table", "ul", "ol", "dd", "dt",
    ]
    static let minimumLines = 4

    static func read(_ text: String, url: URL) -> PageReading {
        if isPlainText(text) {
            let chart = clean(text)
            return chart.isEmpty ? .unreadable : .chart(ParsedChart(
                text: chart,
                fields: SourceFields(),
            ))
        }
        guard let document = HTMLText.document(text, url: url) else { return .unreadable }
        let fields = fields(document, url: url)
        guard let body = document.body() else { return .unreadable }
        strip(body)
        let candidates = candidates(in: body)
        var best: Candidate?
        for element in candidates {
            let rendered = clean(render(element))
            let lines = rendered.components(separatedBy: "\n")
            guard lines
                .count(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty }) >= minimumLines
            else { continue }
            var score = score(lines)
            if isChordPro(element) {
                score += 100
            }
            guard let current = best else {
                best = Candidate(element: element, text: rendered, score: score)
                continue
            }
            let nested = isAncestor(current.element, of: element)
            if score > current.score || (nested && Double(score) >= Double(current.score) * 0.9) {
                best = Candidate(element: element, text: rendered, score: score)
            }
        }
        guard let best, best.score > 0 else { return .unreadable }
        return .chart(ParsedChart(text: best.text, fields: fields))
    }

    // MARK: Candidates

    private struct Candidate {
        var element: Element
        var text: String
        var score: Int
    }

    static func isPlainText(_ text: String) -> Bool {
        let head = text.prefix(512).lowercased()
        return !head.contains("<html") && !head.contains("<body") && !head.contains("<!doctype")
            && !head.contains("<div") && !head.contains("<p>")
    }

    private static func strip(_ body: Element) {
        for tag in droppedTags {
            _ = try? body.select(tag).remove()
        }
        let all = (try? body.getAllElements().array()) ?? []
        for element in all where isFurniture(element) {
            try? element.remove()
        }
    }

    static func isFurniture(_ element: Element) -> Bool {
        let names = ((try? element.className()) ?? "") + " " + element.id()
        let words = names.lowercased().split { !$0.isLetter && !$0.isNumber }.map(String.init)
        return words.contains(where: furnitureWords.contains)
    }

    private static func candidates(in body: Element) -> [Element] {
        let all = (try? body.getAllElements().array()) ?? []
        return all.filter { element in
            let tag = element.tagName()
            if tag == "pre" || tag == "textarea" || tag == "code" {
                return true
            }
            let names = (((try? element.className()) ?? "") + " " + element.id()).lowercased()
            if candidateWords.contains(where: names.contains) {
                return true
            }
            return element.children().array().count(where: { $0.tagName() == "br" }) >= 4
        }
    }

    private static func isChordPro(_ element: Element) -> Bool {
        let names = (((try? element.className()) ?? "") + " " + element.id()).lowercased()
        return names.contains("chordpro") || ((try? element.attr(
            "data-format",
        )) ?? "") == "chordpro"
    }

    private static func isAncestor(_ ancestor: Element, of element: Element) -> Bool {
        var node = element.parent()
        while let current = node {
            if current === ancestor {
                return true
            }
            node = current.parent()
        }
        return false
    }

    // MARK: Rendering

    /// `<br>` and block ends become newlines; whitespace is kept inside `<pre>` and
    /// monospace-styled elements and collapsed elsewhere; an inline element whose whole text
    /// is a chord, outside `<pre>`, becomes `[X]` in place (pages that mark chords inline).
    static func render(_ element: Element) -> String {
        render(element, preformatted: isPreformatted(element))
    }

    private static func render(_ element: Element, preformatted: Bool) -> String {
        var output = ""
        for child in element.getChildNodes() {
            if let text = child as? TextNode {
                let raw = text.getWholeText()
                output += preformatted ? raw : raw.replacing(/\s+/, with: " ")
            } else if let child = child as? Element {
                let tag = child.tagName()
                if tag == "br" {
                    output += "\n"
                    continue
                }
                let inner = render(child, preformatted: preformatted || isPreformatted(child))
                if !preformatted, !blockTags.contains(tag),
                   IngestPipeline.isChordToken(inner.trimmingCharacters(in: .whitespaces))
                {
                    output += "[" + inner.trimmingCharacters(in: .whitespaces) + "]"
                } else if blockTags.contains(tag) {
                    output += "\n" + inner + "\n"
                } else {
                    output += inner
                }
            }
        }
        return output
    }

    private static func isPreformatted(_ element: Element) -> Bool {
        let tag = element.tagName()
        if tag == "pre" || tag == "textarea" || tag == "code" {
            return true
        }
        let style = ((try? element.attr("style")) ?? "").lowercased()
        return style.contains("monospace") || style.contains("white-space: pre")
            || style.contains("white-space:pre")
    }

    /// Non-breaking spaces as spaces, trailing spaces trimmed, runs of blank lines folded,
    /// junk lines (print links, ratings, site words) dropped.
    static func clean(_ text: String) -> String {
        text.replacingOccurrences(of: "\u{A0}", with: " ")
            .replacingOccurrences(of: "\r\n", with: "\n")
            .components(separatedBy: "\n")
            .map { line in
                var line = line
                while line.last?.isWhitespace == true {
                    line.removeLast()
                }
                return line
            }
            .filter { !IngestPipeline.isJunkLine($0) }
            .joined(separator: "\n")
            .replacing(/\n{3,}/, with: "\n\n")
            .trimmingCharacters(in: .newlines)
    }

    /// +3 per chord line followed by a lyric line, +1 per lyric line, +2 per section header,
    /// -2 per junk line, -1 per line over 200 characters.
    static func score(_ lines: [String]) -> Int {
        let classes = IngestPipeline.lineClasses(lines)
        var score = 0
        for (index, lineClass) in classes.enumerated() {
            switch lineClass {
            case .chordLine:
                if index + 1 < classes.count, classes[index + 1] == .lyricLine {
                    score += 3
                }
            case .lyricLine:
                score += 1
                if lines[index].contains("[") {
                    score += 1
                }
            case .headerLine: score += 2
            default: break
            }
            if IngestPipeline.isJunkLine(lines[index]) {
                score -= 2
            }
            if lines[index].count > 200 {
                score -= 1
            }
        }
        return score
    }

    // MARK: Fields

    /// JSON-LD, then `og:title`, then `<h1>`, then `<title>`, each read with the usual
    /// heading patterns and checked with `isPlausibleName`.
    static func fields(_ document: Document, url: URL? = nil) -> SourceFields {
        if let item = HTMLText.jsonLD(document, types: ["MusicComposition", "MusicRecording"]),
           let name = HTMLText.string(item, ["name"])
        {
            let artist = HTMLText.string(item, ["byArtist", "name"])
                ?? HTMLText.string(item, ["recordedAs", "byArtist", "name"])
            var fields = heading(name, url: url)
            if let artist, IngestPipeline.isPlausibleName(artist) {
                fields.artistCredit = artist
            }
            fields.album = HTMLText.string(item, ["inAlbum", "name"])
            return fields
        }
        let sources = [
            HTMLText.meta(document, property: "og:title"),
            try? document.select("h1").first()?.text(),
            HTMLText.title(document),
        ]
        for source in sources.compactMap(\.self) {
            let fields = heading(source, url: url)
            if fields.title != nil {
                return fields
            }
        }
        return SourceFields()
    }

    /// "X Chords by Y", "X - Y Chords", "X Chords", "X Lyrics". A site suffix after "|" and
    /// an "@ ..." tail are dropped first. In "X - Y Chords" the part the page's own address
    /// names is the title (sites write both "Artist - Title" and "Title - Artist").
    static func heading(_ text: String, url: URL? = nil) -> SourceFields {
        var value = text.replacingOccurrences(of: "\u{A0}", with: " ")
            .replacingOccurrences(of: " \u{2013} ", with: " - ")
            .replacingOccurrences(of: " \u{2014} ", with: " - ")
            .replacing(/\s+/, with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if let bar = value.firstIndex(of: "|") {
            value = value[..<bar].trimmingCharacters(in: .whitespaces)
        }
        value = value.replacing(/\s*@.*$/, with: "")
        // An unbalanced "(" left by the cut ("Tum Hi Ho (Aashiqui 2 | Guitar Chords)").
        if let open = value.lastIndex(of: "("), !value[open...].contains(")") {
            value = value[..<open].trimmingCharacters(in: .whitespaces)
        }
        value = value.replacing(
            /(?i)\s*(guitar|ukulele|piano)?\s*(chords|tabs?)?\s*(and|&|with)?\s*lyrics\s*$/,
            with: "",
        )
        var fields = SourceFields()
        if let match = value.wholeMatch(of: /(?i)(.+?)\s+(?:guitar\s+)?chords\s+by\s+(.+)/) {
            fields.title = String(match.output.1)
            fields.artistCredit = String(match.output.2)
        } else if let match = value
            .wholeMatch(of: /(?i)(.+?)\s+-\s+(.+?)\s+(?:guitar\s+)?(?:chords|tabs?)\b.*/)
        {
            let (first, second) = (String(match.output.1), String(match.output.2))
            let swap = url.map { named(second, in: $0) && !named(first, in: $0) } ?? false
            fields.title = swap ? second : first
            fields.artistCredit = swap ? first : second
        } else if let match = value
            .wholeMatch(of: /(?i)(.+?)\s+(?:guitar\s+)?(?:chords|tabs?)\b.*/)
        {
            fields.title = String(match.output.1)
        } else {
            fields.title = value
        }
        fields.title = plausible(fields.title)
        fields.artistCredit = plausible(fields.artistCredit)
        return fields
    }

    private static func plausible(_ value: String?) -> String? {
        guard let value = value?.trimmingCharacters(in: .whitespaces), !value.isEmpty,
              value.contains(where: \.isLetter), IngestPipeline.isPlausibleName(value)
        else { return nil }
        return value
    }

    /// Whether the address's last path part spells `name` (letters and digits only).
    static func named(_ name: String, in url: URL) -> Bool {
        let squash: (String) -> String = { $0.lowercased().filter { $0.isLetter || $0.isNumber } }
        let key = squash(name)
        return !key.isEmpty && squash(url.lastPathComponent).contains(key)
    }
}
