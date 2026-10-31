import ChordPro
import Editing
import Foundation
import MusicTheory

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

/// Directive completion on `{` (phase 1 spec, fixed by R81): every item shows a plain
/// name beside its directive; a section word (`{cho`, `{verse`, `{int`) offers the
/// `start_of_` forms first (labelled when the numbering rule gives a label); ChordPro's short forms
/// (`soc`, `eov`, `c`)
/// are aliases of the long forms they stand for.
enum DirectiveSuggestions {
    struct Item: Equatable, Identifiable {
        /// Plain name ("Chorus 2", "Time signature").
        let title: String
        /// The directive text inserted after `{`, without the closing brace
        /// (`start_of_chorus: Chorus 2`, `title: `).
        let body: String
        /// Short forms and other words that find this item (`soc`).
        var aliases: [String] = []

        var id: String {
            body
        }

        /// The directive name (`start_of_chorus`).
        var name: String {
            String(body.prefix { $0 != ":" })
        }

        /// What the list shows beside the title: `{start_of_chorus: Chorus 2}`.
        var detail: String {
            "{\(body)}"
        }

        /// The text inserted after `{` and where the caret goes in it: before the `}` for
        /// a value still to type, after it otherwise.
        var completion: (text: String, caretOffset: Int) {
            let text = body + "}"
            let waitsForValue = body.hasSuffix(": ")
            return (text, text.utf16.count - (waitsForValue ? 1 : 0))
        }
    }

    /// Section kinds offered, in order: ChordPro's own plus the common custom ones.
    static let sectionKinds: [SectionKind] = [
        .verse, .chorus, .bridge, .custom("intro"), .custom("outro"), .tab, .custom("grid"),
    ]

    /// ChordPro short forms by the long directive they abbreviate.
    static let shortForms: [String: [String]] = [
        "start_of_chorus": ["soc"], "end_of_chorus": ["eoc"],
        "start_of_verse": ["sov"], "end_of_verse": ["eov"],
        "start_of_bridge": ["sob"], "end_of_bridge": ["eob"],
        "start_of_tab": ["sot"], "end_of_tab": ["eot"],
        "start_of_grid": ["sog"], "end_of_grid": ["eog"],
        "comment": ["c"], "title": ["t"], "subtitle": ["st"],
    ]

    static let metadata: [Item] = [
        Item(title: "Title", body: "title: "),
        Item(title: "Artist", body: "artist: "),
        Item(title: "Movie / Album", body: "album: "),
        Item(title: "Key", body: "key: "),
        Item(title: "Capo", body: "capo: "),
        Item(title: "Tempo", body: "tempo: "),
        Item(title: "Time signature", body: "time: "),
        Item(title: "Length", body: "duration: "),
    ]

    static let trailing: [Item] = [
        Item(title: "Chorus (repeat)", body: "chorus"),
        Item(title: "Comment", body: "comment: "),
        Item(title: "Subtitle", body: "subtitle: "),
        Item(title: "Chord shape", body: "define: "),
        Item(title: "Meta", body: "meta: "),
    ]

    /// The `start_of_` items of `kind`: labelled with the next number, then plain.
    static func startItems(_ kind: SectionKind, document: SongDocument) -> [Item] {
        let name = SectionLabels.displayName(kind)
        let directive = "start_of_\(kindName(kind))"
        // The numbering rule (P3-11): verses always numbered; the first chorus, bridge,
        // intro or outro unlabelled. Existing sections are not renumbered from here (the
        // slash menu and the section band do that).
        guard let label = SectionLabels.proposal(for: kind, lyrics: nil, in: document).label
        else {
            return [Item(title: name, body: directive)]
        }
        return [
            Item(title: label, body: "\(directive): \(label)"),
            Item(title: "\(name), no label", body: directive),
        ]
    }

    static func endItem(_ kind: SectionKind) -> Item {
        let name = SectionLabels.displayName(kind).lowercased()
        return Item(title: "End of \(name)", body: "end_of_\(kindName(kind))")
    }

    /// Every item, in the default order (without any prefix).
    static func all(document: SongDocument) -> [Item] {
        let starts = sectionKinds.flatMap { startItems($0, document: document) }
        return (metadata + starts + sectionKinds.map(endItem) + trailing).map(withAliases)
    }

    /// Items for `prefix` (what follows the `{`), most relevant first: the open section's
    /// `end_of_`, a matching section word's start items, exact short forms, then directive
    /// names and plain names that start with the prefix.
    static func items(
        prefix: String,
        openSection: String?,
        document: SongDocument,
        limit: Int = 10,
    ) -> [Item] {
        let typed = prefix.lowercased()
        let everything = all(document: document)
        var ordered: [Item] = []
        if let openSection {
            ordered += everything.filter { $0.body == "end_of_\(openSection)" }
        }
        if typed.count >= 2 {
            for kind in sectionKinds where kindName(kind).hasPrefix(typed) {
                ordered += startItems(kind, document: document).map(withAliases)
                if kind == .chorus {
                    ordered += trailing.filter { $0.body == "chorus" }
                }
            }
        }
        ordered += everything.filter { $0.aliases.contains(typed) }
        ordered += everything.filter { item in
            item.name.hasPrefix(typed)
                || item.aliases.contains { $0.hasPrefix(typed) }
                || item.title.lowercased().split(separator: " ").contains { $0.hasPrefix(typed) }
        }
        var seen = Set<String>()
        let unique = ordered.filter { item in
            matches(item, typed) && seen.insert(item.body).inserted
        }
        return Array(unique.prefix(limit))
    }

    private static func matches(_ item: Item, _ typed: String) -> Bool {
        typed.isEmpty || item.name.hasPrefix(typed) || item.aliases.contains { $0.hasPrefix(typed) }
            || item.title.lowercased().split(separator: " ").contains { $0.hasPrefix(typed) }
            || (typed.count >= 2 && item.name.hasPrefix("start_of_")
                && item.name.dropFirst("start_of_".count).hasPrefix(typed))
    }

    private static func withAliases(_ item: Item) -> Item {
        var item = item
        item.aliases = shortForms[item.name] ?? []
        return item
    }

    private static func kindName(_ kind: SectionKind) -> String {
        switch kind {
        case .verse: "verse"
        case .chorus: "chorus"
        case .bridge: "bridge"
        case .tab: "tab"
        case let .custom(name): name
        }
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

/// The Text mode slash menu (R81, spec 16.0.2): `/` at the start of a line opens plain
/// names; a section item wraps the selected lines (or inserts the pair with the caret
/// inside), numbered by `SectionLabels`. Matching is fuzzy over words and aliases.
enum SlashMenu {
    enum Action: Equatable {
        /// Wrap the selection in, or insert, a `start_of_`/`end_of_` pair.
        case section(SectionKind)
        /// `{chorus}`.
        case chorusRepeat
        /// A `{comment: }` with the caret in it: a chart note on the current section (P3-13).
        case note
        /// Writes this metadata directive at the top (replacing one already there) and opens
        /// its value choices: `key`, `tempo`, `duration`, `capo`, `time` (`album` has none).
        case value(String)
    }

    struct Item: Equatable, Identifiable {
        let title: String
        let action: Action
        /// What the list shows beside the title (the directive it writes).
        let detail: String
        let aliases: [String]

        var id: String {
            title
        }

        var isSection: Bool {
            if case .section = action {
                true
            } else {
                false
            }
        }
    }

    static let items: [Item] = [
        Item(
            title: "Verse",
            action: .section(.verse),
            detail: "{start_of_verse}",
            aliases: ["v", "sov", "verse"],
        ),
        Item(
            title: "Chorus",
            action: .section(.chorus),
            detail: "{start_of_chorus}",
            aliases: ["c", "ch", "cho", "soc", "chorus", "refrain"],
        ),
        Item(
            title: "Bridge",
            action: .section(.bridge),
            detail: "{start_of_bridge}",
            aliases: ["b", "br", "sob", "bridge"],
        ),
        Item(
            title: "Intro",
            action: .section(.custom("intro")),
            detail: "{start_of_intro}",
            aliases: ["i", "in", "int", "intro"],
        ),
        Item(
            title: "Outro",
            action: .section(.custom("outro")),
            detail: "{start_of_outro}",
            aliases: ["o", "out", "outro", "ending"],
        ),
        Item(
            title: "Tab",
            action: .section(.tab),
            detail: "{start_of_tab}",
            aliases: ["t", "sot", "tab"],
        ),
        Item(
            title: "Chorus (repeat)",
            action: .chorusRepeat,
            detail: "{chorus}",
            aliases: ["repeat", "rep"],
        ),
        Item(
            title: "Note",
            action: .note,
            detail: "{comment}",
            aliases: ["n", "note", "comment", "cue"],
        ),
        Item(
            title: "Movie / Album…",
            action: .value("album"),
            detail: "{album}",
            aliases: ["movie", "film", "album"],
        ),
        Item(title: "Key…", action: .value("key"), detail: "{key}", aliases: ["k", "key"]),
        Item(
            title: "Tempo…",
            action: .value("tempo"),
            detail: "{tempo}",
            aliases: ["bpm", "tempo"],
        ),
        Item(
            title: "Length…",
            action: .value("duration"),
            detail: "{duration}",
            aliases: ["len", "length", "duration"],
        ),
        Item(title: "Capo…", action: .value("capo"), detail: "{capo}", aliases: ["capo"]),
        Item(
            title: "Time…",
            action: .value("time"),
            detail: "{time}",
            aliases: ["time", "signature"],
        ),
    ]

    /// Items matching `query`, best first: an exact alias, then a title that starts with
    /// the query, then any word or alias that does, then the query's letters in order in
    /// the title. Ties keep the menu order. `sections` says whether section items apply.
    static func matches(_ query: String, sections: SectionAvailability) -> [Item] {
        let typed = query.trimmingCharacters(in: .whitespaces).lowercased()
        let pool = items.filter { item in
            switch sections {
            case .all: true
            case .wrapOnly: item.isSection
            case .noSections: !item.isSection
            }
        }
        guard !typed.isEmpty else { return pool }
        // Rank first, then menu order (pool index) breaks ties.
        let ranked = pool.enumerated().compactMap { index, item -> (key: Int, item: Item)? in
            rank(item, typed).map { (key: $0 * 100 + index, item: item) }
        }
        return ranked.sorted { $0.key < $1.key }.map(\.item)
    }

    enum SectionAvailability {
        case all
        /// A selection is being wrapped: only sections apply.
        case wrapOnly
        /// The caret is inside a section: sections cannot nest.
        case noSections
    }

    private static func rank(_ item: Item, _ typed: String) -> Int? {
        let title = item.title.lowercased()
        let words = title.split(whereSeparator: { !$0.isLetter }).map(String.init)
        if item.aliases.contains(typed) {
            return 0
        }
        if title.hasPrefix(typed) {
            return 1
        }
        if (words + item.aliases).contains(where: { $0.hasPrefix(typed) }) {
            return 2
        }
        return isSubsequence(typed, of: title) ? 3 : nil
    }

    private static func isSubsequence(_ needle: String, of haystack: String) -> Bool {
        var rest = Substring(haystack)
        for character in needle where character != " " {
            guard let found = rest.firstIndex(of: character) else { return false }
            rest = rest[rest.index(after: found)...]
        }
        return true
    }
}

/// Value help after `{key: `, `{time: `, `{capo: `, `{tempo: ` and `{duration: ` (R81): the
/// card's choices as a list (keys with the one heard in the chords first, common time
/// signatures, capo frets), or, for tempo and length, the format as the list's header.
enum ValueSuggestions {
    struct Choice: Equatable {
        let title: String
        var detail: String?
        /// The value written between `: ` and `}`.
        let value: String
    }

    static let names: Set = ["key", "time", "capo", "tempo", "duration"]

    /// The header shown above the choices ("Key", "Tempo: beats per minute, like 96").
    static func header(for name: String) -> String {
        switch name {
        case "key": "Key"
        case "time": "Time signature"
        case "capo": "Capo fret"
        case "tempo": "Tempo: beats per minute, like 96"
        case "duration": "Length: m:ss, like 4:05"
        default: name
        }
    }

    static func choices(for name: String, prefix: String, detected: SongKey?) -> [Choice] {
        let typed = prefix.trimmingCharacters(in: .whitespaces).lowercased()
        switch name {
        case "key":
            return KeyChoices.matching(typed, detected: detected).prefix(10).map { key in
                Choice(
                    title: key.name,
                    detail: key == detected ? "from chords" : nil,
                    value: key.name,
                )
            }
        case "time":
            return (TimeSignatures.common + TimeSignatures.more)
                .filter { typed.isEmpty || $0.hasPrefix(typed) }
                .map { Choice(title: $0, value: $0) }
        case "capo":
            return (1 ... 11).map(String.init)
                .filter { typed.isEmpty || $0.hasPrefix(typed) }
                .map { Choice(title: "Fret \($0)", value: $0) }
        default:
            return []
        }
    }
}
