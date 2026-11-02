import Foundation
import Library

/// Spec 6.3 step 4: merge the answers of every query, deduplicate by id and then by loose
/// title and artist, and rank by `0.55 x title + 0.25 x artist + 0.10 x lyric start + 0.10 x
/// has plain lyrics`, every similarity on `RomanNormalizer.loose` words. Instrumental records
/// sort last. Each result keeps its breakdown, which sums to its score.
enum LyricsRanker {
    struct Ranked: Sendable, Hashable {
        var record: LyricsRecord
        var title: Double
        var artist: Double
        var lyricStart: Double
        var hasLyrics: Double

        var score: Double {
            title + artist + lyricStart + hasLyrics
        }
    }

    static let titleWeight = 0.55
    static let artistWeight = 0.25
    static let lyricWeight = 0.10
    static let lyricsWeight = 0.10

    static func rank(_ records: [LyricsRecord], query: String) -> [Ranked] {
        let queryWords = words(query)
        var seenIDs: Set<Int> = []
        var seenNames: Set<String> = []
        var ranked: [Ranked] = []
        for record in records where seenIDs.insert(record.id).inserted {
            let name = RomanNormalizer.loose(record.trackName ?? "") + "|"
                + RomanNormalizer.loose(record.artistName ?? "")
            guard seenNames.insert(name).inserted else { continue }
            let firstLine = (record.plainLyrics ?? "").split(separator: "\n").first
                .map(String.init) ?? ""
            ranked.append(Ranked(
                record: record,
                title: titleWeight * covered(words(record.trackName ?? ""), by: queryWords),
                artist: artistWeight * covered(words(record.artistName ?? ""), by: queryWords),
                lyricStart: lyricWeight * covered(queryWords, by: words(firstLine)),
                hasLyrics: (record.plainLyrics?.isEmpty == false) ? lyricsWeight : 0,
            ))
        }
        return ranked.enumerated().sorted { lhs, rhs in
            let left = lhs.element, right = rhs.element
            if left.record.isInstrumental != right.record.isInstrumental {
                return !left.record.isInstrumental
            }
            return left.score == right.score ? lhs.offset < rhs.offset : left.score > right.score
        }.map(\.element)
    }

    /// The share of `words` found in `pool` (0 when `words` is empty).
    static func covered(_ words: Set<String>, by pool: Set<String>) -> Double {
        guard !words.isEmpty else { return 0 }
        return Double(words.intersection(pool).count) / Double(words.count)
    }

    static func words(_ text: String) -> Set<String> {
        Set(RomanNormalizer.loose(text).split(separator: " ").map(String.init))
    }
}
