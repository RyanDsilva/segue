import Foundation

// P8-8 section 3.1 (R172, R173): a song's artists as one ordered list, one `{artist}` each.
// Pure. The matching forms (`ArtistNames.forms`) live in Library beside `RomanNormalizer`.

/// The display join and the deterministic split of a combined artist value.
public enum ArtistNames {
    /// "A, B": the one display join of a song's artists (trimmed, blanks dropped); nil when
    /// there are none.
    public static func display(_ artists: [String]) -> String? {
        let names = artists
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        return names.isEmpty ? nil : names.joined(separator: ", ")
    }

    /// R172 / R173's split of one combined value, for pasted credit lines and headers (and
    /// the explicit Split button) only, never stored files. Separators: ",", "&", and the
    /// whole words "feat.", "ft." (the dot required) and "featuring", case-insensitive, plus
    /// a `(feat. X)` parenthesis whose brackets are dropped. Never "and", "x", "with", "/"
    /// or "-". Parts keep the source's exact spelling; a part equal to an earlier one
    /// ignoring case and diacritics is dropped.
    public static func split(_ value: String) -> ArtistSplit {
        let chars = Array(unbracketFeaturing(value))
        var separators: Set<ArtistSeparator> = []
        var parts: [String] = []
        var seen: Set<String> = []
        var current = ""
        func take() {
            let part = current.trimmingCharacters(in: .whitespacesAndNewlines)
            current = ""
            guard !part.isEmpty else { return }
            let key = part.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            if seen.insert(key).inserted {
                parts.append(part)
            }
        }
        var index = 0
        while index < chars.count {
            if let (kind, length) = separator(in: chars, at: index) {
                take()
                separators.insert(kind)
                index += length
            } else {
                current.append(chars[index])
                index += 1
            }
        }
        take()
        if parts.count < 2 {
            separators = []
        }
        return ArtistSplit(original: value, parts: parts, separators: separators)
    }

    /// Cleans one typed or written artist value for a `{artist: X}` line: no "}" and no line
    /// breaks, trimmed; nil when nothing is left.
    public static func cleaned(_ value: String) -> String? {
        let flat = value
            .replacingOccurrences(of: "}", with: "")
            .replacingOccurrences(of: "\r\n", with: " ")
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\r", with: " ")
            .trimmingCharacters(in: .whitespaces)
        return flat.isEmpty ? nil : flat
    }

    // MARK: - Internals

    private static let featuringWords = ["feat.", "ft.", "featuring"]

    /// The separator starting at `index` and its length in characters, if any: ",", "&",
    /// or a whole-word featuring word.
    private static func separator(
        in chars: [Character],
        at index: Int,
    ) -> (ArtistSeparator, Int)? {
        switch chars[index] {
        case ",": return (.comma, 1)
        case "&": return (.ampersand, 1)
        default: break
        }
        guard let length = featuringWord(in: chars, at: index) else { return nil }
        return (.feat, length)
    }

    /// The length of a whole-word "feat." / "ft." / "featuring" at `index`, else nil.
    private static func featuringWord(in chars: [Character], at index: Int) -> Int? {
        if index > 0, isWordCharacter(chars[index - 1]) {
            return nil
        }
        for word in featuringWords {
            let end = index + word.count
            guard end <= chars.count,
                  String(chars[index ..< end]).lowercased() == word
            else { continue }
            // "feat." and "ft." end on their dot; "featuring" must end the word.
            if word.hasSuffix(".") || end == chars.count || !isWordCharacter(chars[end]) {
                return word.count
            }
        }
        return nil
    }

    private static func isWordCharacter(_ char: Character) -> Bool {
        char.isLetter || char.isNumber
    }

    /// The value with the brackets of each `(feat. X)` parenthesis dropped (its featuring
    /// word then splits like any other).
    private static func unbracketFeaturing(_ value: String) -> String {
        let chars = Array(value)
        var result: [Character] = []
        var dropClosing = 0
        var index = 0
        while index < chars.count {
            let char = chars[index]
            if char == "(" {
                var next = index + 1
                while next < chars.count, chars[next].isWhitespace {
                    next += 1
                }
                if next < chars.count, featuringWord(in: chars, at: next) != nil {
                    dropClosing += 1
                    result.append(" ")
                    index = next
                    continue
                }
            } else if char == ")", dropClosing > 0 {
                dropClosing -= 1
                index += 1
                continue
            }
            result.append(char)
            index += 1
        }
        return String(result)
    }
}

/// One combined value and the parts R172's split made of it.
public struct ArtistSplit: Sendable, Hashable {
    /// Exactly as read.
    public var original: String
    /// In order, each in the source's spelling; one element when nothing split.
    public var parts: [String]
    /// The separators that split it; empty when it did not split.
    public var separators: Set<ArtistSeparator>

    public init(original: String, parts: [String], separators: Set<ArtistSeparator>) {
        self.original = original
        self.parts = parts
        self.separators = separators
    }

    /// True when the value became two or more artists.
    public var didSplit: Bool {
        parts.count > 1
    }
}

/// Which separator split a value ("feat" covers "feat.", "ft." and "featuring").
public enum ArtistSeparator: String, Sendable, CaseIterable {
    case comma
    case ampersand
    case feat
}
