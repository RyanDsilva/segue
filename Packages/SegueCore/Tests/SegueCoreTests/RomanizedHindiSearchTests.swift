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
        ("mein", "mei"),
        ("main", "mai"),
        ("nahin", "nahi"),
        ("nahi", "nahi"),
        ("kyun", "kyu"),
        ("kyoon", "kyu"),
        ("zindagi", "jindagi"),
        ("jindagee", "jindagi"),
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

    @Test
    func `normalizer keeps word boundaries and strips punctuation`() {
        #expect(RomanNormalizer.normalize("Tum Hi Ho, (Pyaar!) hain...") == "tum hi ho pyar hai")
        #expect(RomanNormalizer.normalize("  ") == "")
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

    @Test(arguments: [
        ("river", ["River Song"]),
        ("the", ["River Song", "Morning Light"]),
        ("love", ["Morning Light"]),
        ("morning light", ["Morning Light"]),
        ("willow", ["River Song"]),
        ("fixtures", ["River Song"]),
        ("with", []),
    ])
    func `english queries are unaffected by normalization`(
        query: String,
        expected: [String],
    ) async throws {
        let (lib, store) = try await Self.fixtureLibrary()
        _ = lib
        #expect(try await Set(store.search(query: query).titles) == Set(expected))
    }

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
