import ChordPro
import Foundation
import Library
import Support
import Testing

/// `SongFilter` (phase 2, unit D): typed tokens in the search field ("ready, upbeat, key G")
/// become tag, proficiency and key constraints; the rest goes to the text search.
struct SongFilterTests {
    private static let knownTags = ["Upbeat", "crowd pleaser", "ballad", "Hindi"]

    struct ParseCase: CustomTestStringConvertible, Sendable {
        var query: String
        var text: String
        var tags: Set<String>
        var levels: Set<Proficiency>
        var key: String?

        init(
            _ query: String,
            text: String,
            tags: Set<String>,
            levels: Set<Proficiency>,
            key: String?,
        ) {
            self.query = query
            self.text = text
            self.tags = tags
            self.levels = levels
            self.key = key
        }

        var testDescription: String {
            "“\(query)”"
        }
    }

    @Test(arguments: [
        ParseCase("ready, upbeat, key G", text: "", tags: ["Upbeat"], levels: [.ready], key: "G"),
        ParseCase("harbour", text: "harbour", tags: [], levels: [], key: nil),
        ParseCase("pro ballad lights", text: "lights", tags: ["ballad"], levels: [.pro], key: nil),
        ParseCase("#UPBEAT  key:am", text: "", tags: ["Upbeat"], levels: [], key: "Am"),
        ParseCase(
            "crowd pleaser learning",
            text: "",
            tags: ["crowd pleaser"],
            levels: [.learning],
            key: nil,
        ),
        ParseCase("crowd, pleaser", text: "crowd pleaser", tags: [], levels: [], key: nil),
        ParseCase("key", text: "key", tags: [], levels: [], key: nil),
        ParseCase("key lime pie", text: "key lime pie", tags: [], levels: [], key: nil),
        ParseCase("key f#m tum hi ho", text: "tum hi ho", tags: [], levels: [], key: "F#m"),
        ParseCase("#pro", text: "#pro", tags: [], levels: [], key: nil),
        ParseCase("ready pro", text: "", tags: [], levels: [.ready, .pro], key: nil),
        ParseCase("", text: "", tags: [], levels: [], key: nil),
    ])
    func `parse splits tokens from free text`(_ example: ParseCase) {
        let filter = SongFilter.parse(example.query, knownTags: Self.knownTags)
        #expect(filter.text == example.text)
        #expect(filter.tags == example.tags)
        #expect(filter.proficiencies == example.levels)
        #expect(filter.key == example.key)
        let constrained = !example.tags.isEmpty || !example.levels.isEmpty || example.key != nil
        #expect(filter.hasConstraints == constrained)
    }

    @Test
    func `unknown tags stay free text`() {
        let filter = SongFilter.parse("upbeat jazz", knownTags: ["Upbeat"])
        #expect(filter.tags == ["Upbeat"])
        #expect(filter.text == "jazz")
    }

    @Test
    func `tags must all be present, case-insensitively`() {
        let song = Self.song(tags: ["Upbeat", "Crowd  Pleaser"])
        #expect(SongFilter(tags: ["upbeat"]).matches(song))
        #expect(SongFilter(tags: ["UPBEAT", "crowd pleaser"]).matches(song))
        #expect(!SongFilter(tags: ["upbeat", "ballad"]).matches(song))
        #expect(SongFilter().matches(song))
    }

    @Test
    func `proficiency matches any listed level and never an unrated song`() {
        let ready = Self.song(proficiency: .ready)
        let unrated = Self.song()
        #expect(SongFilter(proficiencies: [.ready, .pro]).matches(ready))
        #expect(!SongFilter(proficiencies: [.pro]).matches(ready))
        #expect(!SongFilter(proficiencies: [.learning, .ready, .pro]).matches(unrated))
        #expect(SongFilter().matches(unrated))
    }

    @Test
    func `key matches the declared key, enharmonics included`() {
        let gFlat = Self.song(source: "{key: Gb}\n[Gb]la [Db]la\n")
        #expect(SongFilter(key: "Gb").matches(gFlat))
        #expect(SongFilter(key: "F#").matches(gFlat))
        #expect(!SongFilter(key: "F#m").matches(gFlat))
        #expect(!SongFilter(key: "G").matches(gFlat))
    }

    @Test
    func `key falls back to the detected key`() {
        let detected = Self.song(source: "[Am]one [Dm]two [E]three [Am]four [Am]five\n")
        #expect(SongFilter(key: "Am").matches(detected))
        #expect(!SongFilter(key: "C").matches(detected))
        let noChords = Self.song(source: "just words\n")
        #expect(!SongFilter(key: "C").matches(noChords))
    }

    @Test
    func `constraints combine`() {
        let song = Self.song(
            source: "{key: G}\n[G]la\n",
            tags: ["upbeat"],
            proficiency: .pro,
        )
        let filter = SongFilter.parse("pro upbeat key g", knownTags: ["upbeat"])
        #expect(filter.matches(song))
        #expect(!SongFilter.parse("ready upbeat key g", knownTags: ["upbeat"]).matches(song))
    }

    private static func song(
        source: String = "{title: Test}\n",
        tags: [String] = [],
        proficiency: Proficiency? = nil,
    ) -> SongRecord {
        let id = SongID(ULID(milliseconds: 1, randomness: Array(repeating: 7, count: 10)))
        let (document, diagnostics) = ChordProParser.parse(source)
        let date = Date(timeIntervalSince1970: 0)
        return SongRecord(
            id: id,
            relativePath: "songs/test.cho",
            source: source,
            document: document,
            diagnostics: diagnostics,
            sidecar: Sidecar(
                id: id,
                tags: tags,
                proficiency: proficiency,
                createdAt: date,
                updatedAt: date,
            ),
        )
    }
}
