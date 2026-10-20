import Foundation
import Library
import Support
import Testing

/// Smart filters (P3-6, R72) on a real library folder: files under `filters/`, reload,
/// Trash, versioning, and every condition kind evaluated against real songs and the real
/// play projection.
struct SmartFilterTests {
    private static func store(_ lib: TestLibrary) async throws -> SmartFilterStore {
        let store = SmartFilterStore(fileSystem: lib.fileSystem, clock: lib.clock, ids: lib.ids)
        try await store.load(root: lib.root)
        return store
    }

    // MARK: Files

    @Test
    func `create edit and delete are files that survive a reload`() async throws {
        let lib = try TestLibrary()
        let store = try await Self.store(lib)
        var conditions = SmartFilterConditions(anyTags: ["upbeat", "crowd pleaser"])
        conditions.length = SmartFilterRange(min: 120, max: 300)
        conditions.neverPlayed = true
        let created = try await store.create(name: "Openers", conditions: conditions)

        #expect(lib.exists("filters/openers.filter.json"))
        let json = try lib.read("filters/openers.filter.json")
        #expect(json.contains(#""schemaVersion" : 1"#))
        #expect(json.contains(#""neverPlayed" : true"#))
        #expect(!json.contains("lastPlayed"))
        #expect(!json.lowercased().contains("energy"))

        lib.clock.advance(by: 60)
        try await store.rename(created.id, to: "Big openers")
        conditions.neverPlayed = false
        conditions.proficiencies = [.pro]
        let updated = try await store.update(created.id, conditions: conditions)
        #expect(updated.updatedAt > created.updatedAt)
        #expect(!lib.exists("filters/big-openers.filter.json")) // the slug stays

        let reloaded = try await Self.store(lib)
        #expect(await reloaded.all() == [updated])
        #expect(await reloaded.filter(id: created.id)?.name == "Big openers")

        let receipt = try await reloaded.delete(created.id)
        #expect(!lib.exists("filters/openers.filter.json"))
        #expect(lib.trashedNames() == ["openers.filter.json"])
        #expect(await reloaded.all().isEmpty)
        #expect(try await Self.store(lib).all().isEmpty)

        let restored = try await reloaded.restore(receipt)
        #expect(restored == updated)
        #expect(lib.exists("filters/openers.filter.json"))
    }

    @Test
    func `names that slug alike get numbered files`() async throws {
        let lib = try TestLibrary()
        let store = try await Self.store(lib)
        try await store.create(name: "Ready")
        try await store.create(name: "ready!")
        try lib.write("not mine", to: "filters/ready-3.filter.json")
        let third = try await store.create(name: "Ready")
        #expect(lib.exists("filters/ready.filter.json"))
        #expect(lib.exists("filters/ready-2.filter.json"))
        #expect(await store.fileURL(for: third.id) == lib.url("filters/ready-4.filter.json"))
    }

    @Test
    func `files edited outside the app are picked up on reload`() async throws {
        let lib = try TestLibrary()
        let store = try await Self.store(lib)
        try lib.write("""
        {"id": "01JAAAAAAAAAAAAAAAAAAAAAAA", "name": "Hand made", "schemaVersion": 1,
         "createdAt": "2026-01-01T00:00:00Z", "updatedAt": "2026-01-01T00:00:00Z",
         "conditions": {"keys": ["G"]}}
        """, to: "filters/hand-made.filter.json")
        try lib.write("{ nope", to: "filters/broken.filter.json")
        try lib.write("ignored", to: "filters/readme.txt")

        let issues = try await store.reloadFromDisk()

        #expect(issues.map(\.relativePath) == ["filters/broken.filter.json"])
        #expect(await store.all().map(\.name) == ["Hand made"])
        #expect(await store.all().first?.conditions == SmartFilterConditions(keys: ["G"]))
        #expect(try lib.read("filters/broken.filter.json") == "{ nope")
    }

    @Test
    func `a newer schema loads read-only and is never rewritten`() async throws {
        let lib = try TestLibrary()
        let text = """
        {"id": "01JAAAAAAAAAAAAAAAAAAAAAAA", "name": "Future", "schemaVersion": 7,
         "conditions": {"allTags": ["cover"], "mood": "sunny"}}
        """
        try lib.write(text, to: "filters/future.filter.json")
        let store = try await Self.store(lib)
        let filter = try #require(await store.all().first)

        #expect(filter.readOnly == .newerSchema(found: 7, supported: 1))
        #expect(filter.conditions.allTags == ["cover"])
        await #expect(throws: SmartFilterError.readOnly(filter.id, .newerSchema(
            found: 7,
            supported: 1,
        ))) {
            try await store.rename(filter.id, to: "Now")
        }
        #expect(try lib.read("filters/future.filter.json") == text)
    }

    @Test
    func `a file without a schema version migrates in memory only`() async throws {
        let lib = try TestLibrary()
        let text = """
        {"id": "01JAAAAAAAAAAAAAAAAAAAAAAA", "name": "Old",
         "createdAt": "2026-01-01T00:00:00Z", "updatedAt": "2026-01-01T00:00:00Z"}
        """
        try lib.write(text, to: "filters/old.filter.json")
        let store = try await Self.store(lib)
        let filter = try #require(await store.all().first)
        #expect(filter.readOnly == nil)
        #expect(filter.conditions == SmartFilterConditions())
        #expect(try lib.read("filters/old.filter.json") == text)
        try await store.rename(filter.id, to: "Older")
        #expect(try lib.read("filters/old.filter.json").contains(#""schemaVersion" : 1"#))
    }

    // MARK: Conditions

    private struct Spec {
        var title: String
        var directives: String
        var tags: [String]
        var level: Proficiency?

        init(
            _ title: String,
            _ directives: String,
            _ tags: [String],
            _ level: Proficiency? = .learning,
        ) {
            self.title = title
            self.directives = directives
            self.tags = tags
            self.level = level
        }
    }

    private struct Fixture {
        let lib: TestLibrary
        let store: LibraryStore
        let songs: [String: SongRecord]
        let stats: [SongID: PlayStats]

        func titles(_ conditions: SmartFilterConditions) async throws -> [String] {
            let filter = SmartFilter(
                id: SmartFilterID(lib.ids.next()),
                name: "t",
                conditions: conditions,
            )
            return try await filter.songs(
                in: store.allSongs(),
                playStats: stats,
            ).titles
        }
    }

    /// Five songs: tags, proficiency, key, tempo and length vary; "Unknown" has no tempo,
    /// no length and no key; plays on two days.
    private static func library() async throws -> Fixture {
        let lib = try TestLibrary()
        let store = try await lib.openStore()
        let specs = [
            Spec("Alpha", "{key: G}\n{tempo: 120}\n{duration: 3:30}", ["upbeat", "cover"], .pro),
            Spec("Bravo", "{key: Am}\n{tempo: 72}\n{duration: 5:10}", ["Ballad"], .ready),
            Spec("Charlie", "{key: Gb}\n{tempo: 140}\n{duration: 2:00}", ["upbeat", "original"]),
            Spec("Delta", "{key: C}\n{tempo: 96}\n{duration: 4:00}", ["crowd pleaser"], nil),
            Spec("Unknown", "", [], .ready),
        ]
        var songs: [String: SongRecord] = [:]
        for spec in specs {
            let song = try await store.createSong(
                source: "{title: \(spec.title)}\n\(spec.directives)\nLa\n",
            )
            songs[spec.title] = try await store.updateMetadata(
                id: song.id,
                SongMetadata(tags: spec.tags, proficiency: spec.level),
            )
        }
        // Alpha and Bravo have been played.
        let alpha = try #require(songs["Alpha"]).id
        let bravo = try #require(songs["Bravo"]).id
        let show = lib.ids.next()
        let day = 86400.0
        let now = lib.clock.now()
        let plays = [
            PlayRecord(
                songId: alpha,
                showId: show,
                startedAt: now.addingTimeInterval(-2 * day),
                endedAt: now.addingTimeInterval(-2 * day + 200),
                fromRequest: false,
            ),
            PlayRecord(
                songId: bravo,
                showId: show,
                startedAt: now.addingTimeInterval(-214 * day),
                endedAt: now.addingTimeInterval(-214 * day + 200),
                fromRequest: false,
            ),
        ]
        try await store.replacePlays(forShow: show, with: plays)
        return try await Fixture(lib: lib, store: store, songs: songs, stats: store.playStats())
    }

    @Test
    func `every condition kind narrows the library`() async throws {
        let fix = try await Self.library()
        let all = ["Alpha", "Bravo", "Charlie", "Delta", "Unknown"]
        let cases: [(SmartFilterConditions, [String])] = [
            (SmartFilterConditions(), all),
            (SmartFilterConditions(allTags: ["UPBEAT", "cover"]), ["Alpha"]),
            (SmartFilterConditions(anyTags: ["ballad", "crowd  pleaser"]), ["Bravo", "Delta"]),
            (SmartFilterConditions(noneTags: ["upbeat"]), ["Bravo", "Delta", "Unknown"]),
            (SmartFilterConditions(proficiencies: [.ready, .pro]), ["Alpha", "Bravo", "Unknown"]),
            (SmartFilterConditions(keys: ["F#", "C"]), ["Charlie", "Delta"]), // enharmonic Gb
            (SmartFilterConditions(tempo: SmartFilterRange(min: 96, max: 120)), ["Alpha", "Delta"]),
            (SmartFilterConditions(tempo: SmartFilterRange(max: 100)), ["Bravo", "Delta"]),
            (
                SmartFilterConditions(length: SmartFilterRange(min: 210)),
                ["Alpha", "Bravo", "Delta"],
            ),
            (
                SmartFilterConditions(length: SmartFilterRange(max: 240)),
                ["Alpha", "Charlie", "Delta"],
            ),
            (SmartFilterConditions(neverPlayed: true), ["Charlie", "Delta", "Unknown"]),
            (
                SmartFilterConditions(anyTags: ["upbeat"], neverPlayed: true),
                ["Charlie"],
            ),
        ]
        for (conditions, expected) in cases {
            #expect(try await fix.titles(conditions) == expected, "\(conditions)")
        }
    }

    @Test
    func `songs without a length or tempo never match those conditions`() async throws {
        let fix = try await Self.library()
        let wide = SmartFilterRange(min: 0, max: 100_000)
        #expect(try await !fix.titles(SmartFilterConditions(length: wide)).contains("Unknown"))
        #expect(try await !fix.titles(SmartFilterConditions(tempo: wide)).contains("Unknown"))
        // An open range is no condition at all.
        #expect(try await fix.titles(SmartFilterConditions(length: SmartFilterRange()))
            .contains("Unknown"))
    }

    @Test
    func `the store evaluates a saved filter by id`() async throws {
        let fix = try await Self.library()
        let filters = try await Self.store(fix.lib)
        let saved = try await filters.create(
            name: "Fresh",
            conditions: SmartFilterConditions(neverPlayed: true),
        )
        let songs = try await fix.store.allSongs()
        let matched = await filters.songs(matching: saved.id, in: songs, playStats: fix.stats)
        #expect(matched?.titles == ["Charlie", "Delta", "Unknown"])
        #expect(await filters.songs(matching: SmartFilterID(fix.lib.ids.next()), in: songs) == nil)
    }

    @Test
    func `phase 2 filters are unchanged by the new fields`() async throws {
        let fix = try await Self.library()
        let plain = SongFilter.parse("ready, key Am", knownTags: ["upbeat"])
        #expect(plain == SongFilter(text: "", proficiencies: [.ready], key: "Am"))
        #expect(try await fix.store.allSongs().filter(plain.matches).titles == ["Bravo"])
        #expect(!SongFilter().hasConstraints)
        #expect(SmartFilterConditions().compiled() == SongFilter())
    }

    @Test
    func `conditions count what is set`() {
        #expect(SmartFilterConditions().isEmpty)
        let conditions = SmartFilterConditions(
            allTags: ["a"],
            keys: ["G"],
            tempo: SmartFilterRange(min: 90),
            length: SmartFilterRange(),
            neverPlayed: true,
        )
        #expect(conditions.count == 4)
    }
}

extension SmartFilterTests {
    @Test
    func `essentials are a written key, a length and a tempo`() async throws {
        let fix = try await Self.library()
        let missing = try await fix.store.allSongs().map { song in
            "\(song.document.metadata.title ?? ""): "
                + SongEssentials.missing(in: song.document).map(\.rawValue).joined(separator: ",")
        }
        #expect(missing == [
            "Alpha: ",
            "Bravo: ",
            "Charlie: ",
            "Delta: ",
            "Unknown: key,length,tempo",
        ])
        let partial = try await fix.store.createSong(source: """
        {title: Partial}
        {key: Hm}
        {tempo: 90}
        [G]La [C]la [D]la [G]la

        """)
        // A key detected from the chords, or an invalid {key}, does not count.
        #expect(SongEssentials.missing(in: partial.document) == [.key, .length])
        let builtIn = SongFilter(missingEssentials: true)
        #expect(try await fix.store.allSongs().filter(builtIn.matches).titles == [
            "Partial",
            "Unknown",
        ])
    }
}

/// The < 50 ms budget for evaluating a smart filter over a 300-song library (P3-6). Named
/// `...PerformanceTests` so `make test-perf` runs it alone.
@Suite(.serialized)
struct SmartFilterPerformanceTests {
    @Test
    func `a smart filter over 300 songs evaluates in under 50 ms`() async throws {
        let lib = try TestLibrary()
        let store = try await lib.openStore()
        let keys = ["G", "Am", "C", "D", "Em", "F#m"]
        for number in 0 ..< 300 {
            let key = number.isMultiple(of: 7) ? "" : "{key: \(keys[number % keys.count])}\n"
            let song = try await store.createSong(source: """
            {title: Song \(number)}
            \(key){tempo: \(70 + number % 80)}
            {duration: \(2 + number % 4):\(10 + number % 50)}
            [G]Some [C]words [D]here [Em]and [Am]there
            [C]More [G]words [D]to [G]sing

            """)
            try await store.updateMetadata(id: song.id, SongMetadata(
                tags: number.isMultiple(of: 3) ? ["upbeat", "cover"] : ["ballad"],
                proficiency: Proficiency.allCases[number % 3],
            ))
        }
        let songs = try await store.allSongs()
        var stats: [SongID: PlayStats] = [:]
        for (offset, song) in songs.enumerated() where offset.isMultiple(of: 2) {
            stats[song.id] = PlayStats(
                timesPlayed: 1,
                lastPlayed: lib.clock.now().addingTimeInterval(-Double(offset) * 86400),
            )
        }
        let filter = SmartFilter(
            id: SmartFilterID(lib.ids.next()),
            name: "Everything",
            conditions: SmartFilterConditions(
                anyTags: ["upbeat", "ballad"],
                noneTags: ["original"],
                proficiencies: [.ready, .pro],
                keys: ["G", "Am", "C", "D"],
                tempo: SmartFilterRange(min: 60, max: 200),
                length: SmartFilterRange(min: 60, max: 600),
                neverPlayed: true,
            ),
        )
        let clock = ContinuousClock()
        var best = Duration.seconds(1)
        var count = 0
        for _ in 0 ..< 5 {
            let elapsed = clock.measure {
                count = filter.songs(in: songs, playStats: stats).count
            }
            best = min(best, elapsed)
        }
        #expect(count > 0)
        #expect(best < .milliseconds(50), "best of 5: \(best)")
    }
}
