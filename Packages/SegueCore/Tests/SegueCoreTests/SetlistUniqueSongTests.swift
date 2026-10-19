import Foundation
import Library
import Setlists
import Shows
import Support
import Testing

/// A song appears at most once in a setlist: every path that adds songs (builder `+`, drag,
/// Add to Setlist, Welcome seeding, Duplicate, show-end Save) leaves an existing song where
/// it is and writes nothing for it. Setlists saved with repeats before this rule load as
/// they are and are never rewritten until the user edits them.
struct SetlistUniqueSongTests {
    private struct Fixture {
        var store: SetlistStore
        var setlist: Setlist
        var songs: [SongID]
        var path = "setlists/friday.setlist.json"
    }

    /// "Friday" holding songs 0 and 1 of `count` library songs.
    private static func fixture(_ lib: TestLibrary, count: Int = 4) async throws -> Fixture {
        let library = try await lib.openStore()
        let songs = try await Array(0 ..< count).asyncMap { number in
            try await library.createSong(source: "{title: Song \(number)}\nLa la\n").id
        }
        let (store, _) = try await lib.loadSetlists()
        let created = try await store.create(name: "Friday")
        let setlist = try await store.insertSongs(Array(songs.prefix(2)), into: created.id)
        return Fixture(store: store, setlist: setlist, songs: songs)
    }

    @Test
    func `adding a song already in the set changes nothing and writes nothing`() async throws {
        let lib = try TestLibrary()
        let fix = try await Self.fixture(lib)
        let before = try lib.read(fix.path)
        lib.clock.advance(by: 60)

        let added = try await fix.store.addSong(fix.songs[0], to: fix.setlist.id)

        #expect(added == fix.setlist)
        #expect(try lib.read(fix.path) == before)
        #expect(await fix.store.setlist(id: fix.setlist.id) == fix.setlist)
    }

    @Test
    func `insert skips songs already in the set and repeats within the batch`() async throws {
        let lib = try TestLibrary()
        let fix = try await Self.fixture(lib)
        let songs = fix.songs

        // Multi-song drop before row 1: song 1 is already in, song 2 is dragged twice.
        let updated = try await fix.store.insertSongs(
            [songs[2], songs[1], songs[2], songs[3]],
            into: fix.setlist.id,
            at: 1,
        )

        #expect(updated.entries.map(\.songId) == [songs[0], songs[2], songs[3], songs[1]])
        #expect(Array(updated.entries[0 ..< 1]) == Array(fix.setlist.entries[0 ..< 1]))
        #expect(updated.entries[3] == fix.setlist.entries[1])
        let (reloaded, _) = try await lib.loadSetlists()
        #expect(await reloaded.setlist(id: fix.setlist.id) == updated)
    }

    @Test
    func `inserting only songs already in the set writes nothing`() async throws {
        let lib = try TestLibrary()
        let fix = try await Self.fixture(lib)
        let before = try lib.read(fix.path)
        lib.clock.advance(by: 60)

        let same = try await fix.store.insertSongs(
            [fix.songs[1], fix.songs[0]],
            into: fix.setlist.id,
            at: 0,
        )

        #expect(same == fix.setlist)
        #expect(try lib.read(fix.path) == before)
        // Offsets are still checked.
        await #expect(throws: SetlistError.invalidOffsets(fix.setlist.id)) {
            try await fix.store.insertSongs([fix.songs[0]], into: fix.setlist.id, at: 9)
        }
    }

    @Test
    func `show end save refuses a new entry repeating a song`() async throws {
        let lib = try TestLibrary()
        let fix = try await Self.fixture(lib)
        let entries = fix.setlist.entries
        let before = try lib.read(fix.path)
        let repeatEntry = SetlistEntry(itemId: SetlistItemID(lib.ids.next()), songId: fix.songs[0])

        await #expect(throws: SetlistError.duplicateSong(fix.setlist.id, fix.songs[0])) {
            try await fix.store.replaceEntries(
                [entries[1], repeatEntry, entries[0]],
                in: fix.setlist.id,
            )
        }
        #expect(try lib.read(fix.path) == before)

        let fresh = SetlistEntry(itemId: SetlistItemID(lib.ids.next()), songId: fix.songs[3])
        let saved = try await fix.store.replaceEntries(
            [entries[1], fresh, entries[0]],
            in: fix.setlist.id,
        )
        #expect(saved.entries.map(\.songId) == [fix.songs[1], fix.songs[3], fix.songs[0]])
    }

    /// Legacy repeats: shown and kept as saved (the file is untouched on load), never
    /// multiplied, and dropped from a Duplicate's copy.
    @Test
    func `a setlist saved with repeats loads as it is and only drops them on copy`() async throws {
        let lib = try TestLibrary()
        let library = try await lib.openStore()
        let song = try await library.createSong(source: "{title: Again}\nLa\n").id
        let other = try await library.createSong(source: "{title: Other}\nLa\n").id
        let id = SetlistID(lib.ids.next())
        let first = SetlistItemID(lib.ids.next())
        let second = SetlistItemID(lib.ids.next())
        let text = """
        {"schemaVersion": 2, "id": "\(id)", "name": "Twice",
         "entries": [{"itemId": "\(first)", "songId": "\(song)"},
                     {"itemId": "\(second)", "songId": "\(song)", "note": "encore"}]}
        """
        try lib.write(text, to: "setlists/twice.setlist.json")

        let (store, issues) = try await lib.loadSetlists()
        #expect(issues.isEmpty)
        let loaded = try #require(await store.setlist(id: id))
        #expect(loaded.entries.map(\.itemId) == [first, second])
        #expect(loaded.repeatedEntries == [second])
        #expect(try lib.read("setlists/twice.setlist.json") == text)

        // Another copy is refused; a different song saves the file with both slots kept.
        #expect(try await store.addSong(song, to: id) == loaded)
        #expect(try lib.read("setlists/twice.setlist.json") == text)
        let edited = try await store.addSong(other, to: id)
        #expect(edited.entries.map(\.songId) == [song, song, other])
        #expect(edited.entries[1].note == "encore")

        let copy = try await store.duplicate(id)
        #expect(copy.entries.map(\.songId) == [song, other])
        #expect(copy.repeatedEntries.isEmpty)
    }

    @Test
    func `repeated entries are those whose song appears earlier`() {
        let ids = ULIDGenerator(clock: ManualClock(), seed: 7)
        let songA = SongID(ids.next())
        let songB = SongID(ids.next())
        let entries = [songA, songB, songA, songA].map { song in
            SetlistEntry(itemId: SetlistItemID(ids.next()), songId: song)
        }
        let setlist = Setlist(id: SetlistID(ids.next()), name: "Set", entries: entries)

        #expect(setlist.contains(songA))
        #expect(!setlist.contains(SongID(ids.next())))
        #expect(setlist.repeatedEntries == [entries[2].itemId, entries[3].itemId])
    }

    /// A request or inserted song that repeats a song already in the set is shown as such
    /// at show end, never ticked, and never written by Save.
    @Test
    func `show end merge never adds a song already in the set`() {
        let ids = ULIDGenerator(clock: ManualClock(), seed: 7)
        let songs = (0 ..< 3).map { _ in SongID(ids.next()) }
        let planned = songs.prefix(2).map { song in
            SetlistEntry(itemId: SetlistItemID(ids.next()), songId: song)
        }
        func item(_ song: SongID, _ origin: ItemOrigin) -> ShowItem {
            ShowItem(itemId: SetlistItemID(ids.next()), songId: song, title: "", origin: origin)
        }
        let encore = item(songs[0], .request)
        let fresh = item(songs[2], .inserted)
        let freshAgain = item(songs[2], .request)
        let rows: [ReorderDiff.Row] = [
            .init(item: ShowItem(
                itemId: planned[0].itemId,
                songId: songs[0],
                title: "",
                origin: .setlist,
            ), change: .unchanged),
            .init(item: fresh, change: .inserted(.inserted)),
            .init(item: ShowItem(
                itemId: planned[1].itemId,
                songId: songs[1],
                title: "",
                origin: .setlist,
            ), change: .unchanged),
            .init(item: encore, change: .inserted(.request)),
            .init(item: freshAgain, change: .inserted(.request)),
        ]
        let diff = ReorderDiff(
            setlistId: SetlistID(ids.next()),
            setlistName: "Friday",
            planned: planned,
            performed: rows,
        )

        #expect(diff.repeatedItemIds == [encore.itemId, freshAgain.itemId])
        #expect(diff.defaultIncluded == [fresh.itemId])
        // Even when a repeat is passed in, Save writes each song once.
        let saved = diff.entries(including: Set(diff.insertedItemIds))
        #expect(saved.map(\.songId) == [songs[0], songs[2], songs[1]])
    }
}
