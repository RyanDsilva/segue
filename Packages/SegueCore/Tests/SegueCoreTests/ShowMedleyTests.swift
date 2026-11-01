import Foundation
import Library
import Setlists
import Shows
import Support
import Testing

/// Medleys in a running show (P9-3 5.4, 8.1-8.3) on a real temp library: one item per
/// member, nothing lands inside a medley, the reprise's pending occurrences, block moves,
/// the reorder review and the Gig Log's nested slots.
struct ShowMedleyTests {
    private struct Fixture {
        var harness: ShowHarness
        var setlist: Setlist
        var songs: [SongRecord]
        var medley: SetlistItemID
        /// The members' item IDs, in order.
        var members: [SetlistItemID]
    }

    /// Songs 1 ... 5 as slots; slots 2, 3 and 4 made into "Love medley" with a transition
    /// into its second member: set = [1, medley(2, 3, 4), 5].
    private static func fixture(reprise: Bool = false) async throws -> Fixture {
        let harness = try await ShowHarness()
        let (made, songs) = try await harness.makeSet(5)
        var (setlist, medley) = try await harness.setlists.makeMedley(
            from: Array(made.entries[1 ... 3].map(\.itemId)),
            in: made.id,
        )
        setlist = try await harness.setlists.renameMedley(
            medley,
            to: "Love medley",
            in: made.id,
        )
        let members = try #require(setlist.entries[1].medley?.members.map(\.itemId))
        setlist = try await harness.setlists.setTransition(
            "Hold the D",
            member: members[1],
            in: made.id,
        )
        if reprise {
            setlist = try await harness.setlists.insertSongs([songs[1].id], into: made.id)
        }
        return Fixture(
            harness: harness,
            setlist: setlist,
            songs: songs,
            medley: medley,
            members: members,
        )
    }

    private static func start(_ fix: Fixture) async throws -> ShowController {
        try await ShowController.start(
            setlist: fix.setlist,
            kind: .gig,
            environment: fix.harness.environment(),
        )
    }

    @Test
    func `start expands a medley into one item per member with refs`() async throws {
        let fix = try await Self.fixture()
        let show = try await Self.start(fix)
        let record = await show.state.record
        #expect(record.items.map(\.title) == ["Song 1", "Song 2", "Song 3", "Song 4", "Song 5"])
        #expect(record.items.map(\.medley?.index) == [nil, 0, 1, 2, nil])
        #expect(record.items[2].medley == ShowMedleyRef(
            slot: fix.medley,
            title: "Love medley",
            index: 1,
            count: 3,
            transition: "Hold the D",
        ))
        #expect(record.items[1].itemId == fix.members[0])
        #expect(record.planned.count == 3)
        #expect(record.omittedEntries.isEmpty)
        let reloaded = try #require(try await fix.harness.reloadedShow(record.id))
        #expect(reloaded.items == record.items)
        #expect(try fix.harness.lib.read(fix.harness.showPath(record.id))
            .contains("\"schemaVersion\" : 5"))
    }

    @Test
    func `missing members are omitted and counted out; an all-missing medley goes`()
        async throws
    {
        let fix = try await Self.fixture()
        _ = try await fix.harness.library.deleteSong(id: fix.songs[2].id)
        let missing = await ShowController.missingEntries(
            in: fix.setlist,
            songs: fix.harness.library,
        )
        #expect(missing.map(\.itemId) == [fix.members[1]])
        let show = try await ShowController.start(
            setlist: fix.setlist,
            kind: .gig,
            omitting: Set(missing.map(\.itemId)),
            environment: fix.harness.environment(),
        )
        let record = await show.state.record
        #expect(record.items.compactMap(\.medley).map(\.count) == [2, 2])
        #expect(record.items.compactMap(\.medley).map(\.index) == [0, 1])
        #expect(record.omittedMembers.map(\.member.itemId) == [fix.members[1]])

        let all = try await ShowController.start(
            setlist: fix.setlist,
            kind: .rehearsal,
            omitting: Set(fix.members),
            environment: fix.harness.environment(),
        )
        let gone = await all.state.record
        #expect(gone.items.map(\.title) == ["Song 1", "Song 5"])
        #expect(gone.omittedEntries.map(\.itemId) == [fix.medley])
    }

    @Test
    func `insert next, play now and requests during a medley land after it, uninterrupted`()
        async throws
    {
        let fix = try await Self.fixture()
        let extra = try await fix.harness.song("Extra")
        let request = try await fix.harness.song("Requested")
        let show = try await Self.start(fix)
        _ = try await show.perform(.next) // into the medley: member a
        _ = try await show.perform(.insertNext(extra.id))
        var record = await show.state.record
        #expect(record.items.map(\.title)
            == ["Song 1", "Song 2", "Song 3", "Song 4", "Extra", "Song 5"])
        #expect(record.currentItemId == fix.members[0])

        // Play Now of a pending song outside the medley moves it after the medley.
        _ = try await show.perform(.playNow(fix.songs[4].id))
        record = await show.state.record
        #expect(record.items.map(\.title)
            == ["Song 1", "Song 2", "Song 3", "Song 4", "Song 5", "Extra"])
        #expect(record.currentItemId == fix.members[0])

        // A request played during the medley waits right after it.
        _ = try await show.perform(.addRequest(request.id, note: nil))
        _ = try await show.perform(.playNextRequest)
        record = await show.state.record
        #expect(record.items.map(\.title)
            == ["Song 1", "Song 2", "Song 3", "Song 4", "Requested", "Song 5", "Extra"])
        #expect(record.currentItemId == fix.members[0])
        #expect(record.items[4].state == .pending)

        // Play Now of a pending member of this medley jumps to it.
        _ = try await show.perform(.playNow(fix.songs[3].id))
        record = await show.state.record
        #expect(record.currentItemId == fix.members[2])

        // Outside a medley, Play Now interrupts as today.
        _ = try await show.perform(.next)
        _ = try await show.perform(.playNow(fix.songs[4].id))
        record = await show.state.record
        #expect(record.currentItem?.title == "Song 5")
    }

    @Test
    func `with a reprise pending twice, play now takes the first pending after current`()
        async throws
    {
        let fix = try await Self.fixture(reprise: true)
        let show = try await Self.start(fix)
        var record = await show.state.record
        // Song 2 is member a and the last slot.
        #expect(record.items.map(\.title)
            == ["Song 1", "Song 2", "Song 3", "Song 4", "Song 5", "Song 2"])
        // From song 1 (before the medley): Play Now of song 2 takes member a.
        _ = try await show.perform(.playNow(fix.songs[1].id))
        record = await show.state.record
        #expect(record.currentItemId == fix.members[0])
        // Played as a member, the reprise still stands as upcoming: never refused.
        _ = try await show.perform(.next)
        _ = try await show.perform(.next)
        _ = try await show.perform(.next) // song 5
        _ = try await show.perform(.playNow(fix.songs[1].id))
        record = await show.state.record
        #expect(record.currentItemId == record.items.last?.itemId)
        #expect(record.items.filter { $0.songId == fix.songs[1].id }.map(\.state)
            == [.played, .current])
    }

    @Test
    func `the drawer moves a medley as one block`() async throws {
        let fix = try await Self.fixture()
        let show = try await Self.start(fix)
        // Drag member b (row 2) to the end: the whole medley moves.
        _ = try await show.perform(.move(fromOffsets: [2], toOffset: 5))
        var record = await show.state.record
        #expect(record.items.map(\.title)
            == ["Song 1", "Song 5", "Song 2", "Song 3", "Song 4"])
        // A drop between two members lands after the medley.
        _ = try await show.perform(.move(fromOffsets: [1], toOffset: 3))
        record = await show.state.record
        #expect(record.items.map(\.title)
            == ["Song 1", "Song 2", "Song 3", "Song 4", "Song 5"])
    }

    @Test
    func `the reorder review treats a medley as one slot`() async throws {
        let fix = try await Self.fixture()
        let show = try await Self.start(fix)
        for _ in 0 ..< 4 {
            _ = try await show.perform(.next)
        }
        let unchanged = try await show.end()
        #expect(unchanged.diff == nil)

        let moved = try await Self.start(fix)
        _ = try await moved.perform(.move(fromOffsets: [4], toOffset: 0))
        for _ in 0 ..< 4 {
            _ = try await moved.perform(.next)
        }
        let ending = try await moved.end()
        let diff = try #require(ending.diff)
        let saved = diff.entries(including: diff.defaultIncluded)
        #expect(saved.map(\.itemId) == [
            fix.setlist.entries[2].itemId, fix.setlist.entries[0].itemId, fix.medley,
        ])
        #expect(saved[2] == fix.setlist.entries[1])
        #expect(diff.performed.filter { $0.item.medley != nil }.map(\.change)
            == [.unchanged, .unchanged, .unchanged])
    }

    @Test
    func `the gig log nests played members under their medley, with skipped ones`()
        async throws
    {
        let fix = try await Self.fixture(reprise: true)
        let show = try await Self.start(fix)
        _ = try await show.perform(.next) // member a
        _ = try await show.perform(.next) // member b
        _ = try await show.perform(.skipCurrent) // member b skipped, c current
        _ = try await show.perform(.next) // song 5
        _ = try await show.perform(.next) // the reprise
        let ending = try await show.end()
        let entry = try #require(ending.gigLogEntry)
        #expect(entry.slots.count == 4)
        guard case let .medley(slot, title, members, skipped) = entry.slots[1] else {
            Issue.record("expected the medley as the second slot")
            return
        }
        #expect(slot == fix.medley)
        #expect(title == "Love medley")
        #expect(members.map(\.item.title) == ["Song 2", "Song 4"])
        #expect(skipped.map(\.itemId) == [fix.members[1]])
        // The reprise: two plays of song 2 in one gig.
        let plays = ending.record.playRecords.filter { $0.songId == fix.songs[1].id }
        #expect(plays.count == 2)
    }
}
