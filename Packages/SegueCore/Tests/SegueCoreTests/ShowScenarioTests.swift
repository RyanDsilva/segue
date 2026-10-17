import Foundation
import Library
import Setlists
import Shows
import Support
import Testing

/// The spec's show scenarios, driven through the real `ShowController` against a real temp
/// library, asserting on the files written and on what a fresh store reads back.
struct ShowScenarioTests {
    /// The reorder review numbers a moved song by its planned position: E2E #5/#6's path
    /// (Play now on song 7, then "Next" on song 9) marks song 9 "moved from #9", not the
    /// song 8 it was dropped past; dragging song 3 below song 4 marks song 3, not song 4.
    @Test(arguments: [
        // (actions, the moved song, its planned position 1-based)
        ("play-now-then-next", "Song 9", 9),
        ("drag-down", "Song 3", 3),
        ("drag-up", "Song 6", 6),
    ])
    func `the moved song is numbered by its planned position`(
        scenario: String,
        moved: String,
        planned: Int,
    ) async throws {
        let harness = try await ShowHarness()
        let (setlist, songs) = try await harness.makeSet(10)
        let show = try await ShowController.start(
            setlist: setlist,
            kind: .gig,
            environment: harness.environment(),
        )
        func index(_ title: String) async -> Int {
            await show.state.record.items.firstIndex { $0.title == title } ?? -1
        }
        switch scenario {
        case "play-now-then-next":
            _ = try await show.perform(.next)
            _ = try await show.perform(.next)
            _ = try await show.perform(.playNow(songs[6].id))
            #expect(await show.state.currentTitle == "Song 7")
            // The drawer's "Next": right after the current song.
            let current = await show.state.current?.position ?? 0
            _ = try await show.perform(.move(
                fromOffsets: [index("Song 9")],
                toOffset: current + 1,
            ))
            _ = try await show.perform(.next)
            #expect(await show.state.currentTitle == "Song 9")
        case "drag-down":
            // Song 3 dropped after song 4.
            _ = try await show.perform(.move(fromOffsets: [2], toOffset: 4))
        default:
            // Song 6 dropped before song 5.
            _ = try await show.perform(.move(fromOffsets: [5], toOffset: 4))
        }
        let ending = try await show.end()
        let diff = try #require(ending.diff)
        let changed = diff.performed.filter { $0.change != .unchanged }
        #expect(changed.map(\.item.title) == [moved])
        #expect(changed.first?.change == .moved(fromPosition: planned - 1))
        // The planned column the sheet shows numbers the same song the same way.
        let plannedTitles = diff.planned.map { entry in
            diff.performed.first { $0.item.itemId == entry.itemId }?.item.title
        }
        #expect(plannedTitles[planned - 1] == moved)
    }

    /// E2E #1 at the engine level: 10-song set, play 3, skip 4, a request via `R`, play to
    /// the end. 9 set songs + 1 request played, 1 skipped; the projection updates.
    @Test
    func `friday gig writes every action and ends in the gig log`() async throws {
        let harness = try await ShowHarness()
        let (setlist, songs) = try await harness.makeSet(10)
        let request = try await harness.song("Pyaar Ki Raah")
        let samples = SampleRecorder()
        let show = try await ShowController.start(
            setlist: setlist,
            kind: .gig,
            environment: harness.environment(durations: samples),
        )
        let id = await show.state.record.id
        #expect(await show.state.currentTitle == "Song 1")
        #expect(try await harness.reloadedShow(id) == show.state.record)

        // Applies `action` after `seconds` on stage, then checks the file matches the state.
        func act(_ action: ShowAction, after seconds: TimeInterval = 180) async throws {
            harness.lib.clock.advance(by: seconds)
            let state = try await show.perform(action)
            #expect(try await harness.reloadedShow(id) == state.record)
        }

        for _ in 1 ... 3 {
            try await act(.next)
        }
        #expect(await show.state.currentTitle == "Song 4")
        try await act(.skipCurrent, after: 5)
        #expect(await show.state.currentTitle == "Song 5")
        try await act(.addRequest(request.id, note: " table 4 "), after: 30)
        guard case let .request(queued, song)? = await show.state.upNext else {
            Issue.record("a queued request should win the footer")
            return
        }
        #expect(queued.note == "table 4")
        #expect(song?.id == request.id)
        try await act(.playNextRequest, after: 30)
        #expect(await show.state.currentTitle == "Pyaar Ki Raah")
        #expect(await show.state.record.items.map(\.title).prefix(6) == [
            "Song 1", "Song 2", "Song 3", "Song 4", "Pyaar Ki Raah", "Song 5",
        ])
        // `next` returns to the interrupted song 5, then plays on to the end.
        for _ in 5 ... 10 {
            try await act(.next)
        }
        #expect(await show.state.currentTitle == "Song 10")
        harness.lib.clock.advance(by: 200)
        let ending = try await show.end()

        try await checkAftermath(of: ending, harness, songs: songs, request: request)
        #expect(await samples.samples.map(\.seconds) == ending.gigLogEntry?.played.map(\.duration))
        #expect(await samples.samples.allSatisfy { $0.source == .show && $0.runId == id.ulid })
        let diff = try #require(ending.diff)
        let saved = diff.entries(including: diff.defaultIncluded)
        #expect(saved.count == 11)
        #expect(saved[4].songId == request.id)
        #expect(Array(saved[..<4] + saved[5...]) == setlist.entries)
    }

    /// After the Friday gig: the gig log entry, the file, the projection and the diff.
    private func checkAftermath(
        of ending: ShowEnding,
        _ harness: ShowHarness,
        songs: [SongRecord],
        request: SongRecord,
    ) async throws {
        let id = ending.record.id
        let entry = try #require(ending.gigLogEntry)
        let playedTitles = (1 ... 3).map { "Song \($0)" } + ["Pyaar Ki Raah"]
            + (5 ... 10).map { "Song \($0)" }
        #expect(entry.played.map(\.item.title) == playedTitles)
        #expect(entry.played.count { !$0.fromRequest } == 9)
        #expect(entry.requestCount == 1)
        #expect(entry.skipped.map(\.title) == ["Song 4"])
        #expect(entry.details.venue == "The Anchor")
        #expect(entry.details.date == CalendarDay("2026-10-23"))
        #expect(entry.played.first?.duration == 180)
        #expect(entry.played.last?.duration == 200)

        // On disk: finished, and the gig log reads it back after a relaunch.
        try await harness.relaunch()
        let reloaded = try #require(await harness.shows.show(id: id))
        #expect(reloaded == ending.record)
        #expect(reloaded.closure == .ended)
        #expect(await harness.shows.gigLog().map(\.id) == [id])
        #expect(try await harness.shows.launchCheck() == LaunchShowCheck())

        // Projection through GRDB: "times played" and "last played".
        let stats = try await harness.library.playStats()
        #expect(stats[songs[0].id]?.timesPlayed == 1)
        #expect(stats[songs[3].id] == nil)
        #expect(stats[request.id]?.timesPlayed == 1)
        #expect(stats[songs[9].id]?.lastPlayed == entry.played.last?.startedAt)

        // The request makes the diff sheet appear, ticked by default.
        let diff = try #require(ending.diff)
        #expect(diff.insertedItemIds.count == 1)
        #expect(diff.defaultIncluded == Set(diff.insertedItemIds))
        #expect(diff.performed.allSatisfy { row in
            if case .moved = row.change {
                return false
            }
            return true
        })
    }

    /// E2E #6 and the build ruling on `next`: Play now mid-song 3 on song 7 makes 7 current
    /// and puts 3 back to pending in its slot; `next` goes on after 7, and 3 stays reachable.
    @Test
    func `play now interrupts to pending and next carries on after the jump`() async throws {
        let harness = try await ShowHarness()
        let (setlist, songs) = try await harness.makeSet(10)
        let show = try await ShowController.start(
            setlist: setlist,
            kind: .gig,
            environment: harness.environment(),
        )
        try await show.perform(.next)
        try await show.perform(.next)
        #expect(await show.state.currentTitle == "Song 3")
        var state = try await show.perform(.playNow(songs[6].id))
        #expect(state.currentTitle == "Song 7")
        #expect(state.record.items.map(\.title) == (1 ... 10).map { "Song \($0)" })
        #expect(state.record.items[2].state == .pending)
        #expect(state.record.events.last?.kind == .jumped)
        #expect(state.record.events.last?.fromItemId == state.record.items[2].itemId)

        state = try await show.perform(.next)
        #expect(state.currentTitle == "Song 8")
        #expect(state.titles(.pending) == [
            "Song 3",
            "Song 4",
            "Song 5",
            "Song 6",
            "Song 9",
            "Song 10",
        ])
        // Song 3 is reachable from the drawer, then `next` continues after it.
        state = try await show.perform(.jump(state.record.items[2].itemId))
        #expect(state.currentTitle == "Song 3")
        #expect(state.titles(.pending).first == "Song 4")
        state = try await show.perform(.next)
        #expect(state.currentTitle == "Song 4")

        // Play now on a song outside the set inserts it before current.
        let outside = try await harness.song("Wonderwall")
        state = try await show.perform(.playNow(outside.id))
        #expect(state.currentTitle == "Wonderwall")
        #expect(state.current?.item.origin == .inserted)
        #expect(state.record.items[3].title == "Wonderwall")
        #expect(state.record.items[4].title == "Song 4")
        #expect(state.record.items[4].state == .pending)
        #expect(try await show.perform(.next).currentTitle == "Song 4")

        let ending = try await show.end()
        let diff = try #require(ending.diff)
        #expect(diff.insertedItemIds == [state.record.items[3].itemId])
        #expect(diff.performed.allSatisfy { row in
            if case .moved = row.change {
                return false
            }
            return true
        })
    }

    /// Open question 16: jumps alone never raise the reorder sheet.
    @Test
    func `a show with only jumps ends without a diff`() async throws {
        let harness = try await ShowHarness()
        let (setlist, songs) = try await harness.makeSet(4)
        let show = try await ShowController.start(
            setlist: setlist,
            kind: .gig,
            environment: harness.environment(),
        )
        try await show.perform(.playNow(songs[2].id))
        try await show.perform(.next)
        let ending = try await show.end()
        #expect(ending.diff == nil)
        #expect(ending.gigLogEntry?.played.map(\.item.title) == ["Song 3", "Song 4"])
    }

    /// Build ruling: songs missing at start are removed from the show (not skipped), listed
    /// for the pre-show warning, and Save keeps them in the setlist.
    @Test
    func `missing songs are left out of the show and kept by save`() async throws {
        let harness = try await ShowHarness()
        let (base, _) = try await harness.makeSet(4)
        let ghost = SongID(harness.lib.ids.next())
        let setlist = try await harness.setlists.insertSongs([ghost], into: base.id, at: 1)
        let missing = await ShowController.missingEntries(in: setlist, songs: harness.library)
        #expect(missing.map(\.songId) == [ghost])

        let show = try await ShowController.start(
            setlist: setlist,
            kind: .gig,
            omitting: Set(missing.map(\.itemId)),
            environment: harness.environment(),
        )
        var state = await show.state
        #expect(state.record.items.map(\.title) == ["Song 1", "Song 2", "Song 3", "Song 4"])
        #expect(state.record.omittedEntries == missing)
        #expect(state.record.planned == setlist.entries)

        // No reorder: no sheet, and the gig log does not list it as skipped.
        try await show.perform(.next)
        state = try await show.perform(.move(fromOffsets: [3], toOffset: 2))
        #expect(state.record.items.map(\.title) == ["Song 1", "Song 2", "Song 4", "Song 3"])
        let ending = try await show.end()
        #expect(ending.gigLogEntry?.skipped.isEmpty == true)
        let diff = try #require(ending.diff)
        let saved = diff.entries(including: diff.defaultIncluded)
        #expect(saved.map(\.songId) == [
            setlist.entries[0].songId, ghost, setlist.entries[2].songId,
            setlist.entries[4].songId, setlist.entries[3].songId,
        ])
        #expect(Set(saved.map(\.itemId)) == Set(setlist.entries.map(\.itemId)))

        let all = try await harness.makeSet(1, name: "Ghosts").0
        let ghostsOnly = try await harness.setlists.replaceEntries(
            [SetlistEntry(itemId: all.entries[0].itemId, songId: ghost)],
            in: all.id,
        )
        await #expect(throws: ShowError.emptySetlist) {
            try await ShowController.start(
                setlist: ghostsOnly,
                kind: .gig,
                omitting: [ghostsOnly.entries[0].itemId],
                environment: harness.environment(),
            )
        }
    }

    /// E2E #5: drag song 8 to next; the footer follows. Discard leaves the setlist file
    /// byte-identical; a second run with Save persists the new order.
    @Test
    func `live reorder offers save or discard at show end`() async throws {
        let harness = try await ShowHarness()
        let (setlist, _) = try await harness.makeSet(10)
        let path = "setlists/friday-the-anchor.setlist.json"
        let before = try harness.lib.bytes(path)

        for save in [false, true] {
            let show = try await ShowController.start(
                setlist: #require(await harness.setlists.setlist(id: setlist.id)),
                kind: .gig,
                environment: harness.environment(),
            )
            try await show.perform(.next)
            let state = try await show.perform(.move(fromOffsets: [7], toOffset: 2))
            guard case let .item(next)? = state.upNext else {
                Issue.record("expected an up-next item")
                return
            }
            #expect(next.item.title == "Song 8")
            #expect(state.record.events.last?.kind == .reordered)
            let ending = try await show.end()
            let diff = try #require(ending.diff)
            #expect(diff.insertedItemIds.isEmpty)
            #expect(diff.performed.compactMap { row in
                if case let .moved(from) = row.change {
                    return "\(row.item.title)<-\(from)"
                }
                return nil
            } == ["Song 8<-7"])
            if save {
                let saved = try await harness.setlists.replaceEntries(
                    diff.entries(including: diff.defaultIncluded),
                    in: setlist.id,
                )
                try await harness.relaunch()
                let reloaded = try #require(await harness.setlists.setlist(id: setlist.id))
                #expect(reloaded.entries == saved.entries)
                #expect(reloaded.entries.map(\.itemId) == diff.performed.map(\.item.itemId))
            } else {
                // Discard: nothing to write.
                #expect(try harness.lib.bytes(path) == before)
            }
        }
    }
}

/// A `DurationSampleSink` that keeps samples in memory.
actor SampleRecorder: DurationSampleSink {
    private(set) var samples: [DurationSample] = []

    func record(_ sample: DurationSample) async throws {
        samples.append(sample)
    }
}
