import ChordPro
import Foundation

/// Which rule found a song for a whole typed line (P8-5 section 6.3), best first.
public enum MatchTier: String, Sendable, CaseIterable, Comparable {
    case exactTitle
    case titlePrefix
    case titleWords
    case fuzzyTitle
    case firstLine
    /// The whole line names an artist ("arijit", "by arijit"): every song by them, by title
    /// (P8-8 section 3.5.1).
    case artist

    /// Earlier cases are better.
    public static func < (lhs: Self, rhs: Self) -> Bool {
        lhs.rank < rhs.rank
    }

    private var rank: Int {
        Self.allCases.firstIndex(of: self) ?? 0
    }
}

/// The spelling form a match was made in: as typed, `RomanNormalizer` normalized, or its
/// loose (vowel quality) form.
public enum MatchForm: String, Sendable, CaseIterable {
    case original
    case normalized
    case loose

    /// Position in `allCases`.
    var index: Int {
        switch self {
        case .original: 0
        case .normalized: 1
        case .loose: 2
        }
    }

    /// Points taken off the tier's base score for a match in this form.
    var penalty: Int {
        switch self {
        case .original: 0
        case .normalized: 3
        case .loose: 6
        }
    }
}

/// How sure a match is: `strong` (the title as typed or its start), `likely` (every word
/// in the title), `weak` (a close spelling or the first lyric line).
public enum MatchBand: String, Sendable, CaseIterable {
    case strong
    case likely
    case weak
}

/// One song a library can match: its display title, first lyric line and artists, nothing
/// else.
public struct MatchCandidate: Sendable, Equatable {
    public var id: SongID
    /// `{title}`, else the file name without extension (`SongRecord.displayTitle`).
    public var title: String
    /// First non-blank lyric line (`SongDocument.firstLyricLine`); "" when none.
    public var firstLine: String
    /// The song's artists as written (`Metadata.artists`), for the artist qualifier and the
    /// artist tier (P8-8 section 3.5.1).
    public var artists: [String]

    public init(id: SongID, title: String, firstLine: String, artists: [String] = []) {
        self.id = id
        self.title = title
        self.firstLine = firstLine
        self.artists = artists
    }

    /// From a loaded record. Reads only the title (or file name), the first lyric line and
    /// the artists: the matcher never sees lyrics bodies, albums or tags.
    public init(record: SongRecord) {
        self.init(
            id: record.id,
            title: record.displayTitle,
            firstLine: record.document.firstLyricLine,
            artists: record.document.metadata.artists,
        )
    }
}

/// A candidate the matcher found, with why.
public struct SongMatch: Sendable, Equatable {
    public var id: SongID
    public var score: Int
    public var tier: MatchTier
    public var form: MatchForm
    public var band: MatchBand
    /// The artist (one `ArtistNames.split` part, as written) that trailing query words
    /// qualified the title with, or that the `artist` tier matched; nil otherwise.
    public var artist: String?

    public init(
        id: SongID,
        score: Int,
        tier: MatchTier,
        form: MatchForm,
        artist: String? = nil,
    ) {
        self.id = id
        self.score = score
        self.tier = tier
        self.form = form
        self.artist = artist
        band = switch tier {
        case .exactTitle, .titlePrefix: .strong
        case .titleWords: .likely
        case .artist, .firstLine, .fuzzyTitle: .weak
        }
    }
}

/// Answers "which song does this whole line name" for the set composer (P8-5 section 6).
///
/// Scores titles (with the file-name fallback) and, as a weaker signal, first lyric lines;
/// trailing words naming one of the song's artists qualify a title ("tum hi ho arijit",
/// "tum hi ho by arijit"), and a line that only names an artist lists their songs (P8-8
/// section 3.5.1, amending P8-5's "never artists"); never lyrics bodies, albums or tags. Uses the same `RomanNormalizer` forms as library
/// search so both agree on romanized Hindi spelling variants. Every title and first line
/// is tokenized once in `init`; `bestMatches(for:limit:)` runs per keystroke, in memory,
/// linear in the number of songs.
public struct SongMatcher: Sendable {
    /// Every distinct word of every title and first line, in any form, numbered once, so a
    /// keystroke compares integers rather than strings.
    private struct Vocabulary: Sendable {
        var ids: [String: Int] = [:]
        var words: [String] = []
        var scalars: [[Unicode.Scalar]] = []

        mutating func intern(_ word: String) -> Int {
            if let id = ids[word] {
                return id
            }
            let id = words.count
            ids[word] = id
            words.append(word)
            scalars.append(Array(word.unicodeScalars))
            return id
        }
    }

    /// One text's words in the three forms, as vocabulary IDs.
    private struct Words: Sendable {
        var original: [Int]
        var normalized: [Int]
        var loose: [Int]

        subscript(form: MatchForm) -> [Int] {
            switch form {
            case .original: original
            case .normalized: normalized
            case .loose: loose
            }
        }
    }

    private struct Prepared: Sendable {
        var candidate: MatchCandidate
        var title: Words
        var firstLine: Words
        /// Each artist part (`ArtistNames.split`) as written, with its normalized words.
        var artists: [(name: String, words: [Int])]
    }

    /// The typed line, prepared once per keystroke.
    private struct Query {
        /// Vocabulary IDs per form (`MatchForm.index`); -1 for a word no song has.
        var ids: [[Int]]
        /// Per form: which vocabulary words the last typed word is a prefix of (nil when the
        /// form allows no prefix for it).
        var lastPrefixOf: [[Bool]?]
        /// Per typed word (normalized form): which vocabulary words are one edit away; nil
        /// for words under 4 letters.
        var nearby: [[Bool]?]
        /// Typed word positions that read "by" (an artist qualifier's lead word).
        var byWords: Set<Int> = []
        /// Letters in the typed line (the artist tier needs 4+).
        var letters = 0

        /// The first `count` words as their own query: no word of it is a prefix (the user
        /// typed past it).
        func head(_ count: Int) -> Self {
            Self(
                ids: ids.map { Array($0.prefix(count)) },
                lastPrefixOf: ids.map { _ in nil },
                nearby: Array(nearby.prefix(count)),
                byWords: byWords.filter { $0 < count },
            )
        }

        func matches(_ form: MatchForm, _ index: Int, _ word: Int, isLast: Bool) -> Bool {
            if ids[form.index][index] == word {
                return true
            }
            return isLast && lastPrefixOf[form.index]?[word] == true
        }
    }

    private let prepared: [Prepared]
    private let vocabulary: Vocabulary

    public init(candidates: [MatchCandidate]) {
        var vocabulary = Vocabulary()
        func words(_ text: String) -> Words {
            let forms = Self.forms(of: text)
            return Words(
                original: forms.original.map { vocabulary.intern($0) },
                normalized: forms.normalized.map { vocabulary.intern($0) },
                loose: forms.loose.map { vocabulary.intern($0) },
            )
        }
        prepared = candidates.map { candidate in
            Prepared(
                candidate: candidate,
                title: words(candidate.title),
                firstLine: words(candidate.firstLine),
                artists: candidate.artists.flatMap { ArtistNames.split($0).parts }.map { name in
                    (name, Self.forms(of: name).normalized.map { vocabulary.intern($0) })
                }.filter { !$0.1.isEmpty },
            )
        }
        self.vocabulary = vocabulary
    }

    /// Ranked best first: by tier, then score, then shorter title, then title, then ID. At
    /// most `limit`; empty when the query has no words or nothing matches.
    public func bestMatches(for query: String, limit: Int = 5) -> [SongMatch] {
        let forms = Self.forms(of: query)
        guard !forms.original.isEmpty, limit > 0 else { return [] }
        let prepared = prepare(forms)
        let allowsFirstLine = forms.original.count >= 2 || forms.original.joined().count >= 5
        var scored: [(SongMatch, Prepared)] = []
        for song in self.prepared {
            if let match = match(prepared, song, allowsFirstLine: allowsFirstLine) {
                scored.append((match, song))
            }
        }
        return scored.sorted { lhs, rhs in
            Self.ranksBefore(lhs, rhs)
        }
        .prefix(limit)
        .map(\.0)
    }

    private func prepare(_ forms: TextForms) -> Query {
        var ids: [[Int]] = []
        var lastPrefixOf: [[Bool]?] = []
        for form in MatchForm.allCases {
            let typed = switch form {
            case .original: forms.original
            case .normalized: forms.normalized
            case .loose: forms.loose
            }
            ids.append(typed.map { vocabulary.ids[$0] ?? -1 })
            guard let last = typed.last,
                  form == .original || last.count >= SongIndex.minimumPrefixLength
            else {
                lastPrefixOf.append(nil)
                continue
            }
            lastPrefixOf.append(vocabulary.words.map { $0.hasPrefix(last) })
        }
        let nearby = forms.normalized.map { word -> [Bool]? in
            let typed = Array(word.unicodeScalars)
            guard typed.count >= 4 else { return nil }
            return vocabulary.scalars.map { candidate in
                abs(candidate.count - typed.count) <= 1
                    && RomanNormalizer.editDistance(typed, candidate, limit: 1) <= 1
            }
        }
        return Query(
            ids: ids,
            lastPrefixOf: lastPrefixOf,
            nearby: nearby,
            byWords: Set(forms.original.indices.filter { forms.original[$0].lowercased() == "by" }),
            letters: forms.original.reduce(0) { $0 + $1.count },
        )
    }

    private static func ranksBefore(_ lhs: (SongMatch, Prepared), _ rhs: (SongMatch, Prepared))
        -> Bool
    {
        if lhs.0.tier != rhs.0.tier {
            return lhs.0.tier < rhs.0.tier
        }
        if lhs.0.score != rhs.0.score {
            return lhs.0.score > rhs.0.score
        }
        let leftTitle = lhs.1.candidate.title
        let rightTitle = rhs.1.candidate.title
        // The artist tier lists an artist's songs by title alone.
        if lhs.0.tier != .artist, leftTitle.count != rightTitle.count {
            return leftTitle.count < rightTitle.count
        }
        switch leftTitle.localizedStandardCompare(rightTitle) {
        case .orderedAscending: return true
        case .orderedDescending: return false
        case .orderedSame: return lhs.0.id < rhs.0.id
        }
    }

    // MARK: - Tiers

    private static let titleTiers: [(MatchTier, Int)] = [
        (.exactTitle, 100), (.titlePrefix, 90), (.titleWords, 75),
    ]
    private static let firstLineTiers: [(MatchTier, Int)] = [(.titlePrefix, 50), (.titleWords, 45)]
    private static let allForms = MatchForm.allCases
    private static let firstLineForms: [MatchForm] = [.normalized, .loose]

    private func match(_ query: Query, _ song: Prepared, allowsFirstLine: Bool) -> SongMatch? {
        let id = song.candidate.id
        let count = query.ids[0].count
        if let match = Self.titleMatch(query, song) {
            return match
        }
        // An artist qualifier: trailing words (optionally led by "by") naming one of the
        // song's artists are set aside and the rest must still match the title. Shortest
        // qualifier first, so the title keeps as many words as it can.
        for qualifier in 1 ..< max(count, 1) {
            let headCount = count - qualifier
            guard let artist = Self.qualifier(query, from: headCount, song),
                  var match = Self.titleMatch(query.head(Self.trimBy(query, headCount)), song)
            else { continue }
            match.artist = artist
            return match
        }
        if Self.matchesFuzzy(query, song.title.normalized) {
            let score = 60 - MatchForm.normalized.penalty
                - min(song.title.normalized.count - count, 5)
            return SongMatch(id: id, score: score, tier: .fuzzyTitle, form: .normalized)
        }
        guard allowsFirstLine else { return Self.artistMatch(query, song) }
        for (tier, base) in Self.firstLineTiers {
            for form in Self.firstLineForms {
                let words = song.firstLine[form]
                guard Self.matches(tier, query, form, words) else { continue }
                let score = base - form.penalty - min(words.count - count, 5)
                return SongMatch(id: id, score: score, tier: .firstLine, form: form)
            }
        }
        return Self.artistMatch(query, song)
    }

    /// The `exactTitle`, `titlePrefix` and `titleWords` tiers for `query`.
    private static func titleMatch(_ query: Query, _ song: Prepared) -> SongMatch? {
        let count = query.ids[0].count
        guard count > 0 else { return nil }
        for (tier, base) in titleTiers {
            for form in allForms {
                let words = song.title[form]
                guard matches(tier, query, form, words) else { continue }
                let score = base - form.penalty - min(words.count - count, 5)
                return SongMatch(id: song.candidate.id, score: score, tier: tier, form: form)
            }
        }
        return nil
    }

    /// The words before `headCount` with a trailing "by" dropped.
    private static func trimBy(_ query: Query, _ headCount: Int) -> Int {
        headCount > 1 && query.byWords.contains(headCount - 1) ? headCount - 1 : headCount
    }

    /// The artist part the words from `start` on all name (each a distinct word of it; the
    /// last typed word may be a 4+ letter prefix), else nil.
    private static func qualifier(_ query: Query, from start: Int, _ song: Prepared) -> String? {
        let typed = query.ids[MatchForm.normalized.index]
        guard start < typed.count else { return nil }
        let last = typed.count - 1
        let words = Array(start ... last)
        for artist in song.artists {
            let found = assigns(words.count, slots: artist.words.count) { index, slot in
                query.matches(.normalized, words[index], artist.words[slot],
                              isLast: words[index] == last)
            }
            if found {
                return artist.name
            }
        }
        return nil
    }

    /// The `artist` tier: the whole line (after a leading "by") is the leading words of one
    /// of the song's artists, the last typed word possibly a 4+ letter prefix; 4+ letters.
    private static func artistMatch(_ query: Query, _ song: Prepared) -> SongMatch? {
        let typed = query.ids[MatchForm.normalized.index]
        let start = typed.count > 1 && query.byWords.contains(0) ? 1 : 0
        guard query.letters - (start == 1 ? 2 : 0) >= 4, start < typed.count else { return nil }
        let last = typed.count - 1
        for artist in song.artists where typed.count - start <= artist.words.count {
            let leads = (start ... last).allSatisfy { index in
                query.matches(.normalized, index, artist.words[index - start],
                              isLast: index == last)
            }
            if leads {
                return SongMatch(
                    id: song.candidate.id,
                    score: 40,
                    tier: .artist,
                    form: .normalized,
                    artist: artist.name,
                )
            }
        }
        return nil
    }

    /// The `exactTitle`, `titlePrefix` and `titleWords` rules against `words`. A typed word
    /// matches a word when equal or, for the last typed word only, a prefix of it (in the
    /// normalized forms only from `SongIndex.minimumPrefixLength` letters).
    private static func matches(
        _ tier: MatchTier,
        _ query: Query,
        _ form: MatchForm,
        _ words: [Int],
    ) -> Bool {
        let typed = query.ids[form.index]
        guard !typed.isEmpty, typed.count <= words.count else { return false }
        let last = typed.count - 1
        switch tier {
        case .exactTitle:
            return typed == words
        case .titlePrefix:
            for index in typed.indices
                where !query.matches(form, index, words[index], isLast: index == last)
            {
                return false
            }
            return true
        case .titleWords:
            return assigns(typed.count, slots: words.count) { index, slot in
                query.matches(form, index, words[slot], isLast: index == last)
            }
        case .artist, .firstLine, .fuzzyTitle:
            return false
        }
    }

    /// The `fuzzyTitle` rule, in the normalized form only: each typed word matches a
    /// distinct title word as in `titleWords`, or (4+ letters) is one edit away from it.
    /// Only reached when `titleWords` failed, so a pairing found here used an edit.
    private static func matchesFuzzy(_ query: Query, _ words: [Int]) -> Bool {
        let count = query.nearby.count
        guard count > 0, count <= words.count else { return false }
        return assigns(count, slots: words.count) { index, slot in
            query.matches(.normalized, index, words[slot], isLast: index == count - 1)
                || query.nearby[index]?[words[slot]] == true
        }
    }

    /// Whether `words` typed words can each be paired with a distinct one of `slots` title
    /// words (any order), where `pairs(word, slot)` says which pairings are allowed.
    private static func assigns(
        _ words: Int,
        slots: Int,
        _ pairs: (Int, Int) -> Bool,
    ) -> Bool {
        guard words > 0, words <= slots else { return false }
        if words == 1 {
            for slot in 0 ..< slots where pairs(0, slot) {
                return true
            }
            return false
        }
        var options: [[Int]] = []
        options.reserveCapacity(words)
        for word in 0 ..< words {
            var allowed: [Int] = []
            for slot in 0 ..< slots where pairs(word, slot) {
                allowed.append(slot)
            }
            guard !allowed.isEmpty else { return false }
            options.append(allowed)
        }
        // Most constrained word first; titles are short, so backtracking stays tiny.
        let order = options.indices.sorted { options[$0].count < options[$1].count }
        var used = Array(repeating: false, count: slots)
        func place(_ position: Int) -> Bool {
            guard position < order.count else { return true }
            for slot in options[order[position]] where !used[slot] {
                used[slot] = true
                if place(position + 1) {
                    return true
                }
                used[slot] = false
            }
            return false
        }
        return place(0)
    }

    /// A text's words in the three forms (`RomanNormalizer.words`, `normalizeWord`,
    /// `looseWord`).
    private struct TextForms {
        var original: [String]
        var normalized: [String]
        var loose: [String]
    }

    private static func forms(of text: String) -> TextForms {
        let original = RomanNormalizer.words(text)
        let normalized = original.map(RomanNormalizer.normalizeWord)
        return TextForms(
            original: original,
            normalized: normalized,
            loose: normalized.map(RomanNormalizer.looseWord),
        )
    }
}
