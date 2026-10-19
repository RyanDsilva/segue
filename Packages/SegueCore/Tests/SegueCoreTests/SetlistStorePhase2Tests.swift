import Foundation
import Library
import Setlists
import Support
import Testing

/// Phase 2 setlist operations (builder and show-end Save) on a real library folder: every
/// operation is checked after a reload from disk through a fresh `SetlistStore`.
struct SetlistStorePhase2Tests {
    /// A loaded store with one setlist "Friday" holding `count` real songs.
    private struct Friday {
        var store: SetlistStore
        var setlist: Setlist
        var songs: [SongID]
    }

    private static func friday(_ lib: TestLibrary, count: Int = 3) async throws -> Friday {
        let library = try await lib.openStore()
        let songs = try await Array(0 ..< count).asyncMap { number in
            try await library.createSong(source: "{title: Song \(number)}\nLa la\n").id
        }
        let (store, _) = try await lib.loadSetlists()
        let setlist = try await store.create(name: "Friday")
        let filled = try await store.insertSongs(songs, into: setlist.id)
        return Friday(store: store, setlist: filled, songs: songs)
    }

    private static func reloaded(_ lib: TestLibrary, _ id: SetlistID) async throws -> Setlist {
        let (store, issues) = try await lib.loadSetlists()
        #expect(issues.isEmpty)
        return try #require(await store.setlist(id: id))
    }

    @Test
    func `rename keeps the file and stamps updatedAt`() async throws {
        let lib = try TestLibrary()
        let fix = try await Self.friday(lib)
        let (store, setlist) = (fix.store, fix.setlist)
        lib.clock.advance(by: 60)
        let renamed = try await store.rename(setlist.id, to: "Friday - The Anchor")

        #expect(renamed.name == "Friday - The Anchor")
        #expect(renamed.updatedAt == SegueJSON.stamp(lib.clock.now()))
        #expect(renamed.createdAt == setlist.createdAt)
        #expect(lib.exists("setlists/friday.setlist.json"))
        #expect(try await Self.reloaded(lib, setlist.id) == renamed)
    }

    @Test
    func `duplicate gives fresh setlist and item IDs and keeps everything else`() async throws {
        let lib = try TestLibrary()
        let fix = try await Self.friday(lib)
        let (store, setlist) = (fix.store, fix.setlist)
        var first = setlist.entries[0]
        first.overrides = SetlistOverrides(transpose: -2, capo: 3)
        first.note = "start soft"
        try await store.updateEntry(first, in: setlist.id)
        let details = SetlistDetails(
            venue: "The Anchor",
            date: CalendarDay(year: 2026, month: 10, day: 23),
            targetDuration: 2700,
        )
        let original = try await store.updateDetails(details, of: setlist.id)

        lib.clock.advance(by: 30)
        let copy = try await store.duplicate(setlist.id)
        #expect(copy.name == "Friday copy")
        #expect(copy.id != original.id)
        #expect(Set(copy.entries.map(\.itemId)).isDisjoint(with: original.entries.map(\.itemId)))
        #expect(copy.entries.map(\.songId) == original.entries.map(\.songId))
        #expect(copy.entries.map(\.overrides) == original.entries.map(\.overrides))
        #expect(copy.entries.map(\.note) == original.entries.map(\.note))
        #expect(copy.venue == "The Anchor")
        #expect(copy.date == details.date)
        #expect(copy.targetDuration == details.targetDuration)
        #expect(copy.createdAt == SegueJSON.stamp(lib.clock.now()))
        #expect(lib.exists("setlists/friday-copy.setlist.json"))

        let named = try await store.duplicate(setlist.id, name: "Friday")
        #expect(named.name == "Friday")
        #expect(lib.exists("setlists/friday-2.setlist.json"))

        let (reloaded, issues) = try await lib.loadSetlists()
        #expect(issues.isEmpty)
        #expect(await reloaded.all().count == 3)
        #expect(await reloaded.setlist(id: copy.id) == copy)
        #expect(await reloaded.setlist(id: setlist.id) == original)
    }

    @Test
    func `delete moves the file to the trash and forgets the setlist`() async throws {
        let lib = try TestLibrary()
        let fix = try await Self.friday(lib)
        let (store, setlist) = (fix.store, fix.setlist)
        let other = try await store.create(name: "Saturday")
        let receipt = try await store.delete(setlist.id)

        #expect(!lib.exists("setlists/friday.setlist.json"))
        #expect(lib.trashedNames() == ["friday.setlist.json"])
        #expect(receipt.items.map(\.original) == [lib.url("setlists/friday.setlist.json")])
        #expect(await store.setlist(id: setlist.id) == nil)
        let (reloaded, _) = try await lib.loadSetlists()
        #expect(await reloaded.all().map(\.id) == [other.id])

        await #expect(throws: SetlistError.setlistNotFound(setlist.id)) {
            try await store.delete(setlist.id)
        }
        // A file already deleted outside Segue is just forgotten.
        try FileManager.default.removeItem(at: lib.url("setlists/saturday.setlist.json"))
        #expect(try await store.delete(other.id).isEmpty)
        #expect(await store.all().isEmpty)
    }

    @Test
    func `insert songs at an offset with new item IDs`() async throws {
        let lib = try TestLibrary()
        let fix = try await Self.friday(lib)
        let (store, setlist, songs) = (fix.store, fix.setlist, fix.songs)
        let late = [SongID(lib.ids.next()), SongID(lib.ids.next())]
        let updated = try await store.insertSongs(late, into: setlist.id, at: 1)

        #expect(updated.entries.map(\.songId) == [songs[0], late[0], late[1], songs[1], songs[2]])
        #expect(Set(updated.entries.map(\.itemId)).count == 5)
        let kept = setlist.entries.map(\.itemId)
        #expect([updated.entries[0], updated.entries[3], updated.entries[4]].map(\.itemId) == kept)
        #expect(try await Self.reloaded(lib, setlist.id) == updated)

        let other = SongID(lib.ids.next())
        await #expect(throws: SetlistError.invalidOffsets(setlist.id)) {
            try await store.insertSongs([other], into: setlist.id, at: 6)
        }
        await #expect(throws: SetlistError.invalidOffsets(setlist.id)) {
            try await store.insertSongs([other], into: setlist.id, at: -1)
        }
        #expect(try await Self.reloaded(lib, setlist.id) == updated)
    }

    @Test
    func `update entry changes only overrides and note`() async throws {
        let lib = try TestLibrary()
        let fix = try await Self.friday(lib)
        let (store, setlist, songs) = (fix.store, fix.setlist, fix.songs)
        var edited = setlist.entries[1]
        edited.overrides = SetlistOverrides(capo: 2)
        edited.note = "tag ending"
        edited.songId = songs[0] // ignored: the slot keeps its song
        let updated = try await store.updateEntry(edited, in: setlist.id)

        #expect(updated.entries[1].songId == songs[1])
        #expect(updated.entries[1].overrides == SetlistOverrides(capo: 2))
        #expect(updated.entries[1].note == "tag ending")
        #expect(try await Self.reloaded(lib, setlist.id) == updated)
        let json = try lib.read("setlists/friday.setlist.json")
        #expect(json.contains("\"note\" : \"tag ending\""))
        #expect(json.contains("\"capo\" : 2"))

        let stranger = SetlistEntry(itemId: SetlistItemID(lib.ids.next()), songId: songs[0])
        await #expect(throws: SetlistError.invalidOffsets(setlist.id)) {
            try await store.updateEntry(stranger, in: setlist.id)
        }
    }

    @Test
    func `update details sets and clears venue, date and target`() async throws {
        let lib = try TestLibrary()
        let fix = try await Self.friday(lib)
        let (store, setlist) = (fix.store, fix.setlist)
        let date = try #require(CalendarDay(year: 2026, month: 10, day: 23))
        let saved = try await store.updateDetails(
            SetlistDetails(venue: "The Anchor", date: date, targetDuration: 2700),
            of: setlist.id,
        )
        #expect(saved.venue == "The Anchor")
        #expect(saved.date == date)
        #expect(saved.targetDuration == 2700)
        #expect(try lib.read("setlists/friday.setlist.json").contains("\"date\" : \"2026-10-23\""))
        #expect(try await Self.reloaded(lib, setlist.id) == saved)

        let cleared = try await store.updateDetails(SetlistDetails(venue: "  "), of: setlist.id)
        #expect(cleared.venue == nil)
        #expect(cleared.date == nil)
        #expect(cleared.targetDuration == nil)
        #expect(try await Self.reloaded(lib, setlist.id) == cleared)
    }

    @Test
    func `replace entries saves a new order and refuses duplicate item IDs`() async throws {
        let lib = try TestLibrary()
        let fix = try await Self.friday(lib)
        let (store, setlist) = (fix.store, fix.setlist)
        let request = SetlistEntry(
            itemId: SetlistItemID(lib.ids.next()),
            songId: SongID(lib.ids.next()),
        )
        let reordered = [setlist.entries[2], setlist.entries[0], request, setlist.entries[1]]
        let saved = try await store.replaceEntries(reordered, in: setlist.id)
        #expect(saved.entries == reordered)
        #expect(try await Self.reloaded(lib, setlist.id) == saved)

        let before = try lib.read("setlists/friday.setlist.json")
        await #expect(throws: SetlistError.invalidOffsets(setlist.id)) {
            try await store.replaceEntries([request, request], in: setlist.id)
        }
        #expect(try lib.read("setlists/friday.setlist.json") == before)
        #expect(await store.setlist(id: setlist.id) == saved)
    }

    @Test
    func `edits to a newer-schema setlist are refused and the file is untouched`() async throws {
        let lib = try TestLibrary()
        let id = SetlistID(lib.ids.next())
        let song = SongID(lib.ids.next())
        let text = """
        {"schemaVersion": 99, "id": "\(id)", "name": "Future",
         "entries": [{"itemId": "\(SetlistItemID(lib.ids.next()))", "songId": "\(song)"}],
         "somethingNew": true}
        """
        try lib.write(text, to: "setlists/future.setlist.json")
        let (store, _) = try await lib.loadSetlists()
        let reason = ReadOnlyReason.newerSchema(found: 99, supported: Setlist.currentSchemaVersion)

        await #expect(throws: SetlistError.readOnly(id, reason)) {
            try await store.rename(id, to: "Past")
        }
        await #expect(throws: SetlistError.readOnly(id, reason)) {
            try await store.updateDetails(SetlistDetails(venue: "Here"), of: id)
        }
        await #expect(throws: SetlistError.readOnly(id, reason)) {
            try await store.insertSongs([song], into: id)
        }
        await #expect(throws: SetlistError.readOnly(id, reason)) {
            try await store.replaceEntries([], in: id)
        }
        #expect(try lib.read("setlists/future.setlist.json") == text)

        // Duplicating gives an editable copy of what this build can read.
        let copy = try await store.duplicate(id)
        #expect(copy.readOnly == nil)
        #expect(copy.entries.map(\.songId) == [song])
        #expect(try await store.rename(copy.id, to: "Present").name == "Present")
    }

    @Test
    func `operations before load throw notLoaded`() async throws {
        let lib = try TestLibrary()
        let store = SetlistStore(fileSystem: lib.fileSystem, clock: lib.clock, ids: lib.ids)
        let id = SetlistID(lib.ids.next())
        await #expect(throws: SetlistError.notLoaded) { try await store.rename(id, to: "x") }
        await #expect(throws: SetlistError.notLoaded) { try await store.duplicate(id) }
        await #expect(throws: SetlistError.notLoaded) { try await store.delete(id) }
    }
}
