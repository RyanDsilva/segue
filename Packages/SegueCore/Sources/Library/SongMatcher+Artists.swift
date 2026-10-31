import Foundation

// P8-8 section 3.5.1: the composer's artist qualifier ("tum hi ho arijit", "tum hi ho by
// arijit") and the artist tier ("arijit", "by arijit"), split from SongMatcher.swift.

extension SongMatcher.Query {
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
}

extension SongMatcher {
    /// The `exactTitle`, `titlePrefix` and `titleWords` tiers for `query`.
    static func titleMatch(_ query: Query, _ song: Prepared) -> SongMatch? {
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
    static func trimBy(_ query: Query, _ headCount: Int) -> Int {
        headCount > 1 && query.byWords.contains(headCount - 1) ? headCount - 1 : headCount
    }

    /// The artist part the words from `start` on all name (each a distinct word of it; the
    /// last typed word may be a 4+ letter prefix), else nil.
    static func qualifier(_ query: Query, from start: Int, _ song: Prepared) -> String? {
        let typed = query.ids[MatchForm.normalized.index]
        guard start < typed.count else { return nil }
        let last = typed.count - 1
        let words = Array(start ... last)
        for artist in song.artists {
            let found = assigns(words.count, slots: artist.words.count) { index, slot in
                query.matches(
                    .normalized,
                    words[index],
                    artist.words[slot],
                    isLast: words[index] == last,
                )
            }
            if found {
                return artist.name
            }
        }
        return nil
    }

    /// The `artist` tier: the whole line (after a leading "by") is the leading words of one
    /// of the song's artists, the last typed word possibly a 4+ letter prefix; 4+ letters.
    static func artistMatch(_ query: Query, _ song: Prepared) -> SongMatch? {
        let typed = query.ids[MatchForm.normalized.index]
        let start = typed.count > 1 && query.byWords.contains(0) ? 1 : 0
        guard query.letters - (start == 1 ? 2 : 0) >= 4, start < typed.count else { return nil }
        let last = typed.count - 1
        for artist in song.artists where typed.count - start <= artist.words.count {
            let leads = (start ... last).allSatisfy { index in
                query.matches(
                    .normalized,
                    index,
                    artist.words[index - start],
                    isLast: index == last,
                )
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
}
