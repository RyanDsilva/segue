import Foundation
import Library
import Testing

/// Fixture songs: original, licence-free text written for these tests. Hindi in Latin
/// script with deliberately inconsistent spellings, plus two English songs.
enum RomanizedHindiFixtures {
    static let songs = [
        """
        {title: Pyaar Ka Safar}
        {artist: Fixture Band}
        {key: G}

        {start_of_verse}
        [G]Dil mein tera [C]pyaar hai
        [D]Raaste lambe, [G]safar hai
        {end_of_verse}

        {start_of_chorus}
        [C]Chalte rahenge [G]hum
        {end_of_chorus}

        """,
        """
        {title: Kabhie Phir Milenge}
        {artist: Fixture Band}
        [Am]Kabhie phir milenge [F]yahin
        [C]Yaad rakhna [G]mujhe

        """,
        """
        {title: Deewana Dil}
        {artist: Test Singer}
        [D]Yeh dill deewana hain
        [A]Nahin maanta kabhi

        """,
        """
        {title: River Song}
        {artist: The Fixtures}
        [G]Down by the river where the [C]willows grow

        """,
        """
        {title: Morning Light}
        [E]I love the morning light, it [A]shines on me
        Through the pine and fern

        """,
    ]
}

/// Romanized-Hindi tolerant search through the real store, plus the one unit table for
/// `RomanNormalizer` (docs/phases/0-walking-skeleton.md, "Romanized Hindi search").
struct RomanizedHindiSearchTests {
    @Test(arguments: [
        ("Pyaar", "pyar"),
        ("pyar", "pyar"),
        ("dill", "dil"),
        ("Dil", "dil"),
        ("deewana", "divana"),
        ("diwana", "divana"),
        ("kabhi", "kabi"),
        ("kabhie", "kabi"),
        ("kabhee", "kabi"),
        ("hain", "hai"),
        ("hai", "hai"),
        ("mein", "mai"),
        ("main", "mai"),
        ("nahin", "nahi"),
        ("nahi", "nahi"),
        ("kyun", "kyu"),
        ("kyoon", "kyu"),
        ("zindagi", "jindagi"),
        ("jindagee", "jindagi"),
        ("phir", "fir"),
        ("fir", "fir"),
        ("phool", "ful"),
        ("fool", "ful"),
        ("pool", "pul"),
        ("accha", "acha"),
        ("achha", "acha"),
        ("bhool", "bul"),
        ("jaan", "jan"),
        ("Ẓindagī", "jindagi"),
        ("don't", "dont"),
        ("river", "river"),
    ])
    func `normalizer folds spelling variants`(input: String, expected: String) {
        #expect(RomanNormalizer.normalize(input) == expected)
    }

    /// R157 (P8-5 section 6.8): in normalized words of at most 4 letters, `ei` and `ae`
    /// fold to `ai`, so "tuj mai rab" finds "Tujh Mein Rab" and "ai dil" finds "Ae Dil".
    @Test(arguments: [
        ("mein", "mai"),
        ("main", "mai"),
        ("mai", "mai"),
        ("ae", "ai"),
        ("ai", "ai"),
        ("hae", "hai"),
        ("hai", "hai"),
        ("hain", "hai"),
        ("nei", "nai"),
        ("nai", "nai"),
        // Longer words keep their vowel pairs.
        ("deewana", "divana"),
        ("mehfil", "mehfil"),
        ("kaise", "kaise"),
        // English short words stay apart where they did before.
        ("pen", "pen"),
        ("pin", "pin"),
        ("ten", "ten"),
        ("tin", "tin"),
        ("aid", "aid"),
        ("they", "tey"),
    ])
    func `short words fold their vowel pairs`(input: String, expected: String) {
        #expect(RomanNormalizer.normalize(input) == expected)
    }

    @Test
    func `short-word folding finds tujh mein rab from tuj mai rab`() async throws {
        let lib = try TestLibrary()
        let store = try await lib.openStore()
        _ = try await store.createSong(source: "{title: Tujh Mein Rab Dikhta Hai}\n[G]La la\n")
        _ = try await store.createSong(source: "{title: Ae Dil Hai Mushkil}\n[Am]La la\n")
        #expect(try await store.search(query: "tuj mai rab").titles == ["Tujh Mein Rab Dikhta Hai"])
        #expect(try await store.search(query: "ai dil").titles == ["Ae Dil Hai Mushkil"])
    }

    @Test
    func `normalizer keeps word boundaries and strips punctuation`() {
        #expect(RomanNormalizer.normalize("Tum Hi Ho, (Pyaar!) hain...") == "tum hi ho pyar hai")
        #expect(RomanNormalizer.normalize("  ").isEmpty)
    }

    @Test(arguments: [
        // Query, expected titles in order (best match first).
        ("pyar", ["Pyaar Ka Safar"]),
        ("Pyaar", ["Pyaar Ka Safar"]),
        ("dil", ["Deewana Dil", "Pyaar Ka Safar"]),
        ("dill", ["Deewana Dil", "Pyaar Ka Safar"]),
        ("diwana", ["Deewana Dil"]),
        ("hain", ["Deewana Dil", "Pyaar Ka Safar"]),
        ("kabhi", ["Kabhie Phir Milenge", "Deewana Dil"]),
        ("kabhie", ["Kabhie Phir Milenge", "Deewana Dil"]),
        ("kabhee milenge", ["Kabhie Phir Milenge"]),
        ("fir milenge", ["Kabhie Phir Milenge"]),
        ("phir", ["Kabhie Phir Milenge"]),
        ("fir", ["Kabhie Phir Milenge"]),
        ("nahi manta", ["Deewana Dil"]),
        ("raste", ["Pyaar Ka Safar"]),
        // Edit-distance fallback over normalized titles and first lines.
        ("safer", ["Pyaar Ka Safar"]),
        ("milenga", ["Kabhie Phir Milenge"]),
    ])
    func `romanized hindi spelling variants find the expected songs`(
        query: String,
        expected: [String],
    ) async throws {
        let (lib, store) = try await Self.fixtureLibrary()
        _ = lib
        #expect(try await store.search(query: query).titles == expected)
    }

    /// The tier that found the first result (WS3 row 17, `Segue.Search.performed`).
    @Test(arguments: [
        ("Pyaar", SearchTier?.some(.exact)),
        ("pyar", .spellingVariant),
        ("dewana", .looseVariant),
        ("safer", .fuzzy),
        ("zzqx", nil),
    ])
    func `search reports the tier of its first result`(query: String, tier: SearchTier?)
        async throws
    {
        let (lib, store) = try await Self.fixtureLibrary()
        _ = lib
        let outcome = try await store.searchWithTier(query: query)
        #expect(outcome.firstTier == tier)
        #expect(try await outcome.records.titles == store.search(query: query).titles)
    }

    @Test(arguments: [
        ("river", ["River Song"]),
        ("the", ["River Song", "Morning Light"]),
        ("love", ["Morning Light"]),
        ("morning light", ["Morning Light"]),
        ("willow", ["River Song"]),
        ("fixtures", ["River Song"]),
        ("with", []),
        ("pine", ["Morning Light"]),
    ])
    func `english queries are unaffected by normalization`(
        query: String,
        expected: [String],
    ) async throws {
        let (lib, store) = try await Self.fixtureLibrary()
        _ = lib
        #expect(try await Set(store.search(query: query).titles) == Set(expected))
    }

    @Test(arguments: [
        ("dewana", "divana"),
        ("deewana", "divana"),
        ("diwana", "divana"),
        ("Deewaana", "divana"),
        ("mohabbat", "muhabat"),
        ("muhabbat", "muhabat"),
        ("jeevan", "jivan"),
        ("jevan", "jivan"),
        ("pyaasa", "pyasa"),
        ("deewane", "divani"),
        // Short words keep their vowels: distinct words in both languages.
        ("mere", "mere"),
        ("meri", "meri"),
        ("pen", "pen"),
        ("pin", "pin"),
        ("tu", "tu"),
        ("to", "to"),
    ])
    func `the loose form folds vowel quality in longer words`(input: String, expected: String) {
        #expect(RomanNormalizer.loose(input) == expected)
    }

    @Test
    func `the loose form leaves normalize unchanged`() {
        #expect(RomanNormalizer.normalize("dewana deewana") == "devana divana")
        #expect(RomanNormalizer.normalize("river") == "river")
    }

    /// e/ee/i and o/oo/u spellings of one word find each other, whichever is in the title
    /// and whichever is typed: library search, the builder and quick search all go through
    /// `LibraryStore.search`.
    @Test(arguments: ["dewana", "deewana", "diwana", "Deewaana", "dewan", "DIWANA"])
    func `e ee and i spellings all find each other`(query: String) async throws {
        let lib = try TestLibrary()
        let store = try await lib.openStore()
        for source in Self.vowelFixtures {
            _ = try await store.createSong(source: source)
        }
        let titles = try await store.search(query: query).titles
        #expect(Set(titles.prefix(3)) == ["Dewana Hua", "Deewana Dil", "Diwana Mastana"])
        #expect(!titles.contains("Lever Pulls"))
    }

    @Test(arguments: ["mohabbat", "muhabbat", "mohabat", "muhabat"])
    func `o oo and u spellings all find each other`(query: String) async throws {
        let lib = try TestLibrary()
        let store = try await lib.openStore()
        for source in Self.vowelFixtures {
            _ = try await store.createSong(source: source)
        }
        #expect(try await Set(store.search(query: query).titles) == [
            "Mohabbat Hai", "Muhabbat Ki Raat",
        ])
    }

    /// The exact spelling ranks before its loose variants.
    @Test
    func `exact spellings rank before loose variants`() async throws {
        let lib = try TestLibrary()
        let store = try await lib.openStore()
        for source in Self.vowelFixtures {
            _ = try await store.createSong(source: source)
        }
        #expect(try await store.search(query: "dewana").titles.first == "Dewana Hua")
        #expect(try await store.search(query: "diwana").titles.first == "Diwana Mastana")
        #expect(try await store.search(query: "muhabbat").titles.first == "Muhabbat Ki Raat")
    }

    static let vowelFixtures = [
        "{title: Dewana Hua}\n[G]Dil dewana hua\n",
        "{title: Deewana Dil}\n[D]Yeh dil deewana\n",
        "{title: Diwana Mastana}\n[Am]Diwana mastana\n",
        "{title: Mohabbat Hai}\n[C]Mohabbat hai yahi\n",
        "{title: Muhabbat Ki Raat}\n[F]Muhabbat ki raat\n",
        "{title: Lever Pulls}\n[E]Pull the lever down\n",
    ]

    @Test
    func `an empty query lists every song by title`() async throws {
        let (lib, store) = try await Self.fixtureLibrary()
        _ = lib
        #expect(try await store.search(query: "  ").titles == [
            "Deewana Dil", "Kabhie Phir Milenge", "Morning Light", "Pyaar Ka Safar", "River Song",
        ])
    }

    @Test
    func `rebuilt index gives identical romanized results`() async throws {
        let (lib, store) = try await Self.fixtureLibrary()
        let queries = ["pyar", "dil", "hai", "kabhie", "diwana", "safer", "the", "love"]
        let before = try await queries.asyncMap { try await store.search(query: $0).map(\.id) }

        try FileManager.default.removeItem(at: lib.url(".segue/index.sqlite"))
        let relaunched = try await lib.openStore()
        let after = try await queries.asyncMap { try await relaunched.search(query: $0).map(\.id) }

        #expect(after == before)
    }

    private static func fixtureLibrary() async throws -> (TestLibrary, LibraryStore) {
        let lib = try TestLibrary()
        let store = try await lib.openStore()
        for source in RomanizedHindiFixtures.songs {
            _ = try await store.createSong(source: source)
        }
        return (lib, store)
    }
}
