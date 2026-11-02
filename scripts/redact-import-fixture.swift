#!/usr/bin/env swift
// Turns a saved page (or a recorded JSON response) into a committable, lyric-redacted fixture
// (P9-4 spec 16.2). Markup, attributes, JSON structure, chords, section headers, whitespace
// and line lengths are kept; every other word (lyrics, titles, names) is replaced by a
// deterministic placeholder of the same length and case pattern ("Hum tere bin" -> "Lor ipsu
// met"-like), so a word maps to the same placeholder everywhere in the corpus and a page's
// heading still matches its own fields. Inline scripts are dropped except JSON-LD and the
// small metadata objects the readers use; their strings are redacted the same way.
//
// Usage: swift scripts/redact-import-fixture.swift <input> <output>
// Manual; never part of quick, gate or check. The output is what gets committed.

import Foundation

// MARK: Words

/// Words kept as written: chord and section vocabulary, field labels, UG's placeholder
/// artists, and the site words a junk filter must still see.
let keptWords: Set = [
    "intro", "verse", "chorus", "prechorus", "pre", "bridge", "outro", "interlude", "solo",
    "hook", "refrain", "instrumental", "riff", "tag", "coda", "ending", "break", "post",
    "capo", "key", "tuning", "standard", "fret", "strumming", "pattern", "tempo", "bpm",
    "chords", "chord", "tab", "tabs", "lyrics", "by", "and", "feat", "ft", "featuring", "misc",
    "soundtrack", "unsigned", "bands", "traditional", "pro", "power", "official", "video",
    "ukulele", "bass", "guitar", "x", "repeat", "times", "music", "song", "songs", "movie",
    "album", "singer", "singers", "artist", "title", "version", "ver", "http", "https", "www",
    "com", "net", "org", "html", "htm", "php", "txt", "json", "true", "false", "null", "public",
    "type", "id", "the", "of", "on", "a", "i", "e", "b", "g", "d", "difficulty", "novice",
    "intermediate", "advanced", "beginner", "copyright", "letter", "violates", "block", "removed",
    "claiming", "that", "this", "their", "received", "someone", "have",
]

let chordPattern = try Regex(
    #"^[A-G](#|b)?(m|maj|min|dim|aug|sus|add|M|°|ø|\+)?[0-9]*((maj|sus|add|b|#|m|M|\+|-)?[0-9]*)*(\([^)]*\))?(/[A-G](#|b)?)?$"#,
)

let repeatMark = try Regex("^[xX][0-9]+$")

func isChord(_ word: Substring) -> Bool {
    word.wholeMatch(of: chordPattern) != nil
}

let consonants = Array("bcdfghjklmnprstvz")
let vowels = Array("aeiou")

/// FNV-1a, so the mapping is the same on every run and every machine.
func hash(_ text: String) -> UInt64 {
    var value: UInt64 = 0xCBF2_9CE4_8422_2325
    for byte in text.lowercased().utf8 {
        value = (value ^ UInt64(byte)) &* 0x0000_0100_0000_01B3
    }
    return value
}

/// A chord glued to the front of a word ("EmHum") keeps its chord, so the glued-chords
/// sanity check still sees the fault in a redacted fixture.
let gluedChord = try Regex("^([A-G][#b]?(m|7|m7|maj7|sus[24]|add9|dim)?)([A-Z][a-z].*)$")

func placeholder(_ word: Substring) -> String {
    if let match = word.wholeMatch(of: gluedChord), let chord = match.output[1].substring,
       let rest = match.output[3].substring
    {
        return String(chord) + letters(rest)
    }
    return letters(word)
}

/// Same length and case pattern; an uppercase A-G inside a word stays as written (a chord
/// glued into a word, "meCra").
func letters(_ word: Substring) -> String {
    var seed = hash(String(word))
    var result = ""
    for (index, char) in word.enumerated() {
        guard char.isLetter else {
            result.append(char)
            continue
        }
        if index > 0, char.isUppercase, "ABCDEFG".contains(char) {
            result.append(char)
            continue
        }
        let pool = index % 2 == 0 ? consonants : vowels
        let letter = pool[Int(seed % UInt64(pool.count))]
        seed = seed / UInt64(pool.count) ^ (seed &* 31)
        result.append(char.isUppercase ? Character(letter.uppercased()) : letter)
    }
    return result
}

/// Redacts the letter-words of `text`, keeping chords, kept words, one-letter words and
/// everything that is not a letter (digits, punctuation, spacing, tab lines).
func redactWords(_ text: String) -> String {
    var output = ""
    var word = Substring()
    var start = text.startIndex
    func flush(_ end: String.Index) {
        guard start < end else { return }
        word = text[start ..< end]
        let lowered = word.lowercased()
        if word.count <= 1 || keptWords.contains(lowered) || isChord(word)
            || word.wholeMatch(of: repeatMark) != nil
        {
            output += word
        } else {
            output += placeholder(word)
        }
    }
    var index = text.startIndex
    var inWord = false
    while index < text.endIndex {
        let char = text[index]
        let wordChar = char.isLetter || (inWord && (char == "'" || char.isNumber || char == "#"))
        if wordChar, !inWord {
            start = index
            inWord = true
        } else if !wordChar, inWord {
            flush(index)
            inWord = false
        }
        if !inWord {
            output.append(char)
        }
        index = text.index(after: index)
    }
    if inWord {
        flush(text.endIndex)
    }
    return output
}

// MARK: Chord markup inside text

/// UG content: `[ch]X[/ch]` chords and `[Verse 1]`-style headers kept, every other word redacted.
func redactMarkup(_ text: String) -> String {
    let token =
        try! Regex(
            #"\[/?(ch|tab|b|i|u|verse|chorus|bridge|intro|outro)\]|\[[A-Za-z][A-Za-z0-9 -]{0,30}\]"#,
        )
    var output = ""
    var cursor = text.startIndex
    var inChord = false
    for match in text.matches(of: token) {
        let gap = String(text[cursor ..< match.range.lowerBound])
        output += inChord ? gap : redactWords(gap)
        let tag = String(text[match.range])
        inChord = tag == "[ch]" ? true : (tag == "[/ch]" ? false : inChord)
        output += tag
        cursor = match.range.upperBound
    }
    output += redactWords(String(text[cursor...]))
    return output
}

// MARK: JSON

/// Keys whose string values are vocabulary, not content: kept as written.
let keptKeys: Set = [
    "type", "tonality_name", "tonality", "tab_access_type", "marketing_type", "difficulty",
    "status", "value", "name_of_tuning", "@type", "@context", "TYPE", "CHORDS_KEY", "CAPO",
    "date", "date_update", "index",
]

func redactJSON(_ value: Any, key: String? = nil) -> Any {
    switch value {
    case let dict as [String: Any]:
        return dict.reduce(into: [String: Any]()) { result, pair in
            result[pair.key] = redactJSON(pair.value, key: pair.key)
        }
    case let array as [Any]:
        return array.map { redactJSON($0, key: key) }
    case let text as String:
        if let key, keptKeys.contains(key) {
            return text
        }
        return text.contains("[ch]") || text
            .contains("[tab]") ? redactMarkup(text) : redactWords(text)
    default:
        return value
    }
}

/// UG's store carries the whole site's state (recommendations, charts, user data); only the
/// parts the tab and search readers use are kept.
let keptStoreData: Set = [
    "tab",
    "tab_view",
    "results",
    "results_count",
    "pagination",
    "search_query",
]

func pruned(_ object: Any) -> Any {
    guard var root = object as? [String: Any], var store = root["store"] as? [String: Any],
          var page = store["page"] as? [String: Any], let data = page["data"] as? [String: Any]
    else { return object }
    page["data"] = data.filter { keptStoreData.contains($0.key) }
    store = ["page": page]
    root["store"] = store
    return root
}

func redactJSONText(_ text: String) -> String? {
    guard let data = text.data(using: .utf8),
          let object = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
    else { return nil }
    let redacted = redactJSON(pruned(object))
    guard let out = try? JSONSerialization.data(
        withJSONObject: redacted,
        options: [.sortedKeys, .withoutEscapingSlashes],
    )
    else { return nil }
    return String(decoding: out, as: UTF8.self)
}

// MARK: HTML

func unescapeAttribute(_ text: String) -> String {
    var result = text
    for (entity, char) in [
        ("&quot;", "\""),
        ("&#039;", "'"),
        ("&#39;", "'"),
        ("&lt;", "<"),
        ("&gt;", ">"),
        ("&amp;", "&"),
    ] {
        result = result.replacingOccurrences(of: entity, with: char)
    }
    return result
}

func escapeAttribute(_ text: String) -> String {
    text.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "\"", with: "&quot;")
        .replacingOccurrences(of: "<", with: "&lt;").replacingOccurrences(of: ">", with: "&gt;")
}

/// Scripts the readers need: JSON-LD, UG's store, E-Chords' song metadata.
func redactScript(open: String, body: String) -> String? {
    if open.contains("application/ld+json") {
        return redactJSONText(body).map { open + $0 + "</script>" }
    }
    if body.contains("SONG_METADATA") || body.contains("UGAPP") {
        let literal = try! Regex(#""((?:[^"\\]|\\.)*)"|'((?:[^'\\]|\\.)*)'"#)
        let redacted = body.replacing(literal) { match in
            let whole = String(body[match.range])
            let quote = whole.first.map(String.init) ?? "\""
            return quote + redactWords(String(whole.dropFirst().dropLast())) + quote
        }
        return open + redacted + "</script>"
    }
    return nil
}

func redactHTML(_ html: String) -> String {
    let piece =
        try! Regex(
            #"(?is)<script\b[^>]*>.*?</script>|<style\b[^>]*>.*?</style>|<!--.*?-->|<[^>]+>"#,
        )
    var output = ""
    var cursor = html.startIndex
    for match in html.matches(of: piece) {
        output += redactText(String(html[cursor ..< match.range.lowerBound]))
        let tag = String(html[match.range])
        let lowered = tag.lowercased()
        if lowered.hasPrefix("<script") {
            if let close = tag.firstIndex(of: ">") {
                let open = String(tag[...close])
                let body = String(tag[tag.index(after: close)...].dropLast("</script>".count))
                if let kept = redactScript(open: open, body: body) {
                    output += kept
                }
            }
        } else if lowered.hasPrefix("<style") || lowered.hasPrefix("<!--") {
            // dropped: styling and comments carry nothing a reader uses
        } else {
            output += redactTag(tag)
        }
        cursor = match.range.upperBound
    }
    output += redactText(String(html[cursor...]))
    return output
}

/// Attribute values are redacted like text (titles, names and lyric snippets hide in `title`,
/// `alt`, `content`, `href`, `data-text`, custom `artist=`/`song=` attributes), except the
/// structural ones a reader selects by; `data-content` JSON is redacted as JSON.
let structuralAttributes: Set = [
    "class", "id", "style", "type", "rel", "charset", "name", "lang", "data-chord", "property",
    "itemprop", "itemtype", "itemscope", "width", "height", "dir", "role", "tabindex",
    "aria-hidden", "method", "target", "for", "colspan", "rowspan", "http-equiv", "media",
    "crossorigin", "integrity", "async", "defer", "sizes", "translate",
]

func redactTag(_ tag: String) -> String {
    let attribute = try! Regex(#"(?s)([A-Za-z_:][-A-Za-z0-9_:.]*)=("[^"]*"|'[^']*'|[^\s"'>]+)"#)
    return tag.replacing(attribute) { match in
        let name = String(match.output[1].substring ?? "")
        var raw = String(match.output[2].substring ?? "")
        var quote = ""
        if let first = raw.first, first == "\"" || first == "'" {
            quote = String(first)
            raw = String(raw.dropFirst().dropLast())
        }
        let lowered = name.lowercased()
        if lowered == "class" {
            // WordPress-style tag and category classes name the song and singer.
            let classes = raw.split(separator: " ").map { item in
                ["tag-", "category-", "post-"].contains { item.hasPrefix($0) }
                    ? redactWords(String(item)) : String(item)
            }
            return "\(name)=\(quote)\(classes.joined(separator: " "))\(quote)"
        }
        if structuralAttributes.contains(lowered) {
            return "\(name)=\(quote)\(raw)\(quote)"
        }
        let plain = unescapeAttribute(raw)
        let redacted = name == "data-content" ? (redactJSONText(plain) ?? redactWords(plain)) :
            redactWords(plain)
        let q = quote.isEmpty ? "\"" : quote
        return "\(name)=\(q)\(q == "'" ? redacted.replacingOccurrences(of: "'", with: "&#39;") : escapeAttribute(redacted))\(q)"
    }
}

/// Text between tags: entities (`&amp;`, `&#8217;`) stay as written, words are redacted.
func redactText(_ text: String) -> String {
    let entity = try! Regex(#"&[A-Za-z0-9#]+;"#)
    var output = ""
    var cursor = text.startIndex
    for match in text.matches(of: entity) {
        output += redactWords(String(text[cursor ..< match.range.lowerBound])) + text[match.range]
        cursor = match.range.upperBound
    }
    return output + redactWords(String(text[cursor...]))
}

// MARK: Main

let args = CommandLine.arguments
guard args.count == 3 else {
    FileHandle.standardError
        .write(Data("usage: redact-import-fixture.swift <input> <output>\n".utf8))
    exit(2)
}

let input = try String(contentsOfFile: args[1], encoding: .utf8)
let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
let output = (trimmed.hasPrefix("{") || trimmed.hasPrefix("[")) ?
    (redactJSONText(trimmed) ?? redactWords(input)) : redactHTML(input)
try output.write(toFile: args[2], atomically: true, encoding: .utf8)
print("\(args[2]): \(input.utf8.count) -> \(output.utf8.count) bytes")
