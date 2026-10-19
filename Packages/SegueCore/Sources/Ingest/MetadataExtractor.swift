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
enum MetadataExtractor {
    // MARK: - Key/value lines (anywhere in the sheet)

    /// The fields of a key/value line, or `nil` unless every part of it is one
    /// (`Key: D   Capo 2 (play in C shapes)`, `Scale: Am | Capo: 3rd fret`).
    static func keyValueFields(_ line: String) -> [MetadataField]? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
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
        if let match = part.wholeMatch(of: /(?i)(key|scale)\s*[:=\-]?\s*(.+)/) {
            let value = String(match.output.2).trimmingCharacters(in: .whitespaces)
            guard SongKey(parsing: value) != nil else { return nil }
            return [.key(value)]
        }
        if let capo = capoFields(part) {
            return capo
        }
        let tempo = /(?i)(?:(?:tempo|bpm)\s*[:=]?\s*)?(\d{2,3})\s*(?:bpm)?/
        if let match = part.wholeMatch(of: tempo),
           part.lowercased().contains("bpm") || part.lowercased().contains("tempo")
        {
            return Int(match.output.1).map { [.tempo($0)] }
        }
        guard let match = part.wholeMatch(of: /([A-Za-z][A-Za-z ]{1,20}?)\s*:\s*(\S.*)/),
              let make = labelledFields[String(match.output.1).lowercased()]
        else { return nil }
        return [make(String(match.output.2).trimmingCharacters(in: .whitespaces))]
    }

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
        (?i) capo \s* [:\-]? \s* (?:on \s+)? (?:fret \s+)? (\d{1,2}) (?:st|nd|rd|th)?
        (?: \s* fret)? \s* (?: \( (.*) \) )?
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
        if let match = text.wholeMatch(of: /(?i)by\s+(.+)/) {
            return [.artist(clean(match.output.1))]
        }
        guard isFirst else { return nil }
        let sitePattern =
            /(?i)(.+?)\s+(?:(?:guitar|ukulele|uke|piano)\s+)?(?:chords|tabs?|lyrics)\s+by\s+(.+)/
        if let match = text.wholeMatch(of: sitePattern) {
            return [.title(clean(match.output.1)), .artist(clean(match.output.2))]
        }
        let chordsPattern = /(?i)(.+?)\s+(?:(?:guitar|ukulele|uke|piano)\s+)?(?:chords|tabs?)/
        if let match = text.wholeMatch(of: chordsPattern) {
            return [.title(clean(match.output.1))]
        }
        if let match = text.wholeMatch(of: /(.+?)\s+[-\u{2013}\u{2014}]\s+(.+)/) {
            return [.title(clean(match.output.1)), .artist(clean(match.output.2))]
        }
        if let match = text.wholeMatch(of: /(.+?)\s+by\s+(.+)/) {
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
