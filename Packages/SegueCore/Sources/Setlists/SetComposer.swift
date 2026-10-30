import Foundation
import Library
import MusicTheory

/// What a set composer line means against the library (P8-5 section 6.6): the view only
/// renders this.
public struct SetComposerResolution: Sendable, Equatable {
    public enum Kind: Sendable, Equatable {
        /// Nothing to add: a blank line, or only punctuation.
        case empty
        /// "---": a break row.
        case breakRow
        /// A song query; `matches` may be empty ("No song matches").
        case song
    }

    public var kind: Kind
    /// Ranked best first, at most five.
    public var matches: [SongMatch]
    /// The gig key to apply, when a key token was split off and kept as a key.
    public var key: SongKey?
    /// The text that was matched: the query without the key token, or the whole line.
    public var query: String

    public init(kind: Kind, matches: [SongMatch] = [], key: SongKey? = nil, query: String = "") {
        self.kind = kind
        self.matches = matches
        self.key = key
        self.query = query
    }

    public static let empty = Self(kind: .empty)
}

/// The set composer's pure decisions: which songs a line names and how the ghost reads.
public enum SetComposer {
    /// How many alternatives the composer offers.
    public static let alternativeLimit = 5

    /// Resolves `line` (parsed from `rawText`) against `matcher`.
    ///
    /// A key token ("in A") is kept as a key unless the whole line names a song strongly
    /// and at least as well as the line without it: "stuck in a" finds "Stuck in a Moment"
    /// with no key, "kesariya in a" finds Kesariya in A.
    public static func resolve(
        _ line: SetComposerLine,
        rawText: String,
        matcher: SongMatcher,
    ) -> SetComposerResolution {
        switch line {
        case .empty:
            return .empty
        case .breakRow:
            return SetComposerResolution(kind: .breakRow)
        case let .song(query, key, _):
            guard !RomanNormalizer.words(query).isEmpty else { return .empty }
            let stripped = matcher.bestMatches(for: query, limit: alternativeLimit)
            guard let key else {
                return SetComposerResolution(kind: .song, matches: stripped, query: query)
            }
            let fullLine = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
            let full = matcher.bestMatches(for: fullLine, limit: alternativeLimit)
            if let best = full.first, best.band == .strong,
               best.score >= stripped.first?.score ?? Int.min
            {
                return SetComposerResolution(kind: .song, matches: full, query: fullLine)
            }
            return SetComposerResolution(kind: .song, matches: stripped, key: key, query: query)
        }
    }

    /// The rest of `title` after `typed`, when `title` starts with what was typed (compared
    /// word by word after `RomanNormalizer.words` folding, so case, diacritics and
    /// apostrophes do not matter): "Kesa" + "Kesariya" -> "riya". Nil when the title does
    /// not start with the typed text or nothing is left. The typed text is never changed.
    public static func ghostSuffix(typed: String, title: String) -> String? {
        let typedWords = RomanNormalizer.words(typed)
        guard !typedWords.isEmpty else { return nil }
        let titleWords = foldedWords(title)
        guard typedWords.count <= titleWords.count else { return nil }
        for (index, word) in typedWords.enumerated() {
            let folded = titleWords[index].letters
            let isLast = index == typedWords.count - 1
            guard isLast ? folded.starts(with: word) : folded == Array(word) else { return nil }
        }
        let last = titleWords[typedWords.count - 1]
        let consumed = typedWords[typedWords.count - 1].count
        let cut = consumed < last.ends.count ? last.ends[consumed - 1] : last.end
        var rest = Substring(title[cut...])
        if typed.last?.isWhitespace == true, consumed == last.letters.count {
            rest = rest.drop { $0.isWhitespace }
        } else if typed.last?.isWhitespace == true {
            return nil
        }
        return rest.isEmpty ? nil : String(rest)
    }

    /// A title word as `RomanNormalizer.words` folds it, with where each folded letter ends
    /// in the original title.
    private struct FoldedWord {
        var letters: [Character] = []
        var ends: [String.Index] = []
        var end: String.Index
    }

    private static func foldedWords(_ title: String) -> [FoldedWord] {
        var result: [FoldedWord] = []
        var current: FoldedWord?
        var index = title.startIndex
        while index < title.endIndex {
            let next = title.index(after: index)
            let folded = String(title[index])
                .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
                .lowercased()
            let letters = folded.filter { $0.isLetter || $0.isNumber }
            if !letters.isEmpty, letters.count == folded.count {
                var word = current ?? FoldedWord(end: next)
                for letter in letters {
                    word.letters.append(letter)
                    word.ends.append(next)
                }
                word.end = next
                current = word
            } else if ["'", "\u{2019}", "`"].contains(title[index]), current != nil {
                current?.end = next
            } else if let word = current {
                result.append(word)
                current = nil
            }
            index = next
        }
        if let word = current {
            result.append(word)
        }
        return result
    }
}
