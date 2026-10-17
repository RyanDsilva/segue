import Foundation

/// Deterministic spelling normalization for romanized Hindi (and English) search.
///
/// Romanized Hindi has no fixed spelling ("pyaar/pyar", "hai/hain", "kabhi/kabhie"), so the
/// index stores a normalized form of title, artist, first line and lyrics next to the
/// originals, and the same function runs on the query. Original text is never modified;
/// normalization exists only in the index.
///
/// Every rule lives in `rules`, applied in order to each word after `words(_:)` has lowercased
/// it, folded diacritics and stripped punctuation. Changing the table must bump `version`,
/// which changes the index version and triggers a drop-and-rebuild.
public enum RomanNormalizer {
    /// Bump on any change to `rules` or `words(_:)`.
    public static let version = 1

    /// One rewrite applied to a single lowercased word.
    public enum Rule: Sendable, Equatable {
        /// Replace every occurrence of a substring, left to right.
        case replace(String, with: String)
        /// Collapse every run of the same letter into one (`dill` -> `dil`, `accha` -> `acha`).
        case collapseDoubledLetters
        /// Drop an `h` that follows one of these consonants (aspiration only: `bh` -> `b`).
        case dropH(after: Set<Character>)
        /// Rewrite a word ending, only for words at least `minLength` long.
        case replaceSuffix(String, with: String, minLength: Int)
        /// Drop a word-final `n` that follows one of these vowels, only for words at least
        /// `minLength` long (nasalized long endings: `hain` -> `hai`, `nahin` -> `nahi`).
        case dropFinalN(after: Set<Character>, minLength: Int)
    }

    /// The rule table, applied in order.
    ///
    /// Vowel folding runs before collapsing doubles so `ee` folds to `i` (`deewana` ->
    /// `diwana`) rather than collapsing to `e`. A word-final `n` counts as a nasalized long
    /// vowel ending after `i` or `u` (`hain`, `mein`, `main`, `nahin`, `kyun`); after a lone
    /// `a` it is kept so `jaan`/`jan` stay distinct from `ja`.
    public static let rules: [Rule] = [
        // Vowel length folding.
        .replace("aa", with: "a"),
        .replace("ee", with: "i"),
        .replace("ii", with: "i"),
        .replace("oo", with: "u"),
        .replace("uu", with: "u"),
        // Interchangeable consonant spellings.
        .replace("w", with: "v"),
        .replace("z", with: "j"),
        .replace("q", with: "k"),
        // Doubled letters (`pyaar`, `dill`, `accha`, `chh` -> `ch`).
        .collapseDoubledLetters,
        // Aspiration marks: bh kh dh th ph gh jh -> b k d t p g j.
        .dropH(after: ["b", "k", "d", "t", "p", "g", "j"]),
        // `kabhie` -> `kabi` (same as `kabhi`).
        .replaceSuffix("ie", with: "i", minLength: 3),
        // `hain` -> `hai`, `mein` -> `mei`, `nahin` -> `nahi`, `kyun` -> `kyu`.
        .dropFinalN(after: ["i", "u"], minLength: 4),
    ]

    /// `text` normalized word by word, words joined by single spaces.
    public static func normalize(_ text: String) -> String {
        words(text).map(normalizeWord).joined(separator: " ")
    }

    /// One already-tokenized word (as returned by `words(_:)`) run through `rules`.
    public static func normalizeWord(_ word: String) -> String {
        var current = word
        for rule in rules {
            current = apply(rule, to: current)
        }
        return current
    }

    /// Lowercased words of `text` with diacritics folded. Apostrophes are removed inside a
    /// word (`don't` -> `dont`); any other non-letter, non-digit character separates words.
    public static func words(_ text: String) -> [String] {
        let folded = text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            .lowercased()
        var result: [String] = []
        var current = ""
        for character in folded {
            if character.isLetter || character.isNumber {
                current.append(character)
            } else if apostrophes.contains(character) {
                continue
            } else if !current.isEmpty {
                result.append(current)
                current = ""
            }
        }
        if !current.isEmpty {
            result.append(current)
        }
        return result
    }

    private static let apostrophes: Set<Character> = ["'", "\u{2019}", "`"]

    private static func apply(_ rule: Rule, to word: String) -> String {
        switch rule {
        case .collapseDoubledLetters:
            var out = ""
            for character in word where character != out.last || !character.isLetter {
                out.append(character)
            }
            return out
        case let .dropFinalN(vowels, minLength):
            guard word.count >= minLength, word.hasSuffix("n") else { return word }
            let beforeN = word.dropLast()
            guard let vowel = beforeN.last, vowels.contains(vowel) else { return word }
            return String(beforeN)
        case let .dropH(consonants):
            var out = ""
            for character in word {
                if character == "h", let previous = out.last, consonants.contains(previous) {
                    continue
                }
                out.append(character)
            }
            return out
        case let .replace(target, replacement):
            return word.replacingOccurrences(of: target, with: replacement)
        case let .replaceSuffix(suffix, replacement, minLength):
            guard word.count >= minLength, word.hasSuffix(suffix) else { return word }
            return String(word.dropLast(suffix.count)) + replacement
        }
    }
}

extension RomanNormalizer {
    /// Levenshtein distance between two words, giving up early once it exceeds `limit`.
    static func editDistance(_ lhs: String, _ rhs: String, limit: Int) -> Int {
        let left = Array(lhs)
        let right = Array(rhs)
        if abs(left.count - right.count) > limit {
            return limit + 1
        }
        var previous = Array(0 ... right.count)
        for (row, leftChar) in left.enumerated() {
            var current = [row + 1] + Array(repeating: 0, count: right.count)
            var rowMinimum = current[0]
            for (column, rightChar) in right.enumerated() {
                let substitution = previous[column] + (leftChar == rightChar ? 0 : 1)
                current[column + 1] = min(
                    previous[column + 1] + 1,
                    current[column] + 1,
                    substitution,
                )
                rowMinimum = min(rowMinimum, current[column + 1])
            }
            if rowMinimum > limit {
                return limit + 1
            }
            previous = current
        }
        return previous[right.count]
    }
}
