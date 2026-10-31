import Library
import Testing

/// The composer's artist qualifier and artist tier (P8-8 section 3.5.1, R173 "by <artist>").
struct SongMatcherArtistTests {
    static let songs: [(title: String, artists: [String])] = [
        ("Tum Hi Ho", ["Mithoon"]),
        ("Tum Hi Ho", ["Arijit Singh"]),
        ("Channa Mereya", ["Arijit Singh"]),
        ("Kesariya", ["Arijit Singh"]),
        ("Ghar More Pardesiya", ["Shreya Ghoshal", "Vaishali Mhade"]),
        ("Dus Bahane", ["Vishal & Shekhar"]),
        ("Arijit Medley", []),
    ]

    static var candidates: [MatchCandidate] {
        songs.enumerated().map { index, song in
            MatchCandidate(
                id: ComposerCorpus.id(500 + index),
                title: song.title,
                firstLine: "",
                artists: song.artists,
            )
        }
    }

    static let matcher = SongMatcher(candidates: candidates)

    static func describe(_ matches: [SongMatch]) -> [String] {
        matches.map { match in
            let index = candidates.firstIndex { $0.id == match.id } ?? 0
            let song = songs[index]
            return "\(song.title) / \(song.artists.first ?? "-")"
        }
    }

    @Test(arguments: ["tum hi ho arijit", "tum hi ho by arijit", "tum hi ho arijit singh",
                      "Tum Hi Ho Arij", "tum hi ho singh"])
    func `a trailing artist picks that song first`(typed: String) throws {
        let matches = Self.matcher.bestMatches(for: typed)
        let first = try #require(matches.first)
        #expect(Self.describe([first]) == ["Tum Hi Ho / Arijit Singh"])
        #expect(first.tier == .exactTitle)
        #expect(first.band == .strong)
        #expect(first.artist == "Arijit Singh")
    }

    @Test
    func `without a qualifier both songs titled Tum Hi Ho match`() {
        let matches = Self.matcher.bestMatches(for: "tum hi ho")
        #expect(matches.count == 2)
        #expect(matches.allSatisfy { $0.tier == .exactTitle && $0.artist == nil })
    }

    @Test(arguments: ["arijit", "by arijit", "Arijit Singh", "arij"])
    func `an artist alone lists their songs by title`(typed: String) {
        let matches = Self.matcher.bestMatches(for: typed, limit: 10)
        // "Arijit Medley" matches by title first; the artist tier follows, by title.
        let artistTier = matches.filter { $0.tier == .artist }
        #expect(Self.describe(artistTier) == [
            "Channa Mereya / Arijit Singh", "Kesariya / Arijit Singh", "Tum Hi Ho / Arijit Singh",
        ])
        #expect(artistTier.allSatisfy { $0.band == .weak && $0.artist == "Arijit Singh" })
        #expect(artistTier.allSatisfy { $0.score == 40 })
    }

    @Test
    func `a title match ranks before the artist tier`() {
        let matches = Self.matcher.bestMatches(for: "arijit", limit: 10)
        #expect(Self.describe(Array(matches.prefix(1))) == ["Arijit Medley / -"])
    }

    @Test(arguments: ["ari", "by ari", "a"])
    func `under four letters there is no artist tier`(typed: String) {
        let matches = Self.matcher.bestMatches(for: typed, limit: 10)
        #expect(!matches.contains { $0.tier == .artist })
    }

    @Test(arguments: ["zzz arijit", "kalank arijit", "by"])
    func `a qualifier never rescues a query that names no title`(typed: String) {
        let matches = Self.matcher.bestMatches(for: typed, limit: 10)
        #expect(!matches.contains { $0.tier != .artist && $0.artist != nil })
        #expect(!matches.contains { $0.tier == .exactTitle })
    }

    @Test
    func `legacy combined and later artist parts both qualify`() throws {
        let dus = try #require(Self.matcher.bestMatches(for: "dus bahane shekhar").first)
        #expect(dus.artist == "Shekhar")
        #expect(dus.tier == .exactTitle)
        let ghar = Self.matcher.bestMatches(for: "shreya", limit: 10)
        #expect(Self.describe(ghar) == ["Ghar More Pardesiya / Shreya Ghoshal"])
        #expect(ghar.first?.tier == .artist)
        let vaishali = Self.matcher.bestMatches(for: "vaishali", limit: 10)
        #expect(vaishali.first?.artist == "Vaishali Mhade")
    }

    @Test
    func `the record initializer reads artists`() {
        #expect(Self.candidates[1].artists == ["Arijit Singh"])
    }
}
