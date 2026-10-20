// Phase 3 P3-7 (spec section 7 step 1, R65, R92): the instant code lexicon. It reads numbers,
// durations, song counts, BPM ranges, keys, proficiency phrases, slot phrases (only when the
// request says them), the library's own tag names and smart filter names (fold- and
// romanization-tolerant through `RomanNormalizer`), and reports the words it could not map,
// which the async model pass may turn into suggested chips. Spike section 4: code parses the
// numbers and keys; a model only maps fuzzy words.

import Foundation
import Library
import MusicTheory

/// A smart filter the lexicon can name ("from Wedding set").
public struct SmartFilterName: Sendable, Hashable {
    public var id: SmartFilterID
    public var name: String

    public init(id: SmartFilterID, name: String) {
        self.id = id
        self.name = name
    }
}

/// What the lexicon read: chips in the order the request states them, and the words left.
public struct LexiconResult: Sendable, Hashable {
    public var chips: [SetChip]
    /// Meaningful words the lexicon could not map, as typed, in order (filler words left out).
    public var leftover: [String]

    public init(chips: [SetChip] = [], leftover: [String] = []) {
        self.chips = chips
        self.leftover = leftover
    }

    /// The leftover words joined by spaces (the model pass's input).
    public var leftoverText: String {
        leftover.joined(separator: " ")
    }
}

/// The instant request parser (spec section 7 step 1). Pure and fast: build one per library
/// vocabulary and call `parse` on every keystroke.
public struct SetRequestLexicon: Sendable {
    /// Slot phrases map to the first of these tags the library has (R92: only when asked).
    public static let strongOpenerTags = ["upbeat"]
    public static let softSlotTags = ["ballad", "acoustic"]
    public static let bigCloserTags = ["crowd pleaser", "singalong"]

    private let tagsByKey: [String: String]
    private let filtersByKey: [String: SmartFilterName]
    private let longestName: Int

    /// - Parameters:
    ///   - tags: the tags in use in the library, as spelled there.
    ///   - smartFilters: the library's saved smart filters.
    public init(tags: [String], smartFilters: [SmartFilterName] = []) {
        var tagsByKey: [String: String] = [:]
        var longest = 1
        for tag in tags {
            let words = Self.nameWords(tag)
            guard !words.isEmpty else { continue }
            longest = max(longest, words.count)
            for key in Self.keys(words) where tagsByKey[key] == nil {
                tagsByKey[key] = tag
            }
        }
        var filtersByKey: [String: SmartFilterName] = [:]
        for filter in smartFilters {
            let words = Self.nameWords(filter.name)
            guard !words.isEmpty else { continue }
            longest = max(longest, words.count)
            for key in Self.keys(words) where filtersByKey[key] == nil {
                filtersByKey[key] = filter
            }
        }
        self.tagsByKey = tagsByKey
        self.filtersByKey = filtersByKey
        longestName = longest
    }

    /// The library tag a phrase names ("Crowd Pleasers" -> "crowd pleaser"), if any.
    public func tag(named phrase: String) -> String? {
        let words = Self.nameWords(phrase)
        return Self.keys(words).lazy.compactMap { tagsByKey[$0] }.first
    }

    /// Reads `text`.
    public func parse(_ text: String) -> LexiconResult {
        var scan = Scan(tokens: Token.split(text))
        scan.readTempo()
        scan.readLengths()
        scan.readCounts()
        readPhrases(&scan)
        readSlotWithTag(&scan)
        scan.readKeys()
        readNames(&scan)
        return LexiconResult(chips: scan.orderedChips(), leftover: scan.leftover())
    }

    // MARK: - Phrases

    private enum PhraseMeaning {
        case proficiency(ProficiencyRequirement)
        case avoidRecent(Bool)
        case opener([String])
        case closer([String])
    }

    private static let phrases: [([String], PhraseMeaning)] = {
        var table: [([String], PhraseMeaning)] = []
        func add(_ meaning: PhraseMeaning, _ phrases: [String]) {
            for phrase in phrases {
                let words = phrase.split(separator: " ")
                    .map { RomanNormalizer.normalizeWord(String($0)) }
                table.append((words, meaning))
            }
        }
        add(.proficiency(.pro), [
            "songs i know cold", "i know cold", "i know them cold", "songs i know by heart",
            "know cold", "know them cold", "know it cold", "know by heart", "know them by heart",
            "know inside out", "know them inside out", "pro only", "only pro", "pro songs",
            "pro level",
        ])
        add(.proficiency(.ready), [
            "songs i know well", "i know well", "i know them well", "songs i know really well",
            "i know really well", "know well", "know them well", "know it well", "know really well",
            "know very well",
            "know pretty well", "songs i know", "i know", "can play", "i can play",
            "nothing im still learning", "nothing i am still learning", "nothing still learning",
            "nothing im learning", "no learning", "not learning", "nothing below ready",
            "ready or better", "ready and up", "ready and above", "ready only", "only ready",
            "ready songs", "ready", "ache se", "ache se ate", "ati hai",
        ])
        add(.proficiency(.anything), [
            "including learning", "include learning", "even learning", "learning too",
            "learning ones too", "any proficiency", "including ones im learning",
            "even ones im learning",
        ])
        add(.avoidRecent(true), [
            "nothing recent", "not recent", "avoid recent", "no recent", "nothing played recently",
            "nothing i played recently", "not played recently", "havent played recently",
            "havent played lately", "not played lately", "nothing played lately", "fresh ones",
            "something fresh", "keep it fresh",
        ])
        add(.avoidRecent(false), [
            "recent ok", "recent is fine", "recent are fine", "repeats ok", "repeats are fine",
            "even recent", "including recent", "even recent ones", "include recent",
        ])
        add(.opener(strongOpenerTags), [
            "upbeat start", "start upbeat", "start strong", "strong start", "open strong",
            "strong opener", "start big", "big start", "open big", "start high", "kick off strong",
            "start with a bang", "open with a bang",
        ])
        add(.opener(softSlotTags), [
            "start soft", "soft start", "start slow", "slow start", "open soft", "start gentle",
            "gentle start", "start mellow", "start quiet", "ease in",
        ])
        add(.closer(bigCloserTags), [
            "finish big", "end big", "big finish", "big closer", "close big", "close strong",
            "finish strong", "end strong", "strong finish", "end on a high", "finish on a high",
            "end high", "go out big",
        ])
        add(.closer(softSlotTags), [
            "end soft", "finish soft", "close soft", "end quiet", "finish quiet", "wind down",
            "end slow", "finish slow",
        ])
        // Longest first, so "nothing im still learning" wins over "still learning".
        return table.sorted { $0.0.count > $1.0.count }
    }()

    private func readPhrases(_ scan: inout Scan) {
        for (words, meaning) in Self.phrases {
            var start = 0
            while let at = scan.find(words, from: start) {
                start = at + words.count
                switch meaning {
                case let .proficiency(level):
                    scan.claim(at ..< at + words.count, .proficiency(level))
                case let .avoidRecent(on):
                    scan.claim(at ..< at + words.count, .avoidRecent(on))
                case let .opener(candidates):
                    if let tag = candidates.lazy.compactMap(tag(named:)).first {
                        scan.claim(at ..< at + words.count, .opener(tag: tag))
                    }
                case let .closer(candidates):
                    if let tag = candidates.lazy.compactMap(tag(named:)).first {
                        scan.claim(at ..< at + words.count, .closer(tag: tag))
                    }
                }
            }
        }
    }

    // MARK: - "start with a ballad", "end with a crowd pleaser"

    private static let openerVerbs: Set = ["start", "open", "opening", "starting", "kick"]
    private static let closerVerbs: Set = [
        "end",
        "finish",
        "close",
        "closing",
        "ending",
        "finishing",
    ]
    private static let slotLinks: Set = ["with", "on"]
    private static let articles: Set = ["a", "an", "the", "some", "one", "few", "couple"]

    private func readSlotWithTag(_ scan: inout Scan) {
        var index = 0
        while index < scan.tokens.count {
            defer { index += 1 }
            let word = scan.tokens[index].word
            let isOpener = Self.openerVerbs.contains(word)
            guard isOpener || Self.closerVerbs.contains(word), !scan.used[index] else { continue }
            var cursor = index + 1
            if word == "kick", scan.word(at: cursor) == "off" {
                cursor += 1
            }
            guard let link = scan.word(at: cursor), Self.slotLinks.contains(link) else { continue }
            cursor += 1
            while let next = scan.word(at: cursor), Self.articles.contains(next) {
                cursor += 1
            }
            guard let (tag, length) = longestTag(in: scan, at: cursor) else { continue }
            let end = cursor + length
            scan.claim(index ..< end, isOpener ? .opener(tag: tag) : .closer(tag: tag))
            index = end - 1
        }
    }

    // MARK: - Tags and smart filters

    private static let negators: Set = [
        "no", "not", "skip", "without", "except", "minus", "avoid", "exclude", "excluding",
        "nothing", "bina", "non", "never", "drop", "leave", "nor",
    ]
    private static let postNegators: Set = ["nahi", "nahin", "mat"]
    private static let negationFillers: Set = [
        "the", "any", "those", "these", "of", "a", "an", "out", "my", "too", "many",
    ]
    private static let listLinks: Set = ["or", "nor", ","]

    private func readNames(_ scan: inout Scan) {
        var index = 0
        var negatedList = false
        while index < scan.tokens.count {
            guard !scan.used[index] else {
                negatedList = false
                index += 1
                continue
            }
            let fromPrefix = scan.tokens[index].word == "from"
            if fromPrefix, let (filter, length) = longestFilter(in: scan, at: index + 1) {
                scan.claim(index ..< index + 1 + length, .smartFilter(filter.id))
                index += 1 + length
                negatedList = false
                continue
            }
            let tagMatch = longestTag(in: scan, at: index)
            let filterMatch = longestFilter(in: scan, at: index)
            if let (filter, length) = filterMatch, length > (tagMatch?.1 ?? 0) {
                scan.claim(index ..< index + length, .smartFilter(filter.id))
                index += length
                negatedList = false
                continue
            }
            guard let (tag, length) = tagMatch else {
                if !Self.listLinks.contains(scan.tokens[index].word) {
                    negatedList = false
                }
                index += 1
                continue
            }
            var range = index ..< index + length
            var negated = negatedList
            if let negator = negatorBefore(index, in: scan) {
                negated = true
                range = negator ..< range.upperBound
            }
            if let post = scan.word(at: range.upperBound), Self.postNegators.contains(post) {
                negated = true
                range = range.lowerBound ..< range.upperBound + 1
            }
            scan.claim(range, negated ? .excludeTag(tag) : .tag(tag))
            negatedList = negated
            index = range.upperBound
            // "no covers or ballads": the negation runs on across "or" and commas.
            if negated, let link = scan.word(at: index), Self.listLinks.contains(link) {
                scan.used[index] = true
                index += 1
            }
        }
    }

    /// The index of a negator right before `index` (fillers between allowed), if any.
    private func negatorBefore(_ index: Int, in scan: Scan) -> Int? {
        var cursor = index - 1
        while cursor >= 0, !scan.used[cursor] {
            let word = scan.tokens[cursor].word
            if Self.negators.contains(word) {
                return cursor
            }
            guard Self.negationFillers.contains(word) else { return nil }
            cursor -= 1
        }
        return nil
    }

    private func longestTag(in scan: Scan, at index: Int) -> (String, Int)? {
        longest(in: scan, at: index) { tagsByKey[$0] }
    }

    private func longestFilter(in scan: Scan, at index: Int) -> (SmartFilterName, Int)? {
        longest(in: scan, at: index) { filtersByKey[$0] }
    }

    private func longest<T>(in scan: Scan, at index: Int, lookup: (String) -> T?) -> (T, Int)? {
        var length = min(longestName, scan.tokens.count - index)
        while length > 0 {
            let range = index ..< index + length
            if !range.contains(where: { scan.used[$0] || scan.tokens[$0].isComma }) {
                let words = range.map { scan.tokens[$0].word }
                // "the hindi ones": a trailing "ones" belongs to the name it follows.
                if let found = Self.keys(words).lazy.compactMap(lookup).first {
                    let ones = scan.word(at: range.upperBound).map { $0 == "ones" } ?? false
                    return (found, length + (ones ? 1 : 0))
                }
            }
            length -= 1
        }
        return nil
    }

    /// The lookup keys of a name's words: spaced and joined ("sing along" finds "singalong"),
    /// each word singular and in `RomanNormalizer`'s loose form ("pyaar" = "pyar").
    static func keys(_ words: [String]) -> [String] {
        let folded = words
            .map { RomanNormalizer.looseWord(RomanNormalizer.normalizeWord(singular($0))) }
        let spaced = folded.joined(separator: " ")
        let joined = folded.joined()
        return spaced == joined ? [spaced] : [spaced, joined]
    }

    static func nameWords(_ name: String) -> [String] {
        RomanNormalizer.words(name)
    }

    /// "ballads" -> "ballad", "crowd pleasers" -> "pleaser"; short words and "-ss" stay.
    static func singular(_ word: String) -> String {
        guard word.count > 3, word.hasSuffix("s"), !word.hasSuffix("ss"), !word.hasSuffix("us")
        else { return word }
        return String(word.dropLast())
    }
}

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
