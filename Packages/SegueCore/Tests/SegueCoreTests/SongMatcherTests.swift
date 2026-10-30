import ChordPro
import Library
import Support
import Testing

/// The set composer's corpus library (P8-5 section 13.1): titles, plus first lines where a
/// row needs them.
enum ComposerCorpus {
    static let songs: [(title: String, firstLine: String)] = [
        ("Kesariya", "Mujhko itna bataaye koi"),
        ("Tum Hi Ho", "Hum tere bin ab reh nahi sakte"),
        ("Tum Hi Ho Bandhu", "Ho bandhu sakha"),
        ("Channa Mereya", "Achha chalta hoon"),
        ("Pehla Nasha", "Chaahe tum kuchh na kaho"),
        ("Deewana Hai Dekho", "Deewana hai dekho"),
        ("Kabhi Kabhi Aditi", "Kabhi kabhi aditi zindagi mein"),
        ("Phir Le Aya Dil", "Phir le aya dil majboor"),
        ("Tujh Mein Rab Dikhta Hai", "Tujh mein rab dikhta hai yaara"),
        ("Ae Dil Hai Mushkil", "Tu safar mera"),
        ("Kitaabon Wali Gali", "Purani si gali mein kitaabon ki dukaan"),
        ("Stuck in a Moment", "I'm not afraid of anything"),
        ("Wonderwall", "Today is gonna be the day"),
        ("Hotel California", "On a dark desert highway"),
        ("Soundcheck at Seven", "Testing one two"),
        // An untitled file: its title is the file name.
        ("naina", "Naina lade"),
    ]

    static func id(_ index: Int) -> SongID {
        SongID(ULID(milliseconds: 1000, randomness: Array(repeating: 0, count: 7) + [
            UInt8(index / 256), UInt8(index % 256), 1,
        ]))
    }

    static var candidates: [MatchCandidate] {
        songs.enumerated().map { index, song in
            MatchCandidate(id: id(index), title: song.title, firstLine: song.firstLine)
        }
    }

    static func title(of id: SongID) -> String? {
        candidates.first { $0.id == id }?.title
    }

    static let matcher = SongMatcher(candidates: candidates)
}

/// The whole-line matcher (P8-5 section 6): every corpus row of 13.1, then ordering
/// properties.
struct SongMatcherTests {
    struct Row: Sendable, CustomTestStringConvertible {
        var typed: String
        var first: String?
        var tier: MatchTier?
        var form: MatchForm?
        var following: [String] = []

        var testDescription: String {
            typed
        }

        /// The band section 6.4 gives each tier.
        var band: MatchBand? {
            switch tier {
            case .exactTitle, .titlePrefix: .strong
            case .titleWords: .likely
            case .firstLine, .fuzzyTitle: .weak
            case nil: nil
            }
        }
    }

    private static func row(
        _ typed: String,
        _ first: String,
        _ tier: MatchTier,
        _ form: MatchForm,
        then following: [String] = [],
    ) -> Row {
        Row(typed: typed, first: first, tier: tier, form: form, following: following)
    }

    private static func none(_ typed: String) -> Row {
        Row(typed: typed)
    }

    static let rows: [Row] = [
        row("Kesariya", "Kesariya", .exactTitle, .original),
        row("Kesariyaa", "Kesariya", .exactTitle, .normalized),
        row("kesar", "Kesariya", .titlePrefix, .original),
        row("kesriya", "Kesariya", .fuzzyTitle, .normalized),
        row("Tum Hi Ho", "Tum Hi Ho", .exactTitle, .original, then: ["Tum Hi Ho Bandhu"]),
        row("tum hi ho", "Tum Hi Ho", .exactTitle, .original),
        row("tum hi", "Tum Hi Ho", .titlePrefix, .original, then: ["Tum Hi Ho Bandhu"]),
        row("Tum Hi Ho Bandhu", "Tum Hi Ho Bandhu", .exactTitle, .original),
        row("bandhu", "Tum Hi Ho Bandhu", .titleWords, .original),
        row("Channa Mereya", "Channa Mereya", .exactTitle, .original),
        row("Chana Mereya", "Channa Mereya", .exactTitle, .normalized),
        row("chana mereyaa", "Channa Mereya", .exactTitle, .normalized),
        row("pehla nasha", "Pehla Nasha", .exactTitle, .original),
        row("pehela nasha", "Pehla Nasha", .fuzzyTitle, .normalized),
        row("diwana hai dekho", "Deewana Hai Dekho", .exactTitle, .normalized),
        row("dewana", "Deewana Hai Dekho", .titlePrefix, .loose),
        row("kabhie kabhi", "Kabhi Kabhi Aditi", .titlePrefix, .normalized),
        row("fir le aya dil", "Phir Le Aya Dil", .exactTitle, .normalized),
        row("tuj mein rab", "Tujh Mein Rab Dikhta Hai", .titlePrefix, .normalized),
        row("ae dil hain mushkil", "Ae Dil Hai Mushkil", .exactTitle, .normalized),
        // R157 short-word rules: `mai`/`mein` and `ae`/`ai` meet.
        row("tuj mai rab", "Tujh Mein Rab Dikhta Hai", .titlePrefix, .normalized),
        row("ai dil hai mushkil", "Ae Dil Hai Mushkil", .exactTitle, .normalized),
        row("kitabon wali", "Kitaabon Wali Gali", .titlePrefix, .normalized),
        row("purani si gali", "Kitaabon Wali Gali", .firstLine, .normalized),
        row("mujhko itna", "Kesariya", .firstLine, .normalized),
        row("naina", "naina", .exactTitle, .original),
        // The spec's table says titlePrefix / original; "wonderwal" and "Wonderwall" are
        // the same normalized word (`ll` collapses), and tier dominates, so it is an exact
        // title in the normalized form.
        row("wonderwal", "Wonderwall", .exactTitle, .normalized),
        none("xyzzy"),
        none("zzz qqq"),
        row("k", "Kesariya", .titlePrefix, .original, then: [
            "Kabhi Kabhi Aditi", "Kitaabon Wali Gali",
        ]),
        none("the"),
        row("ho", "Hotel California", .titlePrefix, .original, then: [
            "Tum Hi Ho", "Tum Hi Ho Bandhu",
        ]),
        none("!!!"),
        none("   "),
    ]

    @Test(arguments: rows)
    func `the corpus line names the expected song`(row: Row) throws {
        let matches = ComposerCorpus.matcher.bestMatches(for: row.typed)
        guard let expected = row.first else {
            #expect(matches.isEmpty)
            return
        }
        let first = try #require(matches.first)
        #expect(ComposerCorpus.title(of: first.id) == expected)
        #expect(first.tier == row.tier)
        #expect(first.form == row.form)
        #expect(first.band == row.band)
        if !row.following.isEmpty {
            let next = matches.dropFirst().prefix(row.following.count)
            #expect(next.compactMap { ComposerCorpus.title(of: $0.id) } == row.following)
        }
    }

    @Test
    func `typing tum hi ho bandhu in full never puts Tum Hi Ho first`() {
        let titles = ComposerCorpus.matcher.bestMatches(for: "Tum Hi Ho Bandhu")
            .compactMap { ComposerCorpus.title(of: $0.id) }
        #expect(titles.first == "Tum Hi Ho Bandhu")
        #expect(!titles.contains("Tum Hi Ho"))
    }

    @Test
    func `a word only in a later lyric line finds nothing`() {
        // "bataaye" and "koi" are on Kesariya's first line; "zindagi mein" only on Kabhi
        // Kabhi Aditi's. A long lyric body is never read.
        let long = MatchCandidate(
            id: ComposerCorpus.id(900),
            title: "Long Song",
            firstLine: "Opening words here",
        )
        let matcher = SongMatcher(candidates: [long])
        #expect(matcher.bestMatches(for: "hidden chorus words").isEmpty)
    }

    @Test
    func `the matcher reads only the first lyric line of a record`() throws {
        let source = """
        {title: Long Song}
        Opening words here
        Hidden chorus words later

        """
        let record = try TestSongs.record(source: source, id: ComposerCorpus.id(901))
        let fromRecord = SongMatcher(candidates: [MatchCandidate(record: record)])
        let fromFirstLine = SongMatcher(candidates: [MatchCandidate(
            id: record.id,
            title: "Long Song",
            firstLine: "Opening words here",
        )])
        for query in ["opening words", "hidden chorus words", "long", "later"] {
            #expect(fromRecord.bestMatches(for: query) == fromFirstLine.bestMatches(for: query))
        }
        #expect(fromRecord.bestMatches(for: "hidden chorus words").isEmpty)
        #expect(MatchCandidate(record: record).firstLine == "Opening words here")
    }

    @Test
    func `an untitled record matches by its file name`() throws {
        let record = try TestSongs.record(
            source: "Naina lade\n",
            id: ComposerCorpus.id(902),
            path: "songs/naina.cho",
        )
        #expect(MatchCandidate(record: record).title == "naina")
    }

    @Test(arguments: ["ho", "k", "dil", "kabhi", "tum", "hai", "dewana", "gali", "tum hi ho"])
    func `tier always dominates score`(typed: String) {
        // Within a tier the score orders; across tiers the tier alone does, so a low-scoring
        // match in a better tier still comes first.
        let matches = ComposerCorpus.matcher.bestMatches(for: typed, limit: 16)
        #expect(matches.map(\.tier) == matches.map(\.tier).sorted())
        for (lhs, rhs) in zip(matches, matches.dropFirst()) where lhs.tier == rhs.tier {
            #expect(lhs.score >= rhs.score)
        }
    }

    @Test
    func `ties break by shorter title, then title, then ID`() {
        let matcher = SongMatcher(candidates: [
            MatchCandidate(id: ComposerCorpus.id(5), title: "Rain Song", firstLine: ""),
            MatchCandidate(id: ComposerCorpus.id(4), title: "Rain Dance", firstLine: ""),
            MatchCandidate(id: ComposerCorpus.id(3), title: "Rain Dance", firstLine: ""),
            MatchCandidate(id: ComposerCorpus.id(2), title: "Rain Band", firstLine: ""),
        ])
        let ids = matcher.bestMatches(for: "rain").map(\.id)
        #expect(ids == [
            ComposerCorpus.id(2), ComposerCorpus.id(5), ComposerCorpus.id(3), ComposerCorpus.id(4),
        ])
        // Stable across runs.
        #expect(matcher.bestMatches(for: "rain").map(\.id) == ids)
    }

    @Test(arguments: [0, 1, 2, 5])
    func `limit is respected`(limit: Int) {
        let matches = ComposerCorpus.matcher.bestMatches(for: "k", limit: limit)
        #expect(matches.count == min(limit, 3))
    }
}

/// Builds a `SongRecord` from ChordPro text without a library.
enum TestSongs {
    static func record(source: String, id: SongID, path: String = "songs/song.cho") throws
        -> SongRecord
    {
        let (document, diagnostics) = ChordProParser.parse(source)
        return SongRecord(
            id: id,
            relativePath: path,
            source: source,
            document: document,
            diagnostics: diagnostics,
            sidecar: Sidecar(id: id, createdAt: .distantPast, updatedAt: .distantPast),
        )
    }
}
