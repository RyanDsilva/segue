// The lexicon's tokenizer and working state (P3-7).

import Foundation
import Library

// MARK: - Tokens

/// One word of a request: as typed, and lowercased with apostrophes and diacritics removed.
struct Token: Sendable, Hashable {
    var text: String
    var word: String
    /// `word` through `RomanNormalizer.normalizeWord` (phrases compare on it).
    var folded: String

    init(text: String, word: String) {
        self.text = text
        self.word = word
        folded = RomanNormalizer.normalizeWord(word)
    }

    var isComma: Bool {
        word == ","
    }

    /// Splits on whitespace and punctuation. Kept inside a token: `#`, `♯`, `♭`, `+`, and `.`
    /// `:` `-` between digits ("1.5", "100-130"). Apostrophes vanish ("I'm" -> "im"). Commas
    /// become tokens (they end tag and key lists).
    static func split(_ text: String) -> [Self] {
        var tokens: [Self] = []
        var current = ""
        let characters = Array(text)
        func flush() {
            if !current.isEmpty {
                let word = current.folding(
                    options: [.caseInsensitive, .diacriticInsensitive],
                    locale: nil,
                ).lowercased()
                tokens.append(Self(text: current, word: word))
                current = ""
            }
        }
        for (index, character) in characters.enumerated() {
            if character.isLetter || character.isNumber || "#♯♭+".contains(character) {
                current.append(character)
            } else if "'’`".contains(character) {
                continue
            } else if ".:-".contains(character),
                      current.last?.isNumber == true,
                      index + 1 < characters.count, characters[index + 1].isNumber
            {
                current.append(character == ":" ? ":" : character)
            } else {
                flush()
                if character == "," || character == ";" {
                    tokens.append(Self(text: ",", word: ","))
                }
            }
        }
        flush()
        return tokens
    }
}

/// The lexicon's working state: tokens, which ones a chip claimed, and the chips by position.
struct Scan {
    var tokens: [Token]
    var used: [Bool]
    private var found: [(position: Int, chip: SetChip)] = []

    init(tokens: [Token]) {
        self.tokens = tokens
        used = Array(repeating: false, count: tokens.count)
    }

    func word(at index: Int) -> String? {
        tokens.indices.contains(index) && !used[index] ? tokens[index].word : nil
    }

    /// Marks `range` used and records `chip` at its start.
    mutating func claim(_ range: Range<Int>, _ chip: SetChip) {
        for index in range where tokens.indices.contains(index) {
            used[index] = true
        }
        found.append((range.lowerBound, chip))
    }

    /// The first unused run of tokens whose folded forms equal `words` (already folded),
    /// starting at or after `from`.
    func find(_ words: [String], from: Int) -> Int? {
        guard !words.isEmpty, tokens.count >= words.count else { return nil }
        var start = from
        while start + words.count <= tokens.count {
            let range = start ..< start + words.count
            if !range.contains(where: { used[$0] }),
               zip(range, words).allSatisfy({ tokens[$0.0].folded == $0.1 })
            {
                return start
            }
            start += 1
        }
        return nil
    }

    /// Chips in request order; a later chip of the same slot replaces an earlier one.
    func orderedChips() -> [SetChip] {
        var chips: [SetChip] = []
        for (_, chip) in found.sorted(by: { $0.position < $1.position }) {
            if let index = chips.firstIndex(where: { $0.slot == chip.slot }) {
                chips[index] = chip
            } else {
                chips.append(chip)
            }
        }
        return chips
    }

    /// Unused words, as typed (filler included).
    func remainder() -> [String] {
        tokens.indices.compactMap { index in
            used[index] || tokens[index].isComma ? nil : tokens[index].text
        }
    }

    /// Unused words that carry meaning, as typed.
    func leftover() -> [String] {
        tokens.indices.compactMap { index in
            let token = tokens[index]
            guard !used[index], !token.isComma, !Self.fillers.contains(token.word) else {
                return nil
            }
            return token.text
        }
    }

    /// Words that never carry a request on their own (English and Hinglish filler).
    static let fillers: Set = [
        "a", "an", "the", "of", "for", "me", "give", "some", "set", "sets", "song", "songs",
        "tune", "tunes", "track", "tracks", "gig", "mostly", "mainly", "please", "i", "im", "my",
        "that", "and", "or", "with", "to", "in", "on", "at", "it", "is", "are", "be", "just",
        "stuff", "things", "ones", "one", "something", "anything", "everything", "list", "make",
        "build", "want", "need", "like", "would", "could", "can", "should", "get", "let", "lets",
        "us", "we", "our", "you", "your", "all", "any", "only", "also", "too", "very", "really",
        "bit", "few", "lot", "lots", "from", "into", "this", "these", "those", "them", "they",
        "play", "playing", "music", "kind", "type", "plus", "but", "so", "then", "than", "about",
        "around", "numbers", "kuch", "gaane", "gane", "gaana", "gana", "geet", "wale", "wali",
        "waale", "waali", "wala", "ke", "ki", "ka", "aur", "se", "mein", "hai", "hain", "chahiye",
        "sab", "bhi", "do", "minute", "minutes", "min", "mins", "long", "total", "pls", "thanks",
        "hey", "ok", "okay", "setlist",
    ]
}
