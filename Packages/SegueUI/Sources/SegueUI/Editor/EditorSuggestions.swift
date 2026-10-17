import Foundation

/// Chord autocomplete (phase 1 spec, "Chord autocomplete on `[`"): chords already in the
/// song first, then the diatonic chords of the key, then common extensions of the typed
/// root. Typing filters. Only ever offered after `[` or in the visual chord popover, never
/// on plain lyric words.
/// One `[` completion: what the chip shows, and the chord text it inserts (they differ in
/// Nashville view, where a number inserts the source letters).
struct ChordCompletion: Equatable {
    let title: String
    let insertion: String
}

enum ChordSuggestions {
    /// Common chord suffixes offered for the typed root (unit D owns this list).
    static let extensionSuffixes = [
        "", "m", "7", "m7", "maj7", "sus4", "sus2", "add9", "6", "m6", "9", "m9",
        "7sus4", "dim", "dim7", "aug", "m7b5", "maj9", "11", "13",
    ]

    /// Suggestions for `prefix` (what follows the `[`), most relevant first, de-duplicated.
    /// - Parameters:
    ///   - songChords: chord texts already in the song, in order of first appearance.
    ///   - diatonic: the key's diatonic chord symbols (`SongKey.diatonicChordSymbols`).
    ///   - numbers: Nashville view: a typed degree (`4`, `b7`) gets extensions too.
    static func chords(
        prefix rawPrefix: String,
        songChords: [String],
        diatonic: [String],
        numbers: Bool = false,
        limit: Int = 10,
    ) -> [String] {
        let prefix = normalized(rawPrefix)
        var extensions: [String] = []
        if let root = root(of: prefix) {
            extensions = extensionSuffixes.map { root + $0 }
        } else if numbers, let degree = degree(of: prefix) {
            // Nashville numbers: a suffix starting with a digit is parenthesised (`5(7)`).
            extensions = extensionSuffixes.map { suffix in
                suffix.first?.isNumber == true ? "\(degree)(\(suffix))" : degree + suffix
            }
        }
        var seen = Set<String>()
        var result: [String] = []
        for candidate in songChords + diatonic + extensions {
            let trimmed = candidate.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty, trimmed.hasPrefix(prefix), seen.insert(trimmed).inserted
            else { continue }
            result.append(trimmed)
            if result.count == limit {
                break
            }
        }
        return result
    }

    /// Upper-cases a leading root letter, so `[e` matches `Em` (but not the flat of a
    /// Nashville degree: `b7` stays `b7`).
    static func normalized(_ prefix: String) -> String {
        guard let first = prefix.first, "abcdefg".contains(first), degree(of: prefix) == nil
        else { return prefix }
        return first.uppercased() + prefix.dropFirst()
    }

    /// The Nashville degree at the start of `prefix` (`4`, `b7`, `#4`), if it starts with
    /// one.
    static func degree(of prefix: String) -> String? {
        var degree = ""
        var rest = Substring(prefix)
        if let first = rest.first, first == "b" || first == "#" {
            degree.append(first)
            rest = rest.dropFirst()
        }
        guard let digit = rest.first, ("1" ... "7").contains(digit) else { return nil }
        degree.append(digit)
        return degree
    }

    /// The root spelled at the start of `prefix` (`F#`, `Bb`, `E`), if it starts with one.
    static func root(of prefix: String) -> String? {
        guard let first = prefix.first, "ABCDEFG".contains(first) else { return nil }
        let rest = prefix.dropFirst()
        if let accidental = rest.first, accidental == "#" || accidental == "b" {
            return String(first) + String(accidental)
        }
        return String(first)
    }
}

/// Directive completion on `{` (phase 1 spec): metadata, sections and `define`.
enum DirectiveSuggestions {
    struct Item: Equatable, Identifiable {
        /// The directive name (`title`, `start_of_chorus`).
        let name: String
        /// Whether it takes a value: inserted as `{name: }` with the caret before `}`.
        let takesValue: Bool

        var id: String {
            name
        }

        /// The text inserted after `{` (`title: }`), and where the caret goes in it.
        var completion: (text: String, caretOffset: Int) {
            if takesValue {
                let text = name + ": }"
                return (text, text.utf16.count - 1)
            }
            let text = name + "}"
            return (text, text.utf16.count)
        }
    }

    static let sectionKinds = ["verse", "chorus", "bridge", "tab", "grid"]

    static let all: [Item] = [
        Item(name: "title", takesValue: true),
        Item(name: "artist", takesValue: true),
        Item(name: "key", takesValue: true),
        Item(name: "capo", takesValue: true),
        Item(name: "tempo", takesValue: true),
        Item(name: "time", takesValue: true),
        Item(name: "duration", takesValue: true),
    ] + sectionKinds.map { Item(name: "start_of_\($0)", takesValue: false) }
        + sectionKinds.map { Item(name: "end_of_\($0)", takesValue: false) }
        + [
            Item(name: "chorus", takesValue: false),
            Item(name: "comment", takesValue: true),
            Item(name: "subtitle", takesValue: true),
            Item(name: "define", takesValue: true),
            Item(name: "meta", takesValue: true),
        ]

    /// Directives matching `prefix`. When the caret is inside an open section, its
    /// `end_of_...` comes first.
    static func items(prefix: String, openSection: String?, limit: Int = 10) -> [Item] {
        let lowered = prefix.lowercased()
        var ordered = all
        if let openSection, let index = ordered.firstIndex(where: {
            $0.name == "end_of_\(openSection)"
        }) {
            ordered.insert(ordered.remove(at: index), at: 0)
        }
        return Array(ordered.filter { $0.name.hasPrefix(lowered) }.prefix(limit))
    }

    /// The kind of the section open at `offset` in `text` (the last `{start_of_x}` before it
    /// without a matching `{end_of_x}`), e.g. `"chorus"`.
    static func openSection(in text: String, before offset: Int) -> String? {
        let head = (text as NSString).substring(to: min(offset, (text as NSString).length))
        var open: String?
        for line in head.split(separator: "\n", omittingEmptySubsequences: true) {
            let trimmed = line.trimmingCharacters(in: .whitespaces).lowercased()
            guard trimmed.hasPrefix("{") else { continue }
            let body = trimmed.dropFirst().prefix { $0 != ":" && $0 != "}" && $0 != " " }
            if body.hasPrefix("start_of_") {
                open = String(body.dropFirst("start_of_".count))
            } else if body.hasPrefix("so") && body.count <= 3 {
                open = Self.shortSection(String(body))
            } else if body.hasPrefix("end_of_") || (body.hasPrefix("eo") && body.count <= 3) {
                open = nil
            }
        }
        return open
    }

    /// `{soc}` / `{sov}` / `{sob}` / `{sot}` short forms.
    private static func shortSection(_ body: String) -> String? {
        switch body {
        case "soc": "chorus"
        case "sov": "verse"
        case "sob": "bridge"
        case "sot": "tab"
        case "sog": "grid"
        default: nil
        }
    }
}
