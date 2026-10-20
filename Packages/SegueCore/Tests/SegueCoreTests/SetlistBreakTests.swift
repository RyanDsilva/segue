import Foundation
import Library
import Setlists
import Shows
import Support
import Testing

/// Break rows and changeover (P3-12 step 1; R85, R86, R105): they persist and reload, a v2
/// setlist loads unchanged, a v2 build opens a v3 file read-only, breaks never count as a
/// repeated song, and the show-end save keeps them in place.
struct SetlistBreakTests {
    private struct Fixture {
        var store: SetlistStore
        var setlist: Setlist
        var songs: [SongID]
        var path = "setlists/friday.setlist.json"
    }

    /// "Friday" holding songs 0, 1 and 2 of four library songs.
    private static func fixture(_ lib: TestLibrary) async throws -> Fixture {
        let library = try await lib.openStore()
        let songs = try await Array(0 ..< 4).asyncMap { number in
            try await library.createSong(source: "{title: Song \(number)}\nLa la\n").id
        }
        let (store, _) = try await lib.loadSetlists()
        let created = try await store.create(name: "Friday")
        let setlist = try await store.insertSongs(Array(songs.prefix(3)), into: created.id)
        return Fixture(store: store, setlist: setlist, songs: songs)
    }

    @Test
    func `break rows and changeover persist and reload at schema 3`() async throws {
        let lib = try TestLibrary()
        let fix = try await Self.fixture(lib)
        let id = fix.setlist.id

        var setlist = try await fix.store.insertBreak(into: id, at: 2)
        setlist = try await fix.store.insertBreak(into: id, label: "Encore", length: 120)
        setlist = try await fix.store.setChangeover(30, of: id)

        #expect(setlist.entries.map(\.breakInfo) == [
            nil, nil, SetlistBreak(label: "Set 2"), nil, SetlistBreak(label: "Encore", length: 120),
        ])
        #expect(setlist.songEntries.map(\.songId) == fix.songs.prefix(3).map(\.self))
        #expect(setlist.changeoverSeconds == 30)
        #expect(setlist.nextBreakLabel == "Set 4")
        let json = try lib.read(fix.path)
        #expect(json.contains("\"schemaVersion\" : 3"))
        #expect(json.contains("\"break\" : {"))
        #expect(json.contains("\"changeoverSeconds\" : 30"))
        let (reloaded, issues) = try await lib.loadSetlists()
        #expect(issues.isEmpty)
        #expect(await reloaded.setlist(id: id) == setlist)
    }

    @Test
    func `a break's label and intermission are edited in place, never its kind`() async throws {
        let lib = try TestLibrary()
        let fix = try await Self.fixture(lib)
        let id = fix.setlist.id
        let withBreak = try await fix.store.insertBreak(into: id, at: 1)
        var row = withBreak.entries[1]
        row.kind = .break(SetlistBreak(label: "After dinner", length: 900))

        let updated = try await fix.store.updateEntry(row, in: id)

        #expect(updated.entries[1].breakInfo == SetlistBreak(label: "After dinner", length: 900))
        // A song slot cannot become a break (or the other way round).
        let song = SetlistEntry(itemId: withBreak.entries[1].itemId, songId: fix.songs[3])
        await #expect(throws: SetlistError.invalidOffsets(id)) {
            try await fix.store.updateEntry(song, in: id)
        }
        var breakForSong = withBreak.entries[0]
        breakForSong.kind = .break(SetlistBreak(label: "Nope"))
        await #expect(throws: SetlistError.invalidOffsets(id)) {
            try await fix.store.updateEntry(breakForSong, in: id)
        }
    }

    @Test
    func `a v2 setlist loads unchanged and is written at v3 only when edited`() async throws {
        let lib = try TestLibrary()
        let song = SongID(ULID(milliseconds: 5, randomness: Array(repeating: 7, count: 10)))
        let item = SetlistItemID(ULID(milliseconds: 6, randomness: Array(repeating: 8, count: 10)))
        let setlistID = SetlistID(ULID(milliseconds: 4, randomness: Array(repeating: 9, count: 10)))
        let v2 = """
        {"schemaVersion": 2, "id": "\(setlistID)",
         "name": "Old", "entries": [{"itemId": "\(item)", "songId": "\(song)", "note": "soft"}],
         "targetDuration": 1800}
        """
        try lib.write(v2, to: "setlists/old.setlist.json")

        let (store, issues) = try await lib.loadSetlists()

        #expect(issues.isEmpty)
        let loaded = try #require(await store.all().first)
        #expect(loaded.readOnly == nil)
        #expect(loaded.changeoverSeconds == nil)
        #expect(loaded.entries == [SetlistEntry(itemId: item, songId: song, note: "soft")])
        #expect(try lib.read("setlists/old.setlist.json") == v2)
    }

    @Test
    func `a newer setlist opens read-only, keeping the rows it can read`() async throws {
        let lib = try TestLibrary()
        let song = SongID(ULID(milliseconds: 5, randomness: Array(repeating: 7, count: 10)))
        let item = SetlistItemID(ULID(milliseconds: 6, randomness: Array(repeating: 8, count: 10)))
        let pause = SetlistItemID(ULID(milliseconds: 6, randomness: Array(repeating: 9, count: 10)))
        let setlistID = SetlistID(ULID(milliseconds: 4, randomness: Array(repeating: 9, count: 10)))
        let newer = """
        {"schemaVersion": 4, "id": "\(setlistID)",
         "name": "Future", "entries": [
           {"itemId": "\(item)", "songId": "\(song)"},
           {"itemId": "\(pause)", "break": {"label": "Set 2"}},
           {"itemId": "\(pause)", "somethingNew": {}}]}
        """
        try lib.write(newer, to: "setlists/future.setlist.json")

        let (store, _) = try await lib.loadSetlists()

        let loaded = try #require(await store.all().first)
        #expect(loaded.readOnly == .newerSchema(found: 4, supported: Setlist.currentSchemaVersion))
        #expect(loaded.entries.map(\.kind) == [.song(song), .break(SetlistBreak(label: "Set 2"))])
        let reason = try #require(loaded.readOnly)
        await #expect(throws: SetlistError.readOnly(loaded.id, reason)) {
            try await store.insertBreak(into: loaded.id)
        }
        #expect(try lib.read("setlists/future.setlist.json") == newer)
    }

    @Test
    func `breaks never count as a repeated song`() async throws {
        let lib = try TestLibrary()
        let fix = try await Self.fixture(lib)
        let id = fix.setlist.id
        _ = try await fix.store.insertBreak(into: id, at: 1)
        let setlist = try await fix.store.insertBreak(into: id, at: 3)

        #expect(setlist.repeatedEntries.isEmpty)
        // A batch add (⌘A in Pick) skips the songs already in, around the breaks.
        let added = try await fix.store.insertSongs(fix.songs, into: id)
        #expect(added.songEntries.map(\.songId) == fix.songs.map(\.self))
        #expect(added.entries.count(where: \.isBreak) == 2)
        // A reorder that moves breaks and songs together saves.
        let reversed = try await fix.store.replaceEntries(added.entries.reversed(), in: id)
        #expect(reversed.entries.map(\.itemId) == added.entries.reversed().map(\.itemId))
        // Duplicate keeps breaks and changeover, with new item IDs.
        _ = try await fix.store.setChangeover(45, of: id)
        let copy = try await fix.store.duplicate(id)
        #expect(copy.entries.map(\.kind) == reversed.entries.map(\.kind))
        #expect(Set(copy.entries.map(\.itemId)).isDisjoint(with: reversed.entries.map(\.itemId)))
        #expect(copy.changeoverSeconds == 45)
    }

    @Test
    func `the show-end save keeps break rows where they were`() {
        let setlist = SetlistID(ULID(milliseconds: 1, randomness: Array(repeating: 1, count: 10)))
        func item(_ byte: UInt8) -> SetlistItemID {
            SetlistItemID(ULID(milliseconds: 2, randomness: Array(repeating: byte, count: 10)))
        }
        func song(_ byte: UInt8) -> SongID {
            SongID(ULID(milliseconds: 3, randomness: Array(repeating: byte, count: 10)))
        }
        let planned = [
            SetlistEntry(itemId: item(1), songId: song(1)),
            SetlistEntry(itemId: item(2), songId: song(2)),
            SetlistEntry(itemId: item(3), break: SetlistBreak(label: "Set 2", length: 600)),
            SetlistEntry(itemId: item(4), songId: song(4)),
            SetlistEntry(itemId: item(5), songId: song(5)),
        ]
        // Performed: song 2 before song 1, the second part as planned (the break is not a
        // show item yet).
        let performed = [UInt8(2), 1, 4, 5].map { byte in
            ReorderDiff.Row(
                item: ShowItem(itemId: item(byte), songId: song(byte), title: "", origin: .setlist),
                change: byte == 1 ? .moved(fromPosition: 0) : .unchanged,
            )
        }
        let diff = ReorderDiff(
            setlistId: setlist,
            setlistName: "Friday",
            planned: planned,
            performed: performed,
        )

        let saved = diff.entries(including: [])

        #expect(saved.map(\.itemId) == [item(2), item(1), item(3), item(4), item(5)])
        #expect(diff.repeatedItemIds.isEmpty)
    }
}
