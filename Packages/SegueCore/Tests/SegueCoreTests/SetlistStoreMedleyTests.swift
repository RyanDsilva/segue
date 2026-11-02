import Foundation
import Library
import Setlists
import Support
import Testing

/// Medley store operations on a real library folder (P9-3 5.4, 5.6): make, ungroup, add,
/// move, remove, rename, transitions, the decision 8 refusals, and the schema 6 to 7
/// migration with round trips through the file.
struct SetlistStoreMedleyTests {
    private struct Fixture {
        var lib: TestLibrary
        var store: SetlistStore
        var setlist: Setlist
        var songs: [SongID]
        var path = "setlists/friday.setlist.json"

        var id: SetlistID {
            setlist.id
        }

        func item(_ position: Int) -> SetlistItemID {
            setlist.entries[position].itemId
        }

        /// The file as a fresh store reads it.
        func reloaded() async throws -> Setlist? {
            let (store, issues) = try await lib.loadSetlists()
            #expect(issues.isEmpty)
            return await store.setlist(id: setlist.id)
        }
    }

    /// "Friday" holding songs 0 ... 5 as slots with a break at position 3 (before song 3);
    /// 6 ... 15 are in the library only.
    private static func fixture() async throws -> Fixture {
        let lib = try TestLibrary()
        let library = try await lib.openStore()
        let songs = try await Array(0 ..< 16).asyncMap { number in
            try await library.createSong(source: "{title: Song \(number)}\n[G]La la\n").id
        }
        let (store, _) = try await lib.loadSetlists()
        let created = try await store.create(name: "Friday")
        _ = try await store.insertSongs(Array(songs.prefix(6)), into: created.id)
        let setlist = try await store.insertBreak(into: created.id, at: 3)
        return Fixture(lib: lib, store: store, setlist: setlist, songs: songs)
    }

    @Test
    func `make a medley from non-adjacent slots: ids kept, placed at the first, one write`()
        async throws
    {
        var fix = try await Self.fixture()
        // Notes and arrangements stay attached through the member's kept item ID.
        var first = fix.setlist.entries[0]
        first.note = "Start soft"
        first.overrides = SetlistOverrides(transpose: 2)
        fix.setlist = try await fix.store.updateEntry(first, in: fix.id)
        let picked = [fix.item(0), fix.item(2), fix.item(4)]

        let (setlist, medleyId) = try await fix.store.makeMedley(from: picked, in: fix.id)

        #expect(setlist.entries.count == 5)
        let medley = try #require(setlist.entries[0].medley)
        #expect(setlist.entries[0].itemId == medleyId)
        #expect(medley.members.map(\.itemId) == picked)
        #expect(medley.members.map(\.songId) == [0, 2, 3].map { fix.songs[$0] })
        #expect(medley.members[0].note == "Start soft")
        #expect(medley.members[0].overrides.transpose == 2)
        #expect(medley.title == nil)
        #expect(setlist.entries.map(\.songIds.count) == [3, 1, 0, 1, 1])
        #expect(setlist.songCount == 6)
        #expect(try await fix.reloaded() == setlist)
        let json = try fix.lib.read(fix.path)
        #expect(json.contains("\"schemaVersion\" : 7"))
        #expect(json.contains("\"medley\" : {"))
    }

    @Test
    func `a selected medley is spliced in place, keeping title, transitions and lock`()
        async throws
    {
        let fix = try await Self.fixture()
        var (setlist, medley) = try await fix.store.makeMedley(
            from: [fix.item(1), fix.item(2)],
            in: fix.id,
        )
        setlist = try await fix.store.renameMedley(medley, to: "Love medley", in: fix.id)
        let second = try #require(setlist.entries[1].medley?.members[1].itemId)
        setlist = try await fix.store.setTransition("Hold the D", member: second, in: fix.id)
        setlist = try await fix.store.setLocked([medley], true, in: fix.id)

        let (spliced, newId) = try await fix.store.makeMedley(
            from: [setlist.entries[0].itemId, medley, setlist.entries[4].itemId],
            in: fix.id,
        )

        let value = try #require(spliced.entries[0].medley)
        #expect(spliced.entries[0].itemId == newId)
        #expect(value.title == "Love medley")
        #expect(value.members.map(\.songId) == [0, 1, 2, 4].map { fix.songs[$0] })
        #expect(value.members.map(\.transition) == [nil, nil, "Hold the D", nil])
        #expect(spliced.entries[0].locked)
    }

    @Test
    func `make refuses breaks, too few songs, a 13th member and decision 8 duplicates`()
        async throws
    {
        let fix = try await Self.fixture()
        let before = try fix.lib.read(fix.path)
        await #expect(throws: SetlistError.medley(fix.id, .notASongSlot(fix.item(3)))) {
            try await fix.store.makeMedley(from: [fix.item(0), fix.item(3)], in: fix.id)
        }
        await #expect(throws: SetlistError.medley(fix.id, .tooFewSongs)) {
            try await fix.store.makeMedley(from: [fix.item(0)], in: fix.id)
        }
        #expect(try fix.lib.read(fix.path) == before)

        // A 13th member.
        let (big, medley) = try await fix.store.makeMedley(
            from: [fix.item(0), fix.item(1)],
            in: fix.id,
        )
        var setlist = big
        for song in fix.songs[6 ..< 16] {
            setlist = try await fix.store.addToMedley(song, medley: medley, in: fix.id)
        }
        #expect(setlist.entries[0].medley?.members.count == 12)
        await #expect(throws: SetlistError.medley(fix.id, .tooManyMembers)) {
            try await fix.store.moveIntoMedley(
                setlist.entries[1].itemId,
                medley: medley,
                in: fix.id,
            )
        }

        // Two medleys sharing a song: song 2 is a slot, also put in a reprise slot elsewhere
        // is fine, but a second medley holding song 0 is refused.
        let zero = fix.songs[0]
        let withSlot = try await fix.store.insertSong(
            zero,
            overrides: SetlistOverrides(),
            into: fix.id,
        )
        let reprise = try #require(withSlot.entries.last)
        #expect(reprise.songId == zero)
        await #expect(throws: SetlistError.medley(fix.id, .duplicate(
            zero,
            .member(entryId: medley, itemId: fix.item(0), label: "1a"),
        ))) {
            try await fix.store.makeMedley(
                from: [withSlot.entries[1].itemId, reprise.itemId],
                in: fix.id,
            )
        }
    }

    @Test
    func `a reprise either way round is allowed, a second slot or member is refused`()
        async throws
    {
        let fix = try await Self.fixture()
        var (setlist, medley) = try await fix.store.makeMedley(
            from: [fix.item(0), fix.item(1)],
            in: fix.id,
        )
        // A member's song added again as a slot: the reprise.
        setlist = try await fix.store.insertSongs([fix.songs[0]], into: fix.id)
        #expect(setlist.entries.last?.songId == fix.songs[0])
        // A third time as a slot is skipped (nothing written).
        let again = try await fix.store.insertSongs([fix.songs[0]], into: fix.id)
        #expect(again == setlist)
        // A slot's song joining the medley: allowed as a reprise (song 2 is slot 2).
        setlist = try await fix.store.addToMedley(fix.songs[2], medley: medley, in: fix.id)
        #expect(setlist.entries[0].medley?.members.count == 3)
        // Twice in one medley.
        await #expect(throws: SetlistError.self) {
            try await fix.store.addToMedley(fix.songs[1], medley: medley, in: fix.id)
        }
        #expect(setlist.repeatedEntries.isEmpty)
    }

    @Test
    func `ungroup, remove, auto-ungroup, move within and move into`() async throws {
        let fix = try await Self.fixture()
        var (setlist, medley) = try await fix.store.makeMedley(
            from: [fix.item(0), fix.item(1), fix.item(2)],
            in: fix.id,
        )
        let members = try #require(setlist.entries[0].medley?.members.map(\.itemId))
        setlist = try await fix.store.setTransition("into b", member: members[1], in: fix.id)

        // Move within: b to the end; the transition moves with it.
        setlist = try await fix.store.moveMember(members[1], to: 2, in: fix.id)
        #expect(setlist.entries[0].medley?.members.map(\.itemId)
            == [members[0], members[2], members[1]])
        #expect(setlist.entries[0].medley?.members[2].transition == "into b")
        await #expect(throws: SetlistError.invalidOffsets(fix.id)) {
            try await fix.store.moveMember(members[1], to: 3, in: fix.id)
        }

        // Move into: slot 4 (song 4, after the break) joins at index 1.
        let slot = try #require(setlist.entries.first { $0.songId == fix.songs[4] })
        setlist = try await fix.store.moveIntoMedley(
            slot.itemId,
            medley: medley,
            at: 1,
            in: fix.id,
        )
        #expect(setlist.entries[0].medley?.members.map(\.itemId)[1] == slot.itemId)
        #expect(!setlist.entries.contains { $0.itemId == slot.itemId })

        // Remove from medley: the member becomes a slot right after the medley.
        setlist = try await fix.store.removeFromMedley(slot.itemId, in: fix.id)
        #expect(setlist.entries[1].itemId == slot.itemId)
        #expect(setlist.entries[1].songId == fix.songs[4])

        // Remove two members from the set: one left, so it becomes that song's slot.
        setlist = try await fix.store.removeMember(members[1], in: fix.id)
        setlist = try await fix.store.removeMember(members[2], in: fix.id)
        #expect(setlist.entries[0].itemId == members[0])
        #expect(setlist.entries[0].songId == fix.songs[0])
        #expect(setlist.entries.allSatisfy { !$0.isMedley })

        // Ungroup: members become slots in place, transitions dropped.
        var (again, other) = try await fix.store.makeMedley(
            from: [setlist.entries[0].itemId, setlist.entries[1].itemId],
            in: fix.id,
        )
        let second = try #require(again.entries[0].medley?.members[1].itemId)
        again = try await fix.store.setTransition("drums fill", member: second, in: fix.id)
        again = try await fix.store.ungroup(other, in: fix.id)
        #expect(again.entries.prefix(2).map(\.songId) == [fix.songs[0], fix.songs[4]])
        #expect(try !fix.lib.read(fix.path).contains("drums fill"))
        #expect(try await fix.reloaded() == again)
    }

    @Test
    func `ungrouping or removing a reprised member never makes two slots of one song`()
        async throws
    {
        let fix = try await Self.fixture()
        let (_, medley) = try await fix.store.makeMedley(
            from: [fix.item(0), fix.item(1)],
            in: fix.id,
        )
        let setlist = try await fix.store.insertSongs([fix.songs[0]], into: fix.id)
        let reprise = try #require(setlist.entries.last)
        let occurrence = SongOccurrence.slot(reprise.itemId, number: 6)
        await #expect(throws: SetlistError.medley(fix.id, .duplicate(fix.songs[0], occurrence))) {
            try await fix.store.ungroup(medley, in: fix.id)
        }
        await #expect(throws: SetlistError.medley(fix.id, .duplicate(fix.songs[0], occurrence))) {
            try await fix.store.removeFromMedley(fix.item(0), in: fix.id)
        }
    }

    @Test
    func `rename and transitions are trimmed, capped and blank clears them`() async throws {
        let fix = try await Self.fixture()
        var (setlist, medley) = try await fix.store.makeMedley(
            from: [fix.item(0), fix.item(1)],
            in: fix.id,
        )
        let members = try #require(setlist.entries[0].medley?.members.map(\.itemId))
        setlist = try await fix.store.renameMedley(medley, to: "  Love medley  ", in: fix.id)
        #expect(setlist.entries[0].medley?.title == "Love medley")
        setlist = try await fix.store.setTransition(
            "  " + String(repeating: "x", count: 300),
            member: members[1],
            in: fix.id,
        )
        #expect(setlist.entries[0].medley?.members[1].transition?.count == 280)
        // The first member never has one.
        setlist = try await fix.store.setTransition("ignored", member: members[0], in: fix.id)
        #expect(setlist.entries[0].medley?.members[0].transition == nil)
        setlist = try await fix.store.setTransition("   ", member: members[1], in: fix.id)
        #expect(setlist.entries[0].medley?.members[1].transition == nil)
        setlist = try await fix.store.renameMedley(medley, to: " ", in: fix.id)
        #expect(setlist.entries[0].medley?.displayTitle == "Medley")
        // A member edits like a slot.
        setlist = try await fix.store.updateSongSlot(
            members[1],
            overrides: SetlistOverrides(capo: 2),
            note: "Last chorus twice",
            arrangement: nil,
            in: fix.id,
        )
        #expect(setlist.songSlot(members[1])?.overrides.capo == 2)
        #expect(setlist.songSlot(members[1])?.note == "Last chorus twice")
        #expect(try await fix.reloaded() == setlist)
    }

    @Test
    func `duplicate gives members new IDs and drops repeated members`() async throws {
        let fix = try await Self.fixture()
        let (setlist, _) = try await fix.store.makeMedley(
            from: [fix.item(0), fix.item(1)],
            in: fix.id,
        )
        let copy = try await fix.store.duplicate(fix.id)
        let original = try #require(setlist.entries[0].medley?.members)
        let copied = try #require(copy.entries[0].medley?.members)
        #expect(copied.map(\.songId) == original.map(\.songId))
        #expect(Set(copied.map(\.itemId)).isDisjoint(with: original.map(\.itemId)))
    }

    @Test
    func `a v6 file reads unchanged and is written at 7 with the same entries`() async throws {
        let lib = try TestLibrary()
        let id = SetlistID(lib.ids.next())
        let song = SongID(lib.ids.next())
        let item = SetlistItemID(lib.ids.next())
        let v6 = """
        {"schemaVersion": 6, "id": "\(id)", "name": "Six",
         "entries": [{"itemId": "\(item)", "songId": "\(song)", "note": "soft",
                      "locked": true}]}
        """
        try lib.write(v6, to: "setlists/six.setlist.json")
        let (store, issues) = try await lib.loadSetlists()
        #expect(issues.isEmpty)
        let loaded = try #require(await store.setlist(id: id))
        #expect(loaded.readOnly == nil)
        #expect(try lib.read("setlists/six.setlist.json") == v6)

        let renamed = try await store.rename(id, to: "Six again")
        let json = try lib.read("setlists/six.setlist.json")
        #expect(json.contains("\"schemaVersion\" : 7"))
        #expect(renamed.entries == loaded.entries)
        #expect(!json.contains("medley"))
    }

    @Test
    func `a medley survives a round trip through a fresh store`() async throws {
        let fix = try await Self.fixture()
        var (setlist, medley) = try await fix.store.makeMedley(
            from: [fix.item(4), fix.item(0), fix.item(5)],
            in: fix.id,
        )
        setlist = try await fix.store.renameMedley(medley, to: "Love medley", in: fix.id)
        let members = try #require(setlist.entries[0].medley?.members.map(\.itemId))
        setlist = try await fix.store.setTransition(
            "Hold the D",
            member: members[2],
            in: fix.id,
        )
        let reloaded = try #require(try await fix.reloaded())
        #expect(reloaded == setlist)
        #expect(reloaded.entries[0].medley?.members.map(\.songId)
            == [0, 3, 4].map { fix.songs[$0] })
    }
}

/// R191 (beside the main suite, at its length limit).
extension SetlistStoreMedleyTests {
    @Test
    func `slots and members save their song's file name and keep it after a relaunch (R191)`()
        async throws
    {
        let fix = try await Self.fixture()
        let names = Dictionary(uniqueKeysWithValues: fix.songs.enumerated().map {
            ($0.element, "song-\($0.offset).cho")
        })
        await fix.store.setSongFileNames(names)
        // Opening never writes: the names arrive in memory only.
        let before = try fix.lib.read(fix.path)
        #expect(!before.contains("fileName"))
        #expect(await fix.store.setlist(id: fix.id)?.entries[0].fileName == "song-0.cho")
        let (setlist, medley) = try await fix.store.makeMedley(
            from: [fix.item(1), fix.item(2)],
            in: fix.id,
        )
        let json = try fix.lib.read(fix.path)
        #expect(json.contains("\"fileName\" : \"song-0.cho\""))
        #expect(json.contains("\"fileName\" : \"song-2.cho\""))
        // A relaunch with song 2 gone: a fresh store with names for the others only.
        let (fresh, issues) = try await fix.lib.loadSetlists()
        #expect(issues.isEmpty)
        var others = names
        others[fix.songs[2]] = nil
        await fresh.setSongFileNames(others)
        let reloaded = try #require(await fresh.setlist(id: fix.id))
        let member = try #require(reloaded.member(fix.item(2)))
        #expect(member.entry.itemId == medley)
        #expect(reloaded.songSlot(fix.item(2))?.fileName == "song-2.cho")
        #expect(reloaded == setlist)
    }
}
