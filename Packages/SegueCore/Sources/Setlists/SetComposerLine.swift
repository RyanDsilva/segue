import Foundation
import MusicTheory

/// One line typed into the set composer (P8-5 section 5): nothing, a break, or a song query
/// with an optional gig key at its end ("kesariya in A", "tum hi ho (Am)", "pal key of D").
///
/// A line holding " + " (space, plus, space) is a medley (P9-3 section 10): each part is a
/// song query with its own optional key ("kesariya in A + tum hi ho + channa mereya (Am)").
/// "C++ Blues" has no spaced plus, so it stays one song.
///
/// Pure grammar only: whether a key token is really a key or part of a title ("Stuck in a
/// Moment") is decided by `SetComposer.resolve`, which sees the library.
public enum SetComposerLine: Sendable, Equatable {
    /// One song of a medley line: its query, key and key token as a song line has them, and
    /// the part's own text (trimmed) for the full-text fallback. An empty part ("a +  + b")
    /// has an empty query.
    public struct SongPart: Sendable, Equatable {
        public var query: String
        public var key: SongKey?
        public var keyToken: String?
        public var text: String

        public init(query: String, key: SongKey? = nil, keyToken: String? = nil, text: String) {
            self.query = query
            self.key = key
            self.keyToken = keyToken
            self.text = text
        }
    }

    case empty
    /// "---": a break row with the automatic label.
    case breakRow
    /// A song query, with the key token split off when one parses (`keyToken` keeps the
    /// raw text, for the full-line fallback in `SetComposer.resolve`).
    case song(query: String, key: SongKey?, keyToken: String?)
    /// Two or more songs joined with " + ": one medley slot (P9-3 section 10).
    case medley([SongPart])

    /// The medley join: a plus with a space on each side.
    public static let medleySeparator = " + "

    /// Parses `text` as typed. The text itself is never rewritten: the query keeps the
    /// user's spelling (only trimmed), so nothing "corrects" romanized Hindi.
    public static func parse(_ text: String) -> Self {
        let line = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if line.isEmpty {
            return .empty
        }
        if isBreak(line) {
            return .breakRow
        }
        // "kesariya in A +" while typing the join: the plus is the next part's, still empty.
        let joined = line.hasSuffix(" +") ? line + " " : line
        let parts = joined.components(separatedBy: medleySeparator)
            .map { $0.trimmingCharacters(in: .whitespaces) }
        if parts.count >= 2 {
            let typed = parts.filter { !$0.isEmpty }
            // "kesariya + " while typing the next part: a list of one song is just a song.
            if typed.count == 1, let only = typed.first {
                return song(only)
            }
            return .medley(parts.map(part))
        }
        return song(line)
    }

    /// A song line (already trimmed): the key token split off when one parses.
    private static func song(_ line: String) -> Self {
        if let split = parenthesizedKey(line) ?? keywordKey(line) {
            return .song(query: split.query, key: split.key, keyToken: split.token)
        }
        return .song(query: line, key: nil, keyToken: nil)
    }

    /// One medley part, parsed like a song line.
    private static func part(_ text: String) -> SongPart {
        if let split = parenthesizedKey(text) ?? keywordKey(text) {
            return SongPart(query: split.query, key: split.key, keyToken: split.token, text: text)
        }
        return SongPart(query: text, text: text)
    }

    /// Only dashes (hyphen 1, en dash U+2013 2, em dash U+2014 3) weighing at least 3:
    /// "---", an en dash plus a hyphen, or one em dash.
    /// A pasted or system-substituted dash still counts, although substitution is off.
    static func isBreak(_ line: String) -> Bool {
        var weight = 0
        for character in line {
            switch character {
            case "-": weight += 1
            case "\u{2013}": weight += 2
            case "\u{2014}": weight += 3
            default: return false
            }
        }
        return weight >= 3
    }

    private struct Split {
        var query: String
        var key: SongKey
        var token: String
    }

    /// `<query> (<key>)`, the parentheses last on the line.
    private static func parenthesizedKey(_ line: String) -> Split? {
        guard line.hasSuffix(")"), let open = line.lastIndex(of: "(") else { return nil }
        let inner = line[line.index(after: open) ..< line.index(before: line.endIndex)]
        let query = line[..<open].trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty, let key = gigKey(String(inner)) else { return nil }
        return Split(query: query, key: key, token: String(line[open...]))
    }

    /// `<query> in <key>`, `<query> key of <key>`, `<query> key <key>`, `<query> key: <key>`;
    /// the key is one word ("F#m") or a note and a mode word ("C minor").
    private static func keywordKey(_ line: String) -> Split? {
        let words = wordRanges(line)
        // The key takes the last one or two words; the keyword sits just before it.
        for keyLength in [1, 2] where words.count > keyLength {
            let keyStart = words.count - keyLength
            let keyText = String(line[words[keyStart].lowerBound ..< line.endIndex])
            guard let key = gigKey(keyText) else { continue }
            let keyword = line[words[keyStart - 1]].lowercased()
            var tokenStart = keyStart - 1
            switch keyword {
            case "in", "key", "key:":
                break
            case "of":
                guard tokenStart >= 1, line[words[tokenStart - 1]].lowercased() == "key" else {
                    continue
                }
                tokenStart -= 1
            default:
                continue
            }
            guard tokenStart >= 1 else { continue }
            let tokenLower = words[tokenStart].lowerBound
            let query = line[..<tokenLower].trimmingCharacters(in: .whitespaces)
            guard !query.isEmpty else { continue }
            return Split(query: query, key: key, token: String(line[tokenLower...]))
        }
        return nil
    }

    /// Ranges of the whitespace-separated words of `line`.
    private static func wordRanges(_ line: String) -> [Range<String.Index>] {
        var ranges: [Range<String.Index>] = []
        var start: String.Index?
        var index = line.startIndex
        while index < line.endIndex {
            if line[index].isWhitespace {
                if let begun = start {
                    ranges.append(begun ..< index)
                    start = nil
                }
            } else if start == nil {
                start = index
            }
            index = line.index(after: index)
        }
        if let begun = start {
            ranges.append(begun ..< line.endIndex)
        }
        return ranges
    }

    /// A gig key as typed: letter A-G (either case), an optional accidental (`#`, `♯`, `b`,
    /// `♭`) and an optional mode (`m`, `M`, `min`, `minor`, `maj`, `major`; the word forms
    /// may follow a space). Parsed by `SongKey(parsing:)` with the letter upper-cased.
    static func gigKey(_ raw: String) -> SongKey? {
        let text = raw.trimmingCharacters(in: .whitespaces)
        guard let first = text.first, "abcdefgABCDEFG".contains(first) else { return nil }
        var rest = Substring(text.dropFirst())
        var accidental = ""
        if let next = rest.first, "#♯b♭".contains(next) {
            accidental = String(next)
            rest = rest.dropFirst()
        }
        let mode = String(rest)
        let attached = ["", "m", "M", "min", "minor", "maj", "major"]
        let spaced = [" min", " minor", " maj", " major"]
        let lowered = mode.lowercased()
        let isMode = attached.contains(mode)
            || ["min", "minor", "maj", "major"].contains(lowered)
            || spaced.contains(lowered.replacing(/^\s+/, with: " "))
        guard isMode else { return nil }
        let normalizedMode = mode.trimmingCharacters(in: .whitespaces)
        let spelled = first.uppercased() + accidental + (normalizedMode.isEmpty ? "" : " ")
            + normalizedMode
        return SongKey(parsing: spelled)
    }
}
