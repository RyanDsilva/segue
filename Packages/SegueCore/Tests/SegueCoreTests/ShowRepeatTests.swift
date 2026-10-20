import Foundation
import Library
import Setlists
import Shows
import Support
import Testing

/// R102 / R112: no song twice within a show, driven through the real `ShowController` on a
/// real temp library.
struct ShowRepeatTests {
    private func start(
        _ harness: ShowHarness,
        _ setlist: Setlist,
        kind: ShowKind = .gig,
    ) async throws -> ShowController {
        try await ShowController.start(
            setlist: setlist,
            kind: kind,
            environment: harness.environment(),
        )
    }

    /// Played means actually played, in gigs and rehearsals alike: Insert Next, a request
    /// and Play Now of it are all refused and change nothing on disk.
    @Test(arguments: [ShowKind.gig, .rehearsal])
    func `a played song cannot be added again`(kind: ShowKind) async throws {
        let harness = try await ShowHarness()
        let (setlist, songs) = try await harness.makeSet(3)
        let show = try await start(harness, setlist, kind: kind)
        let state = try await show.perform(.next)
        #expect(state.record.standing(of: songs[0].id) == .played)
        let bytes = try harness.lib.bytes(harness.showPath(state.record.id))
        for action: ShowAction in [
            .insertNext(songs[0].id), .addRequest(songs[0].id, note: nil), .playNow(songs[0].id),
        ] {
            await #expect(throws: ShowError.repeatRefused(songs[0].id, .alreadyPlayed)) {
                try await show.perform(action)
            }
        }
        #expect(await show.state == state)
        #expect(try harness.lib.bytes(harness.showPath(state.record.id)) == bytes)
    }

    @Test
    func `the current song cannot be inserted or requested`() async throws {
        let harness = try await ShowHarness()
        let (setlist, songs) = try await harness.makeSet(2)
        let show = try await start(harness, setlist)
        for action: ShowAction in [.insertNext(songs[0].id), .addRequest(songs[0].id, note: "x")] {
            await #expect(throws: ShowError.repeatRefused(songs[0].id, .playingNow)) {
                try await show.perform(action)
            }
        }
        // Play Now of the current song stays the no-op it always was.
        let before = await show.state
        #expect(try await show.perform(.playNow(songs[0].id)) == before)
    }

    /// An upcoming song is refused with Move to Next, which moves the existing item: the
    /// song count is unchanged and `next` plays it.
    @Test
    func `insert next of an upcoming song offers move to next`() async throws {
        let harness = try await ShowHarness()
        let (setlist, songs) = try await harness.makeSet(5)
        let show = try await start(harness, setlist)
        let items = await show.state.record.items
        let refusal = RepeatRefusal.upcoming(items[3].itemId, isNext: false)
        await #expect(throws: ShowError.repeatRefused(songs[3].id, refusal)) {
            try await show.perform(.insertNext(songs[3].id))
        }
        await #expect(throws: ShowError.repeatRefused(songs[3].id, refusal)) {
            try await show.perform(.addRequest(songs[3].id, note: nil))
        }
        let move = try #require(refusal.moveToNext)
        var state = try await show.perform(move)
        #expect(state.record.items.map(\.title) == [
            "Song 1",
            "Song 4",
            "Song 2",
            "Song 3",
            "Song 5",
        ])
        #expect(state.record.items.count == 5)
        #expect(state.record.events.last?.kind == .reordered)
        #expect(state.record.standing(of: songs[3].id) == .upcoming(items[3].itemId, isNext: true))
        state = try await show.perform(.next)
        #expect(state.currentTitle == "Song 4")

        // The next song is already next: refused, with nothing to move.
        await #expect(
            throws: ShowError.repeatRefused(songs[1].id, .upcoming(items[1].itemId, isNext: true)),
        ) {
            try await show.perform(.insertNext(songs[1].id))
        }
        #expect(RepeatRefusal.upcoming(items[1].itemId, isNext: true).moveToNext == nil)
        // Play Now of an upcoming song jumps to it: never a second item.
        state = try await show.perform(.playNow(songs[4].id))
        #expect(state.currentTitle == "Song 5")
        #expect(state.record.items.count == 5)

        let ending = try await show.end()
        #expect(ending.diff?.insertedItemIds.isEmpty ?? true)
    }

    /// A request for a song already queued is refused; Move to Next brings it to the front
    /// of the queue; Play Now plays that request instead of adding the song again.
    @Test
    func `a queued request is never queued or inserted twice`() async throws {
        let harness = try await ShowHarness()
        let (setlist, _) = try await harness.makeSet(3)
        let first = try await harness.song("Wonderwall")
        let second = try await harness.song("Pyaar Ki Raah")
        let show = try await start(harness, setlist)
        try await show.perform(.addRequest(first.id, note: "table 4"))
        var state = try await show.perform(.addRequest(second.id, note: nil))
        let requests = state.record.queuedRequests.map(\.requestId)
        let refusal = RepeatRefusal.requested(requests[1], isNext: false)
        for action: ShowAction in [.addRequest(second.id, note: "again"), .insertNext(second.id)] {
            await #expect(throws: ShowError.repeatRefused(second.id, refusal)) {
                try await show.perform(action)
            }
        }
        state = try await show.perform(#require(refusal.moveToNext))
        #expect(state.record.queuedRequests.map(\.requestId) == [requests[1], requests[0]])
        guard case let .request(next, _)? = state.upNext else {
            Issue.record("the moved request should be next")
            return
        }
        #expect(next.requestId == requests[1])

        state = try await show.perform(.playNow(first.id))
        #expect(state.currentTitle == "Wonderwall")
        #expect(state.current?.item.requestId == requests[0])
        #expect(state.record.queuedRequests.map(\.requestId) == [requests[1]])
        #expect(state.record.items.count { $0.songId == first.id } == 1)
    }

    /// R112: a skipped song may be added back, and comes back as its skipped item.
    @Test
    func `a skipped song comes back as the same item`() async throws {
        let harness = try await ShowHarness()
        let (setlist, songs) = try await harness.makeSet(5)
        let show = try await start(harness, setlist)
        let items = await show.state.record.items
        try await show.perform(.skip(items[1].itemId))
        try await show.perform(.skipCurrent)
        var state = try await show.perform(.next)
        #expect(state.currentTitle == "Song 4")
        #expect(state.record.standing(of: songs[1].id) == .skipped(items[1].itemId))

        state = try await show.perform(.insertNext(songs[1].id))
        #expect(state.record.items.count == 5)
        #expect(state.record.items.map(\.title) == [
            "Song 1",
            "Song 3",
            "Song 4",
            "Song 2",
            "Song 5",
        ])
        #expect(state.titles(.pending) == ["Song 2", "Song 5"])

        state = try await show.perform(.playNow(songs[0].id))
        #expect(state.currentTitle == "Song 1")
        #expect(state.record.items.count == 5)
        #expect(state.titles(.skipped).isEmpty)
    }

    /// A skipped item cannot come back while its song is requested (the drawer's unskip).
    @Test
    func `unskip is refused when the song is queued as a request`() async throws {
        let harness = try await ShowHarness()
        let (setlist, songs) = try await harness.makeSet(3)
        let show = try await start(harness, setlist)
        let item = await show.state.record.items[2].itemId
        try await show.perform(.skip(item))
        let state = try await show.perform(.addRequest(songs[2].id, note: nil))
        let request = try #require(state.record.queuedRequests.first?.requestId)
        let refusal = RepeatRefusal.requested(request, isNext: true)
        for action: ShowAction in [.unskip(item), .jump(item), .moveToNext(item)] {
            await #expect(throws: ShowError.repeatRefused(songs[2].id, refusal)) {
                try await show.perform(action)
            }
        }
    }

    /// Break rows (P3-12) are never items, so they never count as songs or block an add.
    @Test
    func `break rows never count as songs`() async throws {
        let harness = try await ShowHarness()
        let (base, songs) = try await harness.makeSet(4)
        let setlist = try await harness.setlists.insertBreak(into: base.id, at: 2)
        let show = try await start(harness, setlist)
        var state = await show.state
        #expect(state.record.items.count == 4)
        let breakId = try #require(setlist.entries.first(where: \.isBreak)?.itemId)
        #expect(!state.record.items.contains { $0.itemId == breakId })
        let extra = try await harness.song("Extra")
        state = try await show.perform(.insertNext(extra.id))
        #expect(state.record.items.count == 5)
        await #expect(throws: ShowError.repeatRefused(
            songs[2].id,
            .upcoming(state.record.items[3].itemId, isNext: false),
        )) {
            try await show.perform(.insertNext(songs[2].id))
        }
    }
}
