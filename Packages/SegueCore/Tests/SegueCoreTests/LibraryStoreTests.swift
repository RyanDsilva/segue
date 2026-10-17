import Foundation
import Library
import Support
import Testing

/// Integration suite for `LibraryStore`: real files in a temp folder, real GRDB index, real
/// ChordPro parser (docs/phases/0-walking-skeleton.md, "Test strategy").
struct LibraryStoreTests {
    private static let wonderwall = """
    {title: Wonder Wall}
    {artist: Test Band}
    {key: Em}

    {start_of_verse}
    [Em7]Today is gonna be the [G]day
    {end_of_verse}

    """

    @Test
    func `create song writes cho and sidecar with expected bytes and is searchable`() async throws {
        let lib = try TestLibrary()
        let store = try await lib.openStore()

        let record = try await store.createSong(source: Self.wonderwall)

        #expect(record.relativePath == "songs/wonder-wall.cho")
        #expect(try lib.read("songs/wonder-wall.cho") == Self.wonderwall)
        let stamp = "2026-01-01T00:00:00.000Z"
        #expect(
            try lib.read("songs/wonder-wall.segue.json")
                == TestLibrary.expectedSidecar(id: record.id, created: stamp, updated: stamp),
        )
        #expect(record.sidecar.createdAt == lib.clock.now())
        #expect(record.readOnly == nil)
        #expect(lib.exists(".segue/index.sqlite"))

        #expect(try await store.search(query: "gonna").map(\.id) == [record.id])
        #expect(try await store.search(query: "wonder").map(\.id) == [record.id])
        #expect(try await store.search(query: "test band").map(\.id) == [record.id])
        #expect(try await store.search(query: "nothing like this").isEmpty)

        // Relaunch: same identity, same text, nothing re-added.
        let reopened = try await lib.openStore()
        let reloaded = try #require(try await reopened.song(id: record.id))
        #expect(reloaded == record)
        #expect(try await reopened.refresh() == RefreshSummary())
    }

    @Test
    func `update song keeps id and file name, bumps updatedAt and reindexes`() async throws {
        let lib = try TestLibrary()
        let store = try await lib.openStore()
        let created = try await store.createSong(source: Self.wonderwall)

        lib.clock.advance(by: 90)
        let edited = Self.wonderwall
            .replacingOccurrences(of: "Wonder Wall", with: "Renamed Song")
            .replacingOccurrences(of: "gonna", with: "surely")
        let updated = try await store.updateSong(id: created.id, source: edited)

        #expect(updated.id == created.id)
        #expect(updated.relativePath == "songs/wonder-wall.cho")
        #expect(updated.document.metadata.title == "Renamed Song")
        #expect(updated.sidecar.createdAt == created.sidecar.createdAt)
        #expect(updated.sidecar.updatedAt == lib.clock.now())
        #expect(try lib.read("songs/wonder-wall.cho") == edited)
        #expect(try await store.search(query: "gonna").isEmpty)
        #expect(try await store.search(query: "surely").map(\.id) == [created.id])
        #expect(try await store.search(query: "renamed").map(\.id) == [created.id])
    }

    @Test
    func `external edit, add and delete are picked up by refresh`() async throws {
        let lib = try TestLibrary()
        let store = try await lib.openStore()
        let first = try await store.createSong(source: "{title: First}\nOld words here\n")
        let second = try await store.createSong(source: "{title: Second}\nStays put\n")

        try lib.write("{title: First}\nBrand new lyric line\n", to: "songs/first.cho")
        try lib.write("{title: Third}\nAdded outside the app\n", to: "songs/third.cho")
        try FileManager.default.removeItem(at: lib.url("songs/second.cho"))

        let summary = try await store.refresh()

        #expect(summary == RefreshSummary(added: 1, updated: 1, removed: 1))
        #expect(try await store.search(query: "old words").isEmpty)
        #expect(try await store.search(query: "brand new").map(\.id) == [first.id])
        #expect(try await store.song(id: second.id) == nil)
        #expect(try await store.search(query: "stays").isEmpty)
        #expect(try await store.allSongs().titles == ["First", "Third"])
        // The deleted song's sidecar is left alone (never delete user data).
        #expect(lib.exists("songs/second.segue.json"))
        #expect(try await store.refresh() == RefreshSummary())
    }

    @Test
    func `orphan cho gets a sidecar with a stable ULID`() async throws {
        let lib = try TestLibrary()
        try lib.write("{title: Orphan}\nNo sidecar yet\n", to: "songs/orphan.cho")

        let store = try await lib.openStore()
        let songs = try await store.allSongs()

        let orphan = try #require(songs.first)
        #expect(songs.count == 1)
        #expect(orphan.relativePath == "songs/orphan.cho")
        #expect(lib.exists("songs/orphan.segue.json"))
        let stamp = "2026-01-01T00:00:00.000Z"
        #expect(
            try lib.read("songs/orphan.segue.json")
                == TestLibrary.expectedSidecar(id: orphan.id, created: stamp, updated: stamp),
        )
        #expect(try lib.read("songs/orphan.cho") == "{title: Orphan}\nNo sidecar yet\n")

        let reopened = try await lib.openStore()
        #expect(try await reopened.allSongs().map(\.id) == [orphan.id])
    }

    @Test
    func `duplicate titles get de-duplicated slugs and distinct stable ids`() async throws {
        let lib = try TestLibrary()
        let store = try await lib.openStore()
        let source = "{title: Same Name}\nWords\n"

        let records = try await [
            store.createSong(source: source),
            store.createSong(source: source),
            store.createSong(source: source),
            store.createSong(source: "No title at all\n"),
            store.createSong(source: "{title: Kya Baat Hai!}\nWah\n"),
        ]

        #expect(records.map(\.relativePath) == [
            "songs/same-name.cho",
            "songs/same-name-2.cho",
            "songs/same-name-3.cho",
            "songs/untitled.cho",
            "songs/kya-baat-hai.cho",
        ])
        #expect(Set(records.map(\.id)).count == records.count)

        let reopened = try await lib.openStore()
        for record in records {
            #expect(try await reopened.song(id: record.id)?.relativePath == record.relativePath)
        }
    }

    @Test
    func `renaming the file pair externally keeps the song id`() async throws {
        let lib = try TestLibrary()
        let store = try await lib.openStore()
        let record = try await store.createSong(source: "{title: Mover}\nI travel\n")

        try lib.fileSystem.moveItem(
            from: lib.url("songs/mover.cho"),
            to: lib.url("songs/moved.cho"),
        )
        try lib.fileSystem.moveItem(
            from: lib.url("songs/mover.segue.json"),
            to: lib.url("songs/moved.segue.json"),
        )
        let summary = try await store.refresh()

        #expect(summary == RefreshSummary(updated: 1))
        #expect(try await store.song(id: record.id)?.relativePath == "songs/moved.cho")
        #expect(try await store.search(query: "travel").map(\.id) == [record.id])
    }

    @Test
    func `finder duplicate of a song gets a new id and the original keeps its id`() async throws {
        let lib = try TestLibrary()
        let store = try await lib.openStore()
        let original = try await store.createSong(source: "{title: Original}\nCopy me\n")

        try lib.write(lib.read("songs/original.cho"), to: "songs/original-copy.cho")
        try lib.write(lib.read("songs/original.segue.json"), to: "songs/original-copy.segue.json")
        let summary = try await store.refresh()

        #expect(summary == RefreshSummary(added: 1))
        let songs = try await store.allSongs()
        #expect(songs.count == 2)
        #expect(try await store.song(id: original.id)?.relativePath == "songs/original.cho")
        let copy = try #require(songs.first { $0.id != original.id })
        #expect(copy.relativePath == "songs/original-copy.cho")
        #expect(try lib.read("songs/original-copy.segue.json").contains(copy.id.description))

        let reopened = try await lib.openStore()
        #expect(try await Set(reopened.allSongs().map(\.id)) == [original.id, copy.id])
    }

    @Test
    func `deleting the index and rebuilding yields identical search results`() async throws {
        let lib = try TestLibrary()
        let store = try await lib.openStore()
        for source in RomanizedHindiFixtures.songs {
            _ = try await store.createSong(source: source)
        }
        let queries = ["dil", "pyar", "the river", "kabhie", "hai", "safer", "zzz", ""]
        let before = try await queries.asyncMap { try await store.search(query: $0).map(\.id) }

        // Delete index.sqlite (+ WAL/SHM) behind the app's back, then relaunch.
        try await store.rebuildIndex() // also exercises the explicit rebuild path
        let afterRebuild = try await queries
            .asyncMap { try await store.search(query: $0).map(\.id) }
        for suffix in ["", "-wal", "-shm"] where lib.exists(".segue/index.sqlite\(suffix)") {
            try FileManager.default.removeItem(at: lib.url(".segue/index.sqlite\(suffix)"))
        }
        let relaunched = try await lib.openStore()
        let afterDelete = try await queries.asyncMap {
            try await relaunched.search(query: $0).map(\.id)
        }

        #expect(before.contains { !$0.isEmpty })
        #expect(afterRebuild == before)
        #expect(afterDelete == before)
    }

    @Test
    func `corrupt index file is dropped and rebuilt from files`() async throws {
        let lib = try TestLibrary()
        let record: SongRecord
        do {
            let store = try await lib.openStore()
            record = try await store.createSong(source: Self.wonderwall)
        }

        for suffix in ["-wal", "-shm"] where lib.exists(".segue/index.sqlite\(suffix)") {
            try FileManager.default.removeItem(at: lib.url(".segue/index.sqlite\(suffix)"))
        }
        try lib.write("this is not a sqlite database", to: ".segue/index.sqlite")

        let relaunched = try await lib.openStore()
        #expect(try await relaunched.search(query: "gonna").map(\.id) == [record.id])
    }

    @Test
    func `older sidecar migrates forward on read and is written back on next save`() async throws {
        let lib = try TestLibrary()
        let id = SongID(lib.ids.next())
        // Version 0: pre-versioned sidecar without schemaVersion, tags or displayPrefs.
        let legacy = """
        {"id": "\(id)", "notes": "capo feels better", "createdAt": "2025-06-01T10:00:00Z"}
        """
        try lib.write("{title: Legacy}\nOld but gold\n", to: "songs/legacy.cho")
        try lib.write(legacy, to: "songs/legacy.segue.json")

        let store = try await lib.openStore()
        let record = try #require(try await store.song(id: id))

        #expect(record.readOnly == nil)
        #expect(record.sidecar.schemaVersion == Sidecar.currentSchemaVersion)
        #expect(record.sidecar.notes == "capo feels better")
        #expect(record.sidecar.tags.isEmpty)
        #expect(record.sidecar.createdAt == Date(timeIntervalSince1970: 1_748_772_000))
        #expect(record.sidecar.updatedAt == record.sidecar.createdAt)
        // Reading never rewrites; the migrated form lands on the next save.
        #expect(try lib.read("songs/legacy.segue.json") == legacy)

        _ = try await store.updateSong(id: id, source: "{title: Legacy}\nOld but gold, again\n")
        let saved = try lib.read("songs/legacy.segue.json")
        #expect(saved.contains("\"schemaVersion\" : \(Sidecar.currentSchemaVersion)"))
        #expect(saved.contains("\"notes\" : \"capo feels better\""))
        #expect(saved.contains("\"createdAt\" : \"2025-06-01T10:00:00.000Z\""))
        #expect(saved.contains("\"updatedAt\" : \"2026-01-01T00:00:00.000Z\""))
    }

    @Test
    func `newer sidecar opens read-only, stays searchable and is never rewritten`() async throws {
        let lib = try TestLibrary()
        let id = SongID(lib.ids.next())
        let future = """
        {
          "schemaVersion": 99,
          "id": "\(id)",
          "tags": ["wedding"],
          "createdAt": "2030-01-01T00:00:00Z",
          "updatedAt": "2030-01-01T00:00:00Z",
          "hologramLighting": {"color": "teal"}
        }
        """
        try lib.write("{title: From The Future}\nTime travel lyrics\n", to: "songs/future.cho")
        try lib.write(future, to: "songs/future.segue.json")

        let store = try await lib.openStore()
        let record = try #require(try await store.song(id: id))

        let reason = ReadOnlyReason.newerSchema(found: 99, supported: Sidecar.currentSchemaVersion)
        #expect(record.readOnly == reason)
        #expect(record.sidecar.tags == ["wedding"])
        #expect(try await store.search(query: "time travel").map(\.id) == [id])
        await #expect(throws: LibraryError.readOnly(id, reason)) {
            try await store.updateSong(id: id, source: "{title: Overwrite}\n")
        }

        try await store.refresh()
        try await store.rebuildIndex()
        _ = try await lib.openStore()
        #expect(try lib.read("songs/future.segue.json") == future)
        #expect(try lib
            .read("songs/future.cho") == "{title: From The Future}\nTime travel lyrics\n")
    }

    @Test
    func `corrupted sidecar keeps the song usable read-only and leaves the file alone`(
    ) async throws {
        let lib = try TestLibrary()
        let store = try await lib.openStore()
        let healthy = try await store.createSong(source: "{title: Healthy}\nAll good\n")
        let damaged = try await store.createSong(source: "{title: Damaged}\nStill singable\n")
        let garbage = "{\"id\": \"\(damaged.id)\", \"schemaVersion\": 1, \"tags\": [oops"
        try lib.write(garbage, to: "songs/damaged.segue.json")

        try await store.refresh()
        let reopened = try await lib.openStore()

        for current in [store, reopened] {
            let record = try #require(try await current.song(id: damaged.id))
            guard case .unreadableSidecar = record.readOnly else {
                Issue
                    .record(
                        "expected unreadableSidecar, got \(String(describing: record.readOnly))",
                    )
                return
            }
            #expect(record.source == "{title: Damaged}\nStill singable\n")
            #expect(try await current.search(query: "singable").map(\.id) == [damaged.id])
            #expect(try await current.song(id: healthy.id)?.readOnly == nil)
            await #expect(throws: LibraryError.self) {
                try await current.updateSong(id: damaged.id, source: "{title: Fixed}\n")
            }
        }
        #expect(try lib.read("songs/damaged.segue.json") == garbage)
    }

    @Test
    func `hindi lyric text round trips unchanged through parse, save and reload`() async throws {
        let lib = try TestLibrary()
        let store = try await lib.openStore()
        let source = RomanizedHindiFixtures.songs[0]

        let record = try await store.createSong(source: source)
        let reopened = try await lib.openStore()
        let reloaded = try #require(try await reopened.song(id: record.id))

        #expect(try lib.read(record.relativePath) == source)
        #expect(reloaded.source == source)
        #expect(reloaded.document == record.document)
        #expect(reloaded.document.plainLyrics.contains("Dil mein tera pyaar hai"))
    }

    @Test
    func `operations before open throw notOpen`() async throws {
        let lib = try TestLibrary()
        let store = LibraryStore(fileSystem: lib.fileSystem, clock: lib.clock, ids: lib.ids)
        await #expect(throws: LibraryError.notOpen) { try await store.allSongs() }
        await #expect(throws: LibraryError.notOpen) { try await store.search(query: "x") }
        await #expect(throws: LibraryError.notOpen) { try await store.createSong(source: "") }
    }
}

extension Array {
    func asyncMap<T>(_ transform: (Element) async throws -> T) async rethrows -> [T] {
        var result: [T] = []
        for element in self {
            try await result.append(transform(element))
        }
        return result
    }
}
