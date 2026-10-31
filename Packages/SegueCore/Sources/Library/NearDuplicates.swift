import ChordPro
import Foundation

/// "Looks like a song already in your library" (P8-1 section 6, R154, R158 Q8): one
/// deterministic similarity score over title, artist and content, checked only against
/// library songs whose titles look similar. Built once per review sheet or import batch, so
/// the sheet can re-check on every edit without a store call. Original text is never
/// changed; normalization (`RomanNormalizer`, run at check time, nothing stored) only
/// decides the warning.
public struct NearDuplicateIndex: Sendable {
    /// Why a song matched: each part 0...1.
    public struct Breakdown: Sendable, Hashable {
        /// Title similarity `T`: the better of character and word similarity.
        public let title: Double
        /// Artist similarity `A`: 1 same, 0 different, 0.5 when either side has none.
        public let artist: Double
        /// Content similarity `C`: Jaccard of lyric word 3-shingles, 0.5 when either side
        /// has fewer than 3 (a chords-only chart).
        public let content: Double

        public init(title: Double, artist: Double, content: Double) {
            self.title = title
            self.artist = artist
            self.content = content
        }

        /// `S = 0.5 T + 0.2 A + 0.3 C`.
        public var score: Double {
            0.5 * title + 0.2 * artist + 0.3 * content
        }
    }

    /// The library song an incoming one looks like.
    public struct Match: Sendable, Hashable {
        public let songId: SongID
        public let title: String
        /// The song's artists, joined; nil when it has none.
        public let artist: String?
        /// Why it matched (tests and debugging).
        public let breakdown: Breakdown
    }

    /// A song looks like another at this score or above.
    public static let threshold = 0.72
    /// Lyric words compared per song: enough to tell songs apart, bounded per check.
    static let maxWords = 400
    /// The most edits a title may differ by and still count as similar by character.
    static let titleEditLimit = 3
    /// Titles less similar than this are never scored further.
    static let minTitleSimilarity = 0.5

    /// One library song, prepared once.
    struct Entry: Sendable {
        let songId: SongID
        let title: String
        let artist: String?
        let looseTitle: String
        let titleWords: Set<String>
        let artists: Set<String>
        let contentHash: String
        /// Shingled on demand, only when the title is similar.
        let lyrics: String
    }

    let entries: [Entry]
    /// Blocking key -> indices into `entries`.
    let blocks: [String: [Int]]
    let byHash: [String: Int]

    public init(_ songs: some Sequence<SongRecord>) {
        var entries: [Entry] = []
        var blocks: [String: [Int]] = [:]
        var byHash: [String: Int] = [:]
        for song in songs {
            let metadata = song.document.metadata
            let title = metadata.title.flatMap { $0.isEmpty ? nil : $0 }
                ?? Self.fileStem(song.relativePath)
            let looseTitle = RomanNormalizer.loose(title)
            let entry = Entry(
                songId: song.id,
                title: title,
                artist: metadata.artists.isEmpty ? nil : metadata.artists
                    .joined(separator: ", "),
                looseTitle: looseTitle,
                titleWords: Set(looseTitle.split(separator: " ").map(String.init)),
                artists: Self.artistForms(metadata.artists),
                contentHash: song.revision.contentHash,
                lyrics: song.document.plainLyrics,
            )
            let index = entries.count
            entries.append(entry)
            for key in Self.blockingKeys(looseTitle) {
                blocks[key, default: []].append(index)
            }
            if !entry.contentHash.isEmpty, byHash[entry.contentHash] == nil {
                byHash[entry.contentHash] = index
            }
        }
        self.entries = entries
        self.blocks = blocks
        self.byHash = byHash
    }

    /// The content hash the library keeps for `text` written as a song (its UTF-8 bytes).
    public static func contentHash(of text: String) -> String {
        SongFiles.hash(Data(text.utf8))
    }

    /// The library song this one looks most like, or nil. A song with exactly the same
    /// bytes is not a lookalike (`identical(contentHash:)` finds it). Ties go to the shorter
    /// title, then the title in Finder order, then the song ID, so the result is stable.
    public func match(
        title: String?,
        artists: [String],
        lyrics: String,
        contentHash: String,
    ) -> Match? {
        guard let title, !title.isEmpty else { return nil }
        let looseTitle = RomanNormalizer.loose(title)
        let titleWords = Set(looseTitle.split(separator: " ").map(String.init))
        let artistForms = Self.artistForms(artists)
        var shingles: Set<String>?
        var best: (entry: Entry, breakdown: Breakdown)?
        for index in candidates(forLooseTitle: looseTitle) {
            let entry = entries[index]
            guard entry.contentHash != contentHash else { continue }
            let titleScore = Self.titleSimilarity(
                looseTitle,
                titleWords,
                entry.looseTitle,
                entry.titleWords,
            )
            guard titleScore >= Self.minTitleSimilarity else { continue }
            let incoming = shingles ?? Self.shingles(lyrics)
            shingles = incoming
            let breakdown = Breakdown(
                title: titleScore,
                artist: Self.artistSimilarity(artistForms, entry.artists),
                content: Self.contentSimilarity(incoming, Self.shingles(entry.lyrics)),
            )
            guard breakdown.score >= Self.threshold else { continue }
            if let current = best, !Self.isBetter(entry, breakdown, than: current) {
                continue
            }
            best = (entry, breakdown)
        }
        return best.map { Self.match($0.entry, $0.breakdown) }
    }

    /// A library song with exactly this content hash, or nil.
    public func identical(contentHash: String) -> Match? {
        guard let index = byHash[contentHash] else { return nil }
        return Self.match(entries[index], Breakdown(title: 1, artist: 1, content: 1))
    }

    /// Indices of the songs sharing a blocking key with a title (internal for tests).
    func candidates(forLooseTitle looseTitle: String) -> [Int] {
        var seen: Set<Int> = []
        var result: [Int] = []
        for key in Self.blockingKeys(looseTitle) {
            for index in blocks[key] ?? [] where seen.insert(index).inserted {
                result.append(index)
            }
        }
        return result
    }

    /// The candidates for a title as typed (tests).
    func candidates(for title: String) -> [Int] {
        candidates(forLooseTitle: RomanNormalizer.loose(title))
    }
}

// MARK: - Scoring

extension NearDuplicateIndex {
    /// The first 3 letters of each loose title word of 3 or more letters; a title with no
    /// such word ("Ho") uses its whole loose form.
    static func blockingKeys(_ looseTitle: String) -> Set<String> {
        let words = looseTitle.split(separator: " ")
        let keys = Set(words.filter { $0.count >= 3 }.map { String($0.prefix(3)) })
        if keys.isEmpty, !looseTitle.isEmpty {
            return [looseTitle]
        }
        return keys
    }

    /// `T = max(charSim, wordSim)` over the loose titles.
    static func titleSimilarity(
        _ lhs: String,
        _ lhsWords: Set<String>,
        _ rhs: String,
        _ rhsWords: Set<String>,
    ) -> Double {
        var characters = 0.0
        if !lhs.isEmpty, !rhs.isEmpty {
            let distance = RomanNormalizer.editDistance(lhs, rhs, limit: titleEditLimit)
            if distance <= titleEditLimit {
                characters = 1 - Double(distance) / Double(max(lhs.count, rhs.count))
            }
        }
        return max(characters, jaccard(lhsWords, rhsWords))
    }

    static func artistSimilarity(_ lhs: Set<String>, _ rhs: Set<String>) -> Double {
        guard !lhs.isEmpty, !rhs.isEmpty else { return 0.5 }
        return lhs.isDisjoint(with: rhs) ? 0 : 1
    }

    static func contentSimilarity(_ lhs: Set<String>, _ rhs: Set<String>) -> Double {
        guard lhs.count >= 3, rhs.count >= 3 else { return 0.5 }
        return jaccard(lhs, rhs)
    }

    /// Word 3-shingles of the first `maxWords` loose lyric words (re-wrapped lines still
    /// match: line breaks are only word separators here).
    static func shingles(_ lyrics: String) -> Set<String> {
        let words = RomanNormalizer.words(lyrics).prefix(maxWords)
            .map { RomanNormalizer.looseWord(RomanNormalizer.normalizeWord($0)) }
        guard words.count >= 3 else { return [] }
        var result: Set<String> = []
        for start in 0 ... words.count - 3 {
            result.insert(words[start ..< start + 3].joined(separator: " "))
        }
        return result
    }

    static func jaccard(_ lhs: Set<String>, _ rhs: Set<String>) -> Double {
        let union = lhs.union(rhs).count
        guard union > 0 else { return 0 }
        return Double(lhs.intersection(rhs).count) / Double(union)
    }

    /// `ArtistNames.forms`: each value split first, so a legacy `{artist: Vishal & Shekhar}`
    /// meets a paste split into Vishal, Shekhar (P8-8 section 3.5).
    static func artistForms(_ artists: [String]) -> Set<String> {
        ArtistNames.forms(artists)
    }

    private static func isBetter(
        _ entry: Entry,
        _ breakdown: Breakdown,
        than current: (entry: Entry, breakdown: Breakdown),
    ) -> Bool {
        if breakdown.score != current.breakdown.score {
            return breakdown.score > current.breakdown.score
        }
        if entry.title.count != current.entry.title.count {
            return entry.title.count < current.entry.title.count
        }
        switch entry.title.localizedStandardCompare(current.entry.title) {
        case .orderedAscending: return true
        case .orderedDescending: return false
        case .orderedSame: return entry.songId < current.entry.songId
        }
    }

    private static func match(_ entry: Entry, _ breakdown: Breakdown) -> Match {
        Match(songId: entry.songId, title: entry.title, artist: entry.artist, breakdown: breakdown)
    }

    private static func fileStem(_ relativePath: String) -> String {
        URL(filePath: relativePath).deletingPathExtension().lastPathComponent
    }
}

public extension LibraryStore {
    /// The near-duplicate index over every library song (built once per review or batch).
    func nearDuplicateIndex() throws -> NearDuplicateIndex {
        try NearDuplicateIndex(openLibrary().songs.values.map(\.record))
    }
}
