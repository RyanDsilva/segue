import Foundation
import Library
import Setlists
import Shows
import Support
import Testing

/// Crash safety and recovery: resume, stale close, snapshots, rehearsal runs.
struct ShowRecoveryTests {
    /// E2E #2: advance to song 5, scroll halfway, kill, relaunch: resume lands on song 5 at
    /// the same scroll position. A scroll newer than the debounce window may be lost.
    @Test
    func `crash mid show resumes at the same song and scroll position`() async throws {
        let harness = try await ShowHarness()
        let (setlist, _) = try await harness.makeSet(8)
        var show: ShowController? = try await ShowController.start(
            setlist: setlist,
            kind: .gig,
            environment: harness.environment(),
        )
        let id = try #require(await show?.state.record.id)
        for _ in 1 ... 4 {
            harness.lib.clock.advance(by: 120)
            try await show?.perform(.next)
        }
        // Debounce: the first scroll after an action waits for the 1 s window.
        harness.lib.clock.advance(by: 0.4)
        try await show?.updateScrollPosition(0.3)
        #expect(try await harness.reloadedShow(id)?.scrollPosition == 0)
        harness.lib.clock.advance(by: 0.7)
        try await show?.flushScrollPositionIfDue()
        #expect(try await harness.reloadedShow(id)?.scrollPosition == 0.3)
        harness.lib.clock.advance(by: 1)
        try await show?.updateScrollPosition(0.5)
        #expect(try await harness.reloadedShow(id)?.scrollPosition == 0.5)
        // Within the window: not on disk yet (at most a second of scroll is lost).
        harness.lib.clock.advance(by: 0.5)
        try await show?.updateScrollPosition(0.55)
        try await show?.flushScrollPositionIfDue()
        #expect(try await harness.reloadedShow(id)?.scrollPosition == 0.5)

        show = nil // kill -9
        harness.lib.clock.advance(by: 90)
        try await harness.relaunch()
        let check = try await harness.shows.launchCheck()
        #expect(check.autoClosed.isEmpty)
        let pending = try #require(check.resumable)
        #expect(pending.id == id)
        #expect(pending.currentItem?.title == "Song 5")
        #expect(pending.scrollPosition == 0.5)

        let resumed = try await ShowController.resume(pending, environment: harness.environment())
        let state = await resumed.state
        #expect(state.currentTitle == "Song 5")
        #expect(state.current?.song?.document.metadata.title == "Song 5")
        #expect(state.record.scrollPosition == 0.5)
        #expect(state.record.events.last?.kind == .resumed)
        #expect(try await harness.reloadedShow(id) == state.record)
        harness.lib.clock.advance(by: 60)
        #expect(try await resumed.perform(.next).currentTitle == "Song 6")
        #expect(try await resumed.perform(.previous).currentTitle == "Song 5")
    }

    /// Decisions round 2 + open question 15: an unfinished show untouched for 12 hours is
    /// closed into the gig log at its last update on the next launch; the reorder diff is
    /// offered then. A fresher one is offered for resume instead.
    @Test
    func `stale show is closed into the gig log and a fresh one is resumable`() async throws {
        let harness = try await ShowHarness()
        let (setlist, songs) = try await harness.makeSet(5)
        let stale = try await ShowController.start(
            setlist: setlist,
            kind: .gig,
            environment: harness.environment(),
        )
        harness.lib.clock.advance(by: 200)
        try await stale.perform(.next)
        harness.lib.clock.advance(by: 30)
        try await stale.perform(.move(fromOffsets: [4], toOffset: 2))
        let lastUpdate = await stale.state.record.updatedAt

        harness.lib.clock.advance(by: 13 * 60 * 60)
        let fresh = try await ShowController.start(
            setlist: setlist,
            kind: .gig,
            environment: harness.environment(),
        )
        let freshID = await fresh.state.record.id
        harness.lib.clock.advance(by: 60)

        // kill -9: the process dies and the OS drops both runs' claims.
        await stale.relinquish()
        await fresh.relinquish()
        try await harness.relaunch()
        let check = try await harness.shows.launchCheck()
        #expect(check.resumable?.id == freshID)
        let closed = try #require(check.autoClosed.first)
        #expect(check.autoClosed.count == 1)
        #expect(closed.record.closure == .stale)
        #expect(closed.record.endedAt == lastUpdate)
        #expect(closed.record.events.last?.kind == .autoClosed)
        let entry = try #require(closed.gigLogEntry)
        #expect(entry.played.map(\.item.title) == ["Song 1", "Song 2"])
        #expect(entry.closure == .stale)
        let diff = try #require(closed.diff)
        #expect(diff.performed.map(\.item.title) == [
            "Song 1", "Song 2", "Song 5", "Song 3", "Song 4",
        ])
        #expect(diff.performed[2].change == .moved(fromPosition: 4))

        // Written back: a second launch has nothing left to close, and plays are projected.
        try await harness.relaunch()
        let again = try await harness.shows.launchCheck()
        #expect(again.autoClosed.isEmpty)
        #expect(again.resumable?.id == freshID)
        #expect(await harness.shows.gigLog().map(\.closure) == [.stale])
        #expect(try await harness.library.playStats()[songs[1].id]?.timesPlayed == 1)
    }

    /// Crash safety: the live view keeps its in-memory snapshot. An external edit to the
    /// current song applies only when it next becomes current; a deleted file keeps the
    /// last snapshot.
    @Test
    func `external edits apply on next advance and deleted songs keep their snapshot`(
    ) async throws {
        let harness = try await ShowHarness()
        let (setlist, songs) = try await harness.makeSet(3)
        let show = try await ShowController.start(
            setlist: setlist,
            kind: .gig,
            environment: harness.environment(),
        )
        try harness.lib.write("{title: Song 1 (edited)}\n[D]New words\n", to: songs[0].relativePath)
        #expect(await show.state.current?.song?.document.metadata.title == "Song 1")
        try await show.perform(.next)
        let back = try await show.perform(.previous)
        #expect(back.current?.song?.document.metadata.title == "Song 1 (edited)")
        // The item keeps the title it started with (the gig log reads the same).
        #expect(back.currentTitle == "Song 1")

        try await show.perform(.next)
        try FileManager.default.removeItem(at: harness.lib.url(songs[1].relativePath))
        let current = await show.state.current
        #expect(current?.song?.id == songs[1].id)
        // Going back and forth re-reads a gone file: the last snapshot stays.
        try await show.perform(.next)
        let again = try await show.perform(.previous)
        #expect(again.currentTitle == "Song 2")
        #expect(again.current?.song?.document.metadata.title == "Song 2")
    }

    /// Rehearse-setlist runs: crash resume like a show, timings to `timings/`, never in the
    /// gig log, play stats or reorder sheet.
    @Test
    func `rehearsal resumes after a crash and only records timings`() async throws {
        let harness = try await ShowHarness()
        let (setlist, songs) = try await harness.makeSet(4)
        var timings = harness.timings(run: harness.lib.ids.next(), setlist: setlist)
        var show: ShowController? = try await ShowController.start(
            setlist: setlist,
            kind: .rehearsal,
            environment: harness.environment(durations: timings),
        )
        let id = try #require(await show?.state.record.id)
        harness.lib.clock.advance(by: 150)
        try await show?.perform(.next)
        harness.lib.clock.advance(by: 210)
        try await show?.perform(.move(fromOffsets: [3], toOffset: 2))
        try await show?.perform(.next)
        #expect(harness.lib.exists("timings/\(id)\(LibraryRoot.rehearsalSuffix)"))

        show = nil // kill -9
        harness.lib.clock.advance(by: 30)
        try await harness.relaunch()
        let pending = try #require(try await harness.shows.launchCheck().resumable)
        #expect(pending.kind == .rehearsal)
        #expect(pending.currentItem?.title == "Song 4")
        timings = harness.timings(run: id.ulid, setlist: setlist)
        let resumed = try await ShowController.resume(
            pending,
            environment: harness.environment(durations: timings),
        )
        harness.lib.clock.advance(by: 100)
        let ending = try await resumed.end()
        #expect(ending.diff == nil)
        #expect(ending.gigLogEntry == nil)
        #expect(ending.record.isFinished)

        let samples = try RehearsalTimingStore.loadAll(
            root: harness.lib.root,
            fileSystem: harness.fileSystem,
        )
        // Song 4 counts from the resume (100 s), not across the 30 s the app was down.
        #expect(samples.map(\.seconds) == [150, 210, 100])
        #expect(samples.map(\.songId) == [songs[0].id, songs[1].id, songs[3].id])
        #expect(samples.allSatisfy { $0.source == .rehearsal && $0.runId == id.ulid })
        #expect(try await timings.samples == samples)

        try await harness.relaunch()
        #expect(await harness.shows.gigLog().isEmpty)
        #expect(try await harness.shows.launchCheck() == LaunchShowCheck())
        #expect(try await harness.library.playStats().isEmpty)
    }
}
