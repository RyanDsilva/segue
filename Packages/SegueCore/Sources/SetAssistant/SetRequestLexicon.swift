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

    /// Every word no chip claimed, as typed and in order, filler included ("Let It Be").
    public var remainder: [String]

    public init(chips: [SetChip] = [], leftover: [String] = [], remainder: [String]? = nil) {
        self.chips = chips
        self.leftover = leftover
        self.remainder = remainder ?? leftover
    }

    /// The text a song search should still run on: the unclaimed words, or nothing when
    /// they are all filler ("upbeat songs in G" searches no text, "Paper Boats ballad"
    /// searches "Paper Boats").
    public var searchText: String {
        leftover.isEmpty ? "" : remainder.joined(separator: " ")
    }

    /// The leftover words joined by spaces (the model pass's input).
    public var leftoverText: String {
        leftover.joined(separator: " ")
    }
}

/// The instant request parser (spec section 7 step 1). Pure and fast: build one per library
/// vocabulary and call `parse` on every keystroke.
public struct SetRequestLexicon: Sendable {
    /// Slot phrases map to the first of these tags the library has (R92: only when asked;
    /// R116 drops "start soft" / "end soft").
    public static let strongOpenerTags = ["upbeat"]
    public static let bigCloserTags = ["crowd pleaser", "singalong"]

    private let tagsByKey: [String: String]
    private let filtersByKey: [String: SmartFilterName]
    private let longestName: Int
    /// The library's artists and albums (P8-8 section 3.5.2).
    let credits: CreditNames

    /// - Parameters:
    ///   - tags: the tags in use in the library, as spelled there.
    ///   - smartFilters: the library's saved smart filters.
    ///   - artists: the library's stored artist values (`Metadata.artists`, any song).
    ///   - albums: the library's Movie / Album values.
    public init(
        tags: [String],
        smartFilters: [SmartFilterName] = [],
        artists: [String] = [],
        albums: [String] = [],
    ) {
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
        credits = CreditNames(artists: artists, albums: albums)
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
        readCredits(&scan)
        readNames(&scan)
        return LexiconResult(
            chips: scan.orderedChips(),
            leftover: scan.leftover(),
            remainder: scan.remainder(),
        )
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
        add(.closer(bigCloserTags), [
            "finish big", "end big", "big finish", "big closer", "close big", "close strong",
            "finish strong", "end strong", "strong finish", "end on a high", "finish on a high",
            "end high", "go out big",
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
    func negatorBefore(_ index: Int, in scan: Scan) -> Int? {
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

    func longestTag(in scan: Scan, at index: Int) -> (String, Int)? {
        longest(in: scan, at: index) { tagsByKey[$0] }
    }

    func longestFilter(in scan: Scan, at index: Int) -> (SmartFilterName, Int)? {
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
