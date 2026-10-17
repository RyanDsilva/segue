import Foundation
import Library
import Setlists
import Support
import Testing

/// Integration suite for `SetlistStore` on a real library folder, with song IDs coming from
/// a real `LibraryStore`.
struct SetlistStoreTests {
    @Test
    func `create, add, reorder and remove persist and reload`() async throws {
        let lib = try TestLibrary()
        let library = try await lib.openStore()
        let songs = try await ["Alpha", "Bravo", "Charlie", "Delta"].asyncMap { title in
            try await library.createSong(source: "{title: \(title)}\nLa la\n").id
        }
        let (store, issues) = try await lib.loadSetlists()
        #expect(issues.isEmpty)

        let created = try await store.create(name: "Friday Gig")
        for song in songs {
            try await store.addSong(song, to: created.id)
        }
        // Delta to the top, then Bravo (now index 2) after Charlie.
        try await store.move(in: created.id, fromOffsets: [3], toOffset: 0)
        try await store.move(in: created.id, fromOffsets: [2], toOffset: 4)
        let final = try await store.remove(in: created.id, atOffsets: [1])

        let expected = [songs[3], songs[2], songs[1]]
        #expect(final.entries.map(\.songId) == expected)
        #expect(lib.exists("setlists/friday-gig.setlist.json"))

        let (reloaded, reloadIssues) = try await lib.loadSetlists()
        #expect(reloadIssues.isEmpty)
        let setlist = try #require(await reloaded.setlist(id: created.id))
        #expect(setlist == final)
        #expect(setlist.name == "Friday Gig")
        #expect(setlist.schemaVersion == Setlist.currentSchemaVersion)
        for entry in setlist.entries {
            #expect(try await library.song(id: entry.songId) != nil)
        }
    }

    @Test
    func `setlist file has the expected bytes`() async throws {
        let lib = try TestLibrary()
        let (store, _) = try await lib.loadSetlists()
        let setlist = try await store.create(name: "Sangeet Night")
        let song = SongID(lib.ids.next())
        try await store.addSong(song, to: setlist.id)

        let saved = try #require(await store.setlist(id: setlist.id))
        let item = try #require(saved.entries.first?.itemId)
        // The test clock is frozen at 2026-01-01T00:00:00Z.
        let stamp = "2026-01-01T00:00:00.000Z"
        #expect(try lib.read("setlists/sangeet-night.setlist.json") == """
        {
          "createdAt" : "\(stamp)",
          "entries" : [
            {
              "itemId" : "\(item)",
              "songId" : "\(song)"
            }
          ],
          "id" : "\(setlist.id)",
          "name" : "Sangeet Night",
          "schemaVersion" : 2,
          "updatedAt" : "\(stamp)"
        }

        """)
    }

    @Test
    func `move matches SwiftUI onMove semantics for multiple offsets`() async throws {
        let lib = try TestLibrary()
        let (store, _) = try await lib.loadSetlists()
        let setlist = try await store.create(name: "Order")
        let songs = (0 ..< 5).map { _ in SongID(lib.ids.next()) }
        for song in songs {
            try await store.addSong(song, to: setlist.id)
        }

        let moved = try await store.move(in: setlist.id, fromOffsets: [0, 2], toOffset: 4)

        #expect(moved.entries.map(\.songId) == [songs[1], songs[3], songs[0], songs[2], songs[4]])
        await #expect(throws: SetlistError.invalidOffsets(setlist.id)) {
            try await store.move(in: setlist.id, fromOffsets: [7], toOffset: 0)
        }
        await #expect(throws: SetlistError.invalidOffsets(setlist.id)) {
            try await store.remove(in: setlist.id, atOffsets: [5])
        }
    }

    @Test
    func `same names get de-duplicated file names and all() sorts by name`() async throws {
        let lib = try TestLibrary()
        let (store, _) = try await lib.loadSetlists()
        let first = try await store.create(name: "Wedding")
        let second = try await store.create(name: "wedding")
        let third = try await store.create(name: "Acoustic Brunch")

        #expect(lib.exists("setlists/wedding.setlist.json"))
        #expect(lib.exists("setlists/wedding-2.setlist.json"))
        #expect(await store.all().map(\.id) == [third.id, first.id, second.id])

        let (reloaded, _) = try await lib.loadSetlists()
        #expect(await reloaded.all().map(\.id) == [third.id, first.id, second.id])
    }

    @Test
    func `corrupted setlist json is reported without losing the others`() async throws {
        let lib = try TestLibrary()
        let (store, _) = try await lib.loadSetlists()
        let good = try await store.create(name: "Good One")
        try await store.addSong(SongID(lib.ids.next()), to: good.id)
        let broken = "{\"id\": \"not closed"
        try lib.write(broken, to: "setlists/broken.setlist.json")
        try lib.write("[1, 2, 3]", to: "setlists/array.setlist.json")

        let (reloaded, issues) = try await lib.loadSetlists()

        #expect(issues.map(\.relativePath).sorted() == [
            "setlists/array.setlist.json",
            "setlists/broken.setlist.json",
        ])
        #expect(issues.allSatisfy { !$0.message.isEmpty })
        #expect(await reloaded.all().map(\.id) == [good.id])
        #expect(await reloaded.setlist(id: good.id)?.entries.count == 1)
        #expect(try lib.read("setlists/broken.setlist.json") == broken)

        // A new setlist never overwrites the unreadable file.
        _ = try await reloaded.create(name: "Broken")
        #expect(try lib.read("setlists/broken.setlist.json") == broken)
        #expect(lib.exists("setlists/broken-2.setlist.json"))
    }

    @Test
    func `newer setlist loads read-only and is never rewritten`() async throws {
        let lib = try TestLibrary()
        let id = SetlistID(lib.ids.next())
        let song = SongID(lib.ids.next())
        let future = """
        {"schemaVersion": 7, "id": "\(id)", "name": "Future Set",
         "entries": [{"songId": "\(song)", "cue": "lights"}, {"segue": true}]}
        """
        try lib.write(future, to: "setlists/future.setlist.json")

        let (store, issues) = try await lib.loadSetlists()
        let setlist = try #require(await store.setlist(id: id))

        #expect(issues.isEmpty)
        let reason = ReadOnlyReason.newerSchema(found: 7, supported: Setlist.currentSchemaVersion)
        #expect(setlist.readOnly == reason)
        #expect(setlist.name == "Future Set")
        #expect(setlist.entries.map(\.songId) == [song])
        await #expect(throws: SetlistError.readOnly(id, reason)) {
            try await store.addSong(song, to: id)
        }
        await #expect(throws: SetlistError.readOnly(id, reason)) {
            try await store.remove(in: id, atOffsets: [0])
        }
        #expect(try lib.read("setlists/future.setlist.json") == future)
    }

    @Test
    func `pre-versioned setlist migrates forward and saves at the current version`() async throws {
        let lib = try TestLibrary()
        let id = SetlistID(lib.ids.next())
        let legacy = "{\"id\": \"\(id)\", \"name\": \"Old Set\"}"
        try lib.write(legacy, to: "setlists/old-set.setlist.json")

        let (store, issues) = try await lib.loadSetlists()
        let setlist = try #require(await store.setlist(id: id))

        #expect(issues.isEmpty)
        #expect(setlist.readOnly == nil)
        #expect(setlist.entries.isEmpty)
        #expect(setlist.schemaVersion == Setlist.currentSchemaVersion)
        #expect(try lib.read("setlists/old-set.setlist.json") == legacy)

        try await store.addSong(SongID(lib.ids.next()), to: id)
        #expect(try lib.read("setlists/old-set.setlist.json").contains("\"schemaVersion\" : 2"))
    }

    @Test
    func `operations before load throw notLoaded`() async throws {
        let lib = try TestLibrary()
        let store = SetlistStore(fileSystem: lib.fileSystem, clock: lib.clock, ids: lib.ids)
        #expect(await store.all().isEmpty)
        await #expect(throws: SetlistError.notLoaded) { try await store.create(name: "x") }
        let missing = SetlistID(lib.ids.next())
        _ = try await store.load(root: lib.root)
        await #expect(throws: SetlistError.setlistNotFound(missing)) {
            try await store.addSong(SongID(lib.ids.next()), to: missing)
        }
    }
}
