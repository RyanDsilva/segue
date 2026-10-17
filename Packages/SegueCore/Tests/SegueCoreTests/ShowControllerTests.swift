import Foundation
import Library
import Setlists
import Shows
import Support
import Testing

/// `ShowController` edge cases and invariants on a real temp library.
struct ShowControllerTests {
    /// Random command sequences: item IDs stay unique, the setlist items are always the
    /// planned entries (as a permutation) plus inserted songs and played requests, exactly
    /// one item is current while one is set, and every file written reloads to the state.
    @Test(arguments: [UInt64(1), 2, 3, 4, 5, 6])
    func `random command sequences keep the show consistent`(seed: UInt64) async throws {
        let harness = try await ShowHarness(seed: seed)
        let (setlist, songs) = try await harness.makeSet(6)
        let extras = try await [harness.song("Extra A"), harness.song("Extra B")]
        let show = try await ShowController.start(
            setlist: setlist,
            kind: .gig,
            environment: harness.environment(),
        )
        var random = SeededGenerator(state: seed)
        let library = (songs + extras).map(\.id)
        for step in 0 ..< 60 {
            harness.lib.clock.advance(by: Double(Int.random(in: 1 ... 300, using: &random)))
            let record = await show.state.record
            let action = Self.randomAction(record, songs: library, using: &random)
            do {
                let state = try await show.perform(action)
                try await Self.checkInvariants(state, planned: setlist.entries, harness)
            } catch ShowError.invalidOffsets {
                Issue.record("step \(step): generated offsets must be valid")
            }
            if Bool.random(using: &random) {
                try await show.updateScrollPosition(Double.random(in: 0 ... 1, using: &random))
            }
        }
        let ending = try await show.end()
        try await Self.checkInvariants(
            ShowState(record: ending.record, current: nil, upNext: nil),
            planned: setlist.entries,
            harness,
        )
        #expect(ending.record.items.allSatisfy { $0.state != .current })
        let entry = try #require(ending.gigLogEntry)
        #expect(Set(entry.played.map(\.item.itemId)).count == entry.played.count)
        #expect(entry.played.allSatisfy { $0.duration >= 0 })
        if let diff = ending.diff {
            let saved = diff.entries(including: diff.defaultIncluded)
            #expect(Set(saved.map(\.itemId)).count == saved.count)
            #expect(Set(setlist.entries.map(\.itemId)).isSubset(of: saved.map(\.itemId)))
        }
    }

    private static func randomAction(
        _ record: ShowRecord,
        songs: [SongID],
        using random: inout SeededGenerator,
    ) -> ShowAction {
        let item = record.items.randomElement(using: &random)?.itemId ?? record.items[0].itemId
        let song = songs.randomElement(using: &random) ?? songs[0]
        let request = record.requests.randomElement(using: &random)?.requestId
        let count = record.items.count
        let move = ShowAction.move(
            fromOffsets: [Int.random(in: 0 ..< count, using: &random)],
            toOffset: Int.random(in: 0 ... count, using: &random),
        )
        var choices: [ShowAction] = [
            .next, .next, .next, .previous, .skipCurrent, .skip(item), .unskip(item),
            .jump(item), .playNow(song), .insertNext(song), .addRequest(song, note: nil),
            .playNextRequest, move,
        ]
        if let request {
            choices += [.playRequest(request), .dropRequest(request)]
        }
        return choices.randomElement(using: &random) ?? .next
    }

    private static func checkInvariants(
        _ state: ShowState,
        planned: [SetlistEntry],
        _ harness: ShowHarness,
    ) async throws {
        let record = state.record
        let ids = record.items.map(\.itemId)
        #expect(Set(ids).count == ids.count)
        let fromSetlist = record.items.filter { $0.origin == .setlist }.map(\.itemId)
        #expect(Set(fromSetlist) == Set(planned.map(\.itemId)))
        #expect(fromSetlist.count == planned.count)
        let current = record.items.filter { $0.state == .current }
        #expect(current.map(\.itemId) == (record.currentItemId.map { [$0] } ?? []))
        #expect(state.current?.item.itemId == record.currentItemId)
        let requested = record.items.compactMap(\.requestId)
        let playedRequests = record.requests.filter { $0.state == .played }.map(\.requestId)
        #expect(Set(requested).count == requested.count)
        #expect(Set(requested) == Set(playedRequests))
        // A scroll still inside its debounce window is the only thing allowed to be newer
        // in memory than on disk (a no-op action does not write it).
        var reloaded = try #require(try await harness.reloadedShow(record.id))
        if reloaded != record {
            reloaded.scrollPosition = record.scrollPosition
            reloaded.updatedAt = record.updatedAt
        }
        #expect(reloaded == record)
    }

    @Test
    func `actions that change nothing do not write`() async throws {
        let harness = try await ShowHarness()
        let (setlist, _) = try await harness.makeSet(2)
        let show = try await ShowController.start(
            setlist: setlist,
            kind: .gig,
            environment: harness.environment(),
        )
        let start = await show.state
        let path = harness.showPath(start.record.id)
        let bytes = try harness.lib.bytes(path)
        harness.lib.clock.advance(by: 10)
        #expect(try await show.perform(.previous) == start)
        #expect(try await show.perform(.playNextRequest) == start)
        #expect(try await show.perform(.jump(start.record.items[0].itemId)) == start)
        #expect(try await show.perform(.unskip(start.record.items[1].itemId)) == start)
        #expect(try await show.perform(.move(fromOffsets: [1], toOffset: 2)) == start)
        #expect(try harness.lib.bytes(path) == bytes)

        let missing = ShowItemID(harness.lib.ids.next())
        await #expect(throws: ShowError.itemNotFound(missing)) {
            try await show.perform(.skip(missing))
        }
        await #expect(throws: ShowError.invalidOffsets) {
            try await show.perform(.move(fromOffsets: [2], toOffset: 0))
        }
        let ghost = SongID(harness.lib.ids.next())
        await #expect(throws: ShowError.songNotFound(ghost)) {
            try await show.perform(.addRequest(ghost, note: nil))
        }
        let request = ShowRequestID(harness.lib.ids.next())
        await #expect(throws: ShowError.requestNotFound(request)) {
            try await show.perform(.dropRequest(request))
        }

        // Past the end: nothing current, `next` and `skipCurrent` do nothing more.
        try await show.perform(.next)
        let end = try await show.perform(.next)
        #expect(end.current == nil)
        #expect(end.upNext == nil)
        #expect(try await show.perform(.next) == end)
        #expect(try await show.perform(.skipCurrent) == end)
        // `previous` from the end returns to the last song played.
        #expect(try await show.perform(.previous).currentTitle == "Song 2")

        _ = try await show.end()
        await #expect(throws: ShowError.finished(start.record.id)) {
            try await show.perform(.next)
        }
        await #expect(throws: ShowError.finished(start.record.id)) {
            try await show.end()
        }
    }

    @Test
    func `skip, unskip, insert next and drop request`() async throws {
        let harness = try await ShowHarness()
        let (setlist, _) = try await harness.makeSet(4)
        let extra = try await harness.song("Extra")
        let show = try await ShowController.start(
            setlist: setlist,
            kind: .gig,
            environment: harness.environment(),
        )
        let items = await show.state.record.items
        var state = try await show.perform(.skip(items[1].itemId))
        #expect(state.titles(.skipped) == ["Song 2"])
        guard case let .item(upNext)? = state.upNext else {
            Issue.record("expected an up-next item")
            return
        }
        #expect(upNext.item.title == "Song 3")
        state = try await show.perform(.insertNext(extra.id))
        #expect(state.record.items.map(\.title) == [
            "Song 1",
            "Extra",
            "Song 2",
            "Song 3",
            "Song 4",
        ])
        #expect(state.record.items[1].origin == .inserted)
        state = try await show.perform(.next)
        #expect(state.currentTitle == "Extra")
        state = try await show.perform(.unskip(items[1].itemId))
        #expect(state.titles(.skipped).isEmpty)
        #expect(try await show.perform(.next).currentTitle == "Song 2")

        // Skipping current from the drawer is `skipCurrent`.
        state = try await show.perform(.skip(items[1].itemId))
        #expect(state.currentTitle == "Song 3")
        #expect(state.titles(.skipped) == ["Song 2"])

        state = try await show.perform(.addRequest(extra.id, note: "   "))
        let request = try #require(state.record.requests.first)
        #expect(request.note == nil)
        state = try await show.perform(.dropRequest(request.requestId))
        #expect(state.record.queuedRequests.isEmpty)
        #expect(try await show.perform(.playRequest(request.requestId)) == state)
        #expect(try await show.perform(.playNextRequest) == state)
    }

    /// A failed write keeps the action (the stage goes on), reports `writeFailed`, and the
    /// next action writes everything.
    @Test
    func `a failed write keeps the action and is retried`() async throws {
        let fileSystem = InstrumentedFileSystem()
        let harness = try await ShowHarness(fileSystem: fileSystem)
        let (setlist, _) = try await harness.makeSet(3)
        let show = try await ShowController.start(
            setlist: setlist,
            kind: .gig,
            environment: harness.environment(),
        )
        let id = await show.state.record.id
        fileSystem.fail(.write, suffix: LibraryRoot.showSuffix)
        await #expect(throws: ShowError.writeFailed("Injected failure")) {
            try await show.perform(.next)
        }
        #expect(await show.state.currentTitle == "Song 2")
        #expect(try await harness.reloadedShow(id)?.currentItem?.title == "Song 1")

        fileSystem.heal()
        harness.lib.clock.advance(by: 2)
        try await show.flushScrollPositionIfDue()
        #expect(try await harness.reloadedShow(id) == show.state.record)

        fileSystem.fail(.write, suffix: LibraryRoot.showSuffix)
        await #expect(throws: ShowError.writeFailed("Injected failure")) {
            try await show.end()
        }
        fileSystem.heal()
        let ending = try await show.end()
        #expect(try await harness.reloadedShow(id) == ending.record)
        #expect(ending.record.isFinished)
    }

    @Test
    func `read-only and finished shows cannot be resumed`() async throws {
        let harness = try await ShowHarness()
        let (setlist, _) = try await harness.makeSet(2)
        let show = try await ShowController.start(
            setlist: setlist,
            kind: .gig,
            environment: harness.environment(),
        )
        let ending = try await show.end()
        await #expect(throws: ShowError.finished(ending.record.id)) {
            try await ShowController.resume(ending.record, environment: harness.environment())
        }
        var newer = ending.record
        newer.endedAt = nil
        newer.readOnly = .newerSchema(found: 2, supported: 1)
        await #expect(throws: ShowError.readOnly(newer.id, .newerSchema(found: 2, supported: 1))) {
            try await ShowController.resume(newer, environment: harness.environment())
        }
    }
}
