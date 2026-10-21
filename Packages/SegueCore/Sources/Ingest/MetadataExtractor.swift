import Foundation
import MusicTheory

/// One metadata value found in a line.
enum MetadataField: Equatable {
    case title(String)
    case artist(String)
    case composer(String)
    case lyricist(String)
    case album(String)
    /// `Key: G` / `Scale: Am`, as written.
    case key(String)
    case capo(Int)
    /// `(play in C shapes)`: the key of the chords as written.
    case shapesKey(String)
    case tempo(Int)
}

/// Finds title/artist/key/capo/tempo in directives, "Title - Artist" header lines,
/// chord-site credit lines (`Singer: | Music: | Lyrics:`), `Key: G`, `Scale: Am`, `Capo 2`.
/// Chord sites also write the label with a spaced en or em dash (`Capo – 3rd Fret`) or
/// after an emoji (`🎤 Singer: X`); both read like the colon form (R142).
enum MetadataExtractor {
    // MARK: - Key/value lines (anywhere in the sheet)

    /// The fields of a key/value line, or `nil` unless every part of it is one
    /// (`Key: D   Capo 2 (play in C shapes)`, `Scale: Am | Capo: 3rd fret`).
    static func keyValueFields(_ line: String) -> [MetadataField]? {
        let trimmed = withoutSymbolPrefix(line)
        guard !trimmed.isEmpty, trimmed.count <= 120 else { return nil }
        let parts = trimmed
            .split(separator: /\s+\|\s+|\s{2,}|\s*\|\s*/)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        var fields: [MetadataField] = []
        for part in parts {
            guard let partFields = keyValue(part) else { return nil }
            fields += partFields
        }
        return fields.isEmpty ? nil : fields
    }

    private static func keyValue(_ part: String) -> [MetadataField]? {
        let keyPattern = #/
        (?i) (?: original \s+ )? (?: key | scale ) (?: \s* \/ \s* (?: key | scale ) )?
        \s* [:=\-\u{2013}\u{2014}]? \s* (.+)
        /#
        if let match = part.wholeMatch(of: keyPattern) {
            let value = String(match.output.1).trimmingCharacters(in: .whitespaces)
            guard SongKey(parsing: value) != nil else { return nil }
            return [.key(value)]
        }
        if let capo = capoFields(part) {
            return capo
        }
        let tempo = /(?i)(?:(?:tempo|bpm)\s*[:=\u{2013}\u{2014}]?\s*)?(\d{2,3})\s*(?:bpm)?/
        if let match = part.wholeMatch(of: tempo),
           part.lowercased().contains("bpm") || part.lowercased().contains("tempo")
        {
            return Int(match.output.1).map { [.tempo($0)] }
        }
        let labelled = /([A-Za-z][A-Za-z ]{1,20}?)\s*(:|\s[\u{2013}\u{2014}])\s*(\S.*)/
        guard let match = part.wholeMatch(of: labelled),
              let make = labelledFields[String(match.output.1).lowercased()]
        else { return nil }
        let value = String(match.output.3).trimmingCharacters(in: .whitespaces)
        // The dash form is a site heading as often as a credit (`Song – X Chords`), so its
        // value must also be free of site words.
        let isDash = match.output.2 != ":"
        guard isDash ? isPlausibleField(value) : isPlausibleName(value) else { return nil }
        return [make(value)]
    }

    /// `line` trimmed, without the emoji or symbols a chord site puts before a field label
    /// (`🎶 Song: X`). Letters and digits are never removed.
    static func withoutSymbolPrefix(_ line: String) -> String {
        var rest = Substring(line.trimmingCharacters(in: .whitespaces))
        while let first = rest.first, first == " " || isSymbol(first) {
            rest = rest.dropFirst()
        }
        return String(rest)
    }

    private static func isSymbol(_ character: Character) -> Bool {
        !character.isLetter && !character.isNumber && character.unicodeScalars.contains { scalar in
            scalar.properties.isEmojiPresentation || scalar.properties
                .generalCategory == .otherSymbol
        }
    }

    // MARK: - Note lines

    /// A line of site notes that is never a lyric (R142), read as a `{comment}`:
    ///
    /// - a footnote: `*    Some folks prefer G`, `**   Song is in key of F#m`;
    /// - a song-details field after an emoji (`📅 Release Date: 2003`);
    /// - a chord-site field written with a spaced en or em dash (`Strumming – DDU UDU`,
    ///   `Guitar Tuning – Standard`, `Tempo – 4/4`).
    ///
    /// Both field forms need a label whose last word is in `noteLabels`, so a lyric that merely
    /// starts with an emoji or holds a dash is never taken. Fields that carry metadata
    /// (`Capo – 3rd Fret`) are `keyValueFields` lines instead.
    static func isNoteLine(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard !ChordLines.hasInlineChords(trimmed) else { return false }
        if trimmed.wholeMatch(of: /\*{1,4}\s+\S.*/) != nil {
            return true
        }
        let stripped = withoutSymbolPrefix(trimmed)
        let hasPrefix = stripped.count < trimmed.count
        let field = #/
        ( [A-Za-z][A-Za-z\/]* (?: \s [A-Za-z][A-Za-z\/]* ){0,2} )
        \s* ( : | \s [\u{2013}\u{2014}] ) \s* \S .*
        /#
        guard let match = stripped.wholeMatch(of: field) else { return false }
        let label = String(match.output.1)
        let isDash = match.output.2 != ":"
        let words = label.split(whereSeparator: { $0 == " " || $0 == "/" }).map { $0.lowercased() }
        guard hasPrefix || isDash, let last = words.last, noteLabels.contains(last) else {
            return false
        }
        guard isDash else { return true }
        // A dash field's label is a title-case name made of note words only (`Suggested
        // Strumming`, `Guitar Tuning`), never a sentence or a page heading whose song title
        // comes before the word (`X Chords – Y`, `X Lyrics – Y`).
        return label.split(separator: " ").allSatisfy { $0.first?.isUppercase == true }
            && words.allSatisfy { noteLabels.contains($0) || noteModifiers.contains($0) }
    }

    /// Words that may come before a dash field's last word (`Original Chords`).
    private static let noteModifiers: Set = [
        "guitar", "standard", "stander", "original", "orignal", "suggested", "basic", "easy",
        "main", "time", "release",
    ]

    /// Last words of a note label (chord-site song details and playing notes). Misspellings
    /// seen on real sites are included (`Stander Tunning`).
    private static let noteLabels: Set = [
        "song", "singer", "singers", "artist", "album", "movie", "film", "music", "lyrics",
        "lyricist", "composer", "director", "starring", "cast", "label", "genre", "language",
        "year", "date", "released", "duration", "storyline", "capo", "key", "scale", "tuning",
        "tunning", "chords", "chord", "strumming", "pattern", "rhythm", "tempo", "bpm",
        "signature",
    ]

    /// `Label: value` credit lines (chord-site style) and the field each label fills.
    private static let labelledFields: [String: @Sendable (String) -> MetadataField] = {
        var table: [String: @Sendable (String) -> MetadataField] = [:]
        let groups: [([String], @Sendable (String) -> MetadataField)] = [
            (["song", "song name", "song title", "title"], { .title($0) }),
            (
                ["artist", "artists", "band", "performed by", "singer", "singers", "vocals"],
                { .artist($0) },
            ),
            (["composed by", "composer", "music", "music by", "music director"], { .composer($0) }),
            (
                ["lyricist", "lyrics", "lyrics by", "words", "words by", "written by"],
                { .lyricist($0) },
            ),
            (["album", "film", "movie"], { .album($0) }),
        ]
        for (labels, make) in groups {
            for label in labels {
                table[label] = make
            }
        }
        return table
    }()

    /// `Capo 2`, `Capo: 3rd fret`, `Capo on 2`, `Capo 2 (play in C shapes)`.
    private static func capoFields(_ part: String) -> [MetadataField]? {
        let pattern = #/
        (?i) capo \s* [:\-\u{2013}\u{2014}]? \s* (?:on \s+)? (?:fret \s+)?
        (\d{1,2}) (?:st|nd|rd|th)? (?: \s* fret)? \s* (?: \( (.*) \) )?
        /#
        guard let match = part.wholeMatch(of: pattern),
              let fret = Int(match.output.1), (0 ... 12).contains(fret)
        else { return nil }
        var fields: [MetadataField] = [.capo(fret)]
        if let note = match.output.2 {
            guard let shapes = note.firstMatch(of: /([A-G][#b]?m?)\s+(?:shapes?|form)/)
            else { return nil }
            fields.append(.shapesKey(String(shapes.output.1)))
        }
        return fields
    }

    // MARK: - Title lines (top of the sheet only)

    /// Title/artist from a header line: `X Chords by Y`, `X chords`, `X - Y`, `X by Y`,
    /// `X (Y)`, `by Y`, or the line itself as the title.
    static func titleFields(_ line: String, isFirst: Bool) -> [MetadataField]? {
        let text = line.trimmingCharacters(in: .whitespaces)
        guard isPlausibleName(text) else { return nil }
        return rawTitleFields(text, isFirst: isFirst)?.filter { field in
            switch field {
            case let .artist(value), let .title(value): isPlausibleField(value)
            default: true
            }
        }
    }

    private static func rawTitleFields(_ text: String, isFirst: Bool) -> [MetadataField]? {
        if let match = text.wholeMatch(of: /(?i)by\s+(.+)/) {
            return [.artist(clean(match.output.1))]
        }
        guard isFirst else { return nil }
        let sitePattern =
            /(?i)(.+?)\s+(?:(?:guitar|ukulele|uke|piano)\s+)?(?:chords|tabs?|lyrics)\s+by\s+(.+)/
        if let match = text.wholeMatch(of: sitePattern) {
            return [.title(clean(match.output.1)), .artist(clean(match.output.2))]
        }
        if let fields = siteHeading(text) {
            return fields
        }
        if let match = text.wholeMatch(of: /(.+?)\s+[-\u{2013}\u{2014}]\s+(.+)/) {
            return [.title(clean(match.output.1)), .artist(clean(match.output.2))]
        }
        if let match = text.wholeMatch(of: /(.+?)\s+by\s+(.+)/) {
            return [.title(clean(match.output.1)), .artist(clean(match.output.2))]
        }
        // `Brown Eyed Girl  Van Morrison`: two name-like parts two or more spaces apart.
        if let match = text.wholeMatch(of: /(.+?)\s{2,}(.+)/),
           isNameLike(String(match.output.1)), isNameLike(String(match.output.2))
        {
            return [.title(clean(match.output.1)), .artist(clean(match.output.2))]
        }
        if let match = text.wholeMatch(of: /(.+?)\s*\(([^()]+)\)/),
           isNameLike(String(match.output.2))
        {
            return [.title(clean(match.output.1)), .artist(clean(match.output.2))]
        }
        guard text.split(separator: " ").count <= 10, !text.contains(":") else { return nil }
        return [.title(text)]
    }

    /// A chord site's page heading: `X Chords`, `X Guitar Chords - Y`, `X Chords by Y With
    /// Strumming Pattern`, `X Chords Guitar Piano and Lyrics | Film`, `X Chords - Film | Singer`.
    /// The title is the text before the word; the artist is what follows `by` or a dash, cut
    /// at "with", and after a `|` its last part (`Film | Singer`).
    private static func siteHeading(_ text: String) -> [MetadataField]? {
        let pattern = /(?i)(.+?)\s+(?:(?:guitar|ukulele|uke|piano)\s+)?(?:chords|tabs?)\b(.*)/
        guard let match = text.wholeMatch(of: pattern) else { return nil }
        let rest = String(match.output.2)
        // Only a heading: nothing after the word, or a byline, a dash, or more site words
        // (not a sentence such as "For chords in the original key, transpose...").
        let heading = #/
        (?i) \s* (?: (?: by|guitar|piano|ukulele|and|lyrics|with|easy ) \b
        | [-\u{2013}\u{2014}:|(] ) .*
        /#
        guard rest.trimmingCharacters(in: .whitespaces).isEmpty || rest
            .wholeMatch(of: heading) != nil
        else { return nil }
        var fields: [MetadataField] = [.title(clean(match.output.1))]
        if let tail = rest.wholeMatch(of: /(?i)\s*(?:by\b|[-\u{2013}\u{2014}:])\s*(.+)/) {
            var artist = String(tail.output.1)
            if let cut = artist.firstMatch(of: /(?i)\s+with\s+/) {
                artist = String(artist[..<cut.range.lowerBound])
            }
            // `Film | Singer`: the last part that could be a name.
            artist = artist.split(separator: "|").map { clean($0) }.last { part in
                isPlausibleField(part)
            } ?? ""
            artist = clean(artist)
            if !artist.isEmpty, isPlausibleName(artist) {
                fields.append(.artist(artist))
            }
        }
        return fields
    }

    /// False for text that is never a title or artist: chord symbols only, a chord-shape
    /// legend (`G 3-5-5-4-3-3`), a tuning (`E-A-D-G-B-e`), tab, a capo/key/tuning note, or a
    /// site note (`Strumming Pattern – DD UU`, whose dash is not "Title - Artist").
    static func isPlausibleName(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return false }
        let tokens = ChordLines.tokens(trimmed).map(\.text)
        let chordsOnly = tokens.allSatisfy { token in
            ChordLines.kind(of: token) != .unknown
        }
        let note = trimmed.firstMatch(of: /(?i)\b(?:capo|tuning|fret)\b/) != nil
            // Ultimate Guitar's placeholder artist for film songs.
            || trimmed.lowercased().hasPrefix("misc ")
        return !chordsOnly && !note && !isSiteName(trimmed) && !ChordLines
            .hasInlineChords(trimmed) && !ChordLines.isChordLine(trimmed)
            && !ChordLines.isChordLegend(trimmed) && !ChordLines.isTuningLine(trimmed)
            && !ChordLines.isTabLine(trimmed) && keyValueFields(trimmed) == nil
            && !isNoteLine(trimmed)
    }

    /// A title or artist value (not a whole line): plausible, and no site words such as
    /// "Easy Guitar Chords" or "Strumming Pattern".
    static func isPlausibleField(_ value: String) -> Bool {
        isPlausibleName(value)
            && value.firstMatch(of: /(?i)\b(?:chords?|tabs?|lyrics|strumming)\b/) == nil
    }

    /// A web address or a chord site's name (`youtube.com/watch?v=...`, `www.x.in`,
    /// `guitarchordslyrics`, `Chordsguru.com`): never a title, artist or credit.
    static func isSiteName(_ text: String) -> Bool {
        let lowered = text.lowercased()
        if lowered.contains("http") || lowered.contains("www.") || lowered.contains("youtu") {
            return true
        }
        if lowered.firstMatch(of: /[a-z0-9-]+\.(?:com|in|net|org|co|io|info|me)\b/) != nil {
            return true
        }
        // One run-together word holding "chord", "lyric" or "tab" (a site's name).
        return lowered.split(separator: " ").contains { word in
            word.count > 8 && ["chord", "lyric", "tabs"].contains { word.contains($0) }
                && word != "chords" && word != "lyrics"
        }
    }

    /// A short capitalised name line right under the title (`Penny Marlowe`).
    static func isNameLike(_ text: String) -> Bool {
        let words = text.split(separator: " ")
        guard (1 ... 5).contains(words.count),
              let first = text.first, first.isUppercase,
              !text.contains(where: { $0.isNumber || $0 == ":" || $0 == "|" })
        else { return false }
        let lowered = Set(words.map { $0.lowercased() })
        return lowered.isDisjoint(with: notNames)
    }

    private static func clean(_ text: some StringProtocol) -> String {
        text
            .trimmingCharacters(in: .whitespaces
                .union(CharacterSet(charactersIn: ",;:-|\"'\u{201C}\u{201D}\u{2018}\u{2019}")))
    }

    /// Words that make a line a note, not a name.
    private static let notNames: Set = [
        "tuning", "standard", "capo", "key", "intro", "chords", "chord", "strumming", "tab",
        "version", "live", "acoustic", "remix", "cover", "official", "lyrics", "easy",
        "difficulty", "tempo", "bpm",
    ]
}
