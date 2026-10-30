import Foundation
import Library
import Setlists
import Shows
import Support
import Synchronization
import Testing

/// Regression tests for the phase 2 review (docs/reviews/phase2-review.md) at the core
/// level: the real show engine and stores on a temp library.
struct Phase2HardeningTests {
    // MARK: #2 the reorder review merges into the setlist as it is now

    @Test
    func `saving the played order merges into a setlist edited during the show`(
    ) async throws {
        let harness = try await ShowHarness()
        let (setlist, songs) = try await harness.makeSet(4)
        let extra = try await harness.song("Extra")
        let late = try await harness.song("Added Late")
        let show = try await ShowController.start(
            setlist: setlist,
            kind: .gig,
            environment: harness.environment(),
        )
        // Played order: 1, Extra (insert next), 4 (moved up), 2, 3.
        try await show.perform(.move(fromOffsets: [3], toOffset: 1))
        try await show.perform(.insertNext(extra.id))
        // Meanwhile the setlist is edited: entry 3 removed, a song added at the end, and a
        // note on entry 2.
        var edited = try await harness.setlists.remove(in: setlist.id, atOffsets: [2])
        edited = try await harness.setlists.insertSongs([late.id], into: setlist.id)
        var second = try #require(edited.entries.first { $0.songId == songs[1].id })
        second.note = "capo up"
        edited = try await harness.setlists.updateEntry(second, in: setlist.id)

        let diff = try #require(try await show.end().diff)
        #expect(diff.setlistChanged(current: edited.entries))
        #expect(!diff.setlistChanged(current: setlist.entries))
        let merged = diff.entries(mergingInto: edited.entries, including: diff.defaultIncluded)
        let titles = merged.map { entry in
            [songs, [extra, late]].joined().first { $0.id == entry.songId }?.document.metadata
                .title ?? "?"
        }
        // Song 3 stays removed, "Added Late" stays at the end, Song 2 keeps the note added
        // during the show, Extra is inserted where it was played.
        #expect(titles == ["Song 1", "Extra", "Song 4", "Song 2", "Added Late"])
        #expect(merged.first { $0.songId == songs[1].id }?.note == "capo up")
        // Nothing ticked: only the setlist's own entries, reordered.
        #expect(diff.entries(mergingInto: edited.entries, including: []).count == 4)
    }

    // MARK: #3 play now of the current song

    @Test
    func `play now of the current song is a no-op and never duplicates it`() async throws {
        let harness = try await ShowHarness()
        let (setlist, songs) = try await harness.makeSet(3)
        let extra = try await harness.song("Extra")
        let show = try await ShowController.start(
            setlist: setlist,
            kind: .gig,
            environment: harness.environment(),
        )
        let before = await show.state
        let same = try await show.perform(.playNow(songs[0].id))
        #expect(same == before)
        // Twice in a row (a double Return): one inserted item, no ghost pending copy.
        _ = try await show.perform(.playNow(extra.id))
        let twice = try await show.perform(.playNow(extra.id))
        #expect(twice.record.items.count { $0.songId == extra.id } == 1)
        #expect(twice.currentTitle == "Extra")
        #expect(twice.titles(.pending) == ["Song 1", "Song 2", "Song 3"])
    }

    // MARK: #6 a late scroll flush never lands on the next song

    @Test
    func `a scroll position for an item that is no longer current is dropped`(
    ) async throws {
        let harness = try await ShowHarness()
        let (setlist, _) = try await harness.makeSet(3)
        let show = try await ShowController.start(
            setlist: setlist,
            kind: .gig,
            environment: harness.environment(),
        )
        let first = try #require(await show.state.current?.item.itemId)
        try await show.perform(.next)
        harness.lib.clock.advance(by: 5)
        try await show.updateScrollPosition(0.8, for: first)
        try await show.flushScrollPositionIfDue()
        #expect(await show.state.record.scrollPosition == 0)
        let id = await show.state.record.id
        #expect(try await harness.reloadedShow(id)?.scrollPosition == 0)
        let second = try #require(await show.state.current?.item.itemId)
        try await show.updateScrollPosition(0.4, for: second)
        #expect(await show.state.record.scrollPosition == 0.4)
    }

    // MARK: #7 a resume restarts the current song's clock

    @Test
    func `the gap before a resume is not counted in the song's duration`() async throws {
        let harness = try await ShowHarness()
        let (setlist, _) = try await harness.makeSet(3)
        var show: ShowController? = try await ShowController.start(
            setlist: setlist,
            kind: .gig,
            environment: harness.environment(),
        )
        harness.lib.clock.advance(by: 100)
        show = nil // kill -9 during song 1
        harness.lib.clock.advance(by: 3600)
        try await harness.relaunch()
        let pending = try #require(try await harness.shows.launchCheck().resumable)
        show = try await ShowController.resume(pending, environment: harness.environment())
        harness.lib.clock.advance(by: 120)
        let ending = try #require(try await show?.end())
        let entry = try #require(ending.gigLogEntry)
        #expect(entry.played.map(\.duration) == [120])
    }

    // MARK: #9 a show can only be held by one run

    @Test
    func `a show held by one run cannot be resumed or closed by another`() async throws {
        let harness = try await ShowHarness()
        let (setlist, _) = try await harness.makeSet(3)
        let show = try await ShowController.start(
            setlist: setlist,
            kind: .gig,
            environment: harness.environment(),
        )
        let record = await show.state.record
        let lock = harness.lib.url("shows/\(record.id).show.lock")
        #expect(FileManager.default.fileExists(atPath: lock.path))

        // A second window or process: fresh stores on the same folder.
        try await harness.relaunch()
        await #expect(throws: ShowError.claimedElsewhere(record.id)) {
            try await ShowController.resume(record, environment: harness.environment())
        }
        // Its launch check neither offers nor closes the show being performed.
        harness.lib.clock.advance(by: 13 * 60 * 60)
        #expect(try await harness.shows.launchCheck() == LaunchShowCheck())
        #expect(try await harness.reloadedShow(record.id)?.isFinished == false)

        // The holder dies (the OS drops the lock): the show is resumable again, and once
        // it ends the lock file goes away.
        await show.relinquish()
        harness.lib.clock.set(record.updatedAt.addingTimeInterval(60))
        try await harness.relaunch()
        let pending = try #require(try await harness.shows.launchCheck().resumable)
        let resumed = try await ShowController.resume(pending, environment: harness.environment())
        _ = try await resumed.end()
        #expect(!FileManager.default.fileExists(atPath: lock.path))
    }

    @Test
    func `resume picks up the latest record on disk`() async throws {
        let harness = try await ShowHarness()
        let (setlist, _) = try await harness.makeSet(3)
        let show = try await ShowController.start(
            setlist: setlist,
            kind: .gig,
            environment: harness.environment(),
        )
        let offered = await show.state.record
        try await show.perform(.next)
        await show.relinquish()
        // Resuming the record offered before the advance resumes from the file instead.
        let resumed = try await ShowController.resume(offered, environment: harness.environment())
        #expect(await resumed.state.currentTitle == "Song 2")
        await resumed.relinquish()
    }

    // MARK: Nit: a write never acknowledges before it landed

    @Test
    func `an action returns only once its record is on disk`() async throws {
        let fileSystem = InstrumentedFileSystem()
        let harness = try await ShowHarness(fileSystem: fileSystem)
        let (setlist, _) = try await harness.makeSet(4)
        let show = try await ShowController.start(
            setlist: setlist,
            kind: .gig,
            environment: harness.environment(),
        )
        let id = await show.state.record.id
        fileSystem.slowDown(writes: LibraryRoot.showSuffix, by: 0.2)
        let first = Task { try await show.perform(.next) }
        try await Task.sleep(for: .milliseconds(50))
        // The first write is in flight: this one must wait for the loop to write it too.
        let state = try await show.perform(.next)
        #expect(try await harness.reloadedShow(id) == state.record)
        _ = try await first.value
        // The state is built from one record: up next follows the current item.
        let final = await show.state
        #expect(final.currentTitle == "Song 3")
        guard case let .item(next) = final.upNext else {
            Issue.record("expected an up-next item")
            return
        }
        #expect(next.item.title == "Song 4")
        #expect(await !show.hasUnsavedChanges)
    }

    // MARK: Nit: scroll durability within a second

    @Test
    func `a scroll change reaches disk within a second at the stage's flush tick`(
    ) async throws {
        let harness = try await ShowHarness()
        let (setlist, _) = try await harness.makeSet(2)
        let show = try await ShowController.start(
            setlist: setlist,
            kind: .gig,
            environment: harness.environment(),
        )
        let id = await show.state.record.id
        // Worst case: the change comes right after a write.
        harness.lib.clock.advance(by: 0.01)
        try await show.updateScrollPosition(0.25)
        var landed: Double?
        for tick in 1 ... 8 {
            harness.lib.clock.advance(by: 0.25)
            try await show.flushScrollPositionIfDue()
            if try await harness.reloadedShow(id)?.scrollPosition == 0.25 {
                landed = Double(tick) * 0.25
                break
            }
        }
        let after = try #require(landed, "never written")
        #expect(after <= 1)
    }

    // MARK: Nit: reorder reviews are stored until answered

    @Test
    func `a reorder review stays pending across relaunches until it is answered`(
    ) async throws {
        let harness = try await ShowHarness()
        let (setlist, _) = try await harness.makeSet(3)
        let show = try await ShowController.start(
            setlist: setlist,
            kind: .gig,
            environment: harness.environment(),
        )
        try await show.perform(.move(fromOffsets: [2], toOffset: 0))
        let ending = try await show.end()
        #expect(ending.record.reorderReview == .pending)

        try await harness.relaunch()
        let pending = await harness.shows.pendingReviews()
        #expect(pending.map(\.showId) == [ending.record.id])
        #expect(pending.first?.setlistId == setlist.id)

        try await harness.shows.resolveReview(of: ending.record.id, saved: false)
        try await harness.relaunch()
        #expect(await harness.shows.pendingReviews().isEmpty)
        #expect(try await harness.reloadedShow(ending.record.id)?.reorderReview == .discarded)

        // An unchanged order has no review.
        let plain = try await ShowController.start(
            setlist: setlist,
            kind: .gig,
            environment: harness.environment(),
        )
        #expect(try await plain.end().record.reorderReview == nil)
    }

    // MARK: Nit: clock skew in the launch check

    @Test
    func `a show updated in the future is treated as stale`() async throws {
        let harness = try await ShowHarness()
        let (setlist, _) = try await harness.makeSet(2)
        harness.lib.clock.advance(by: 3600)
        let show = try await ShowController.start(
            setlist: setlist,
            kind: .gig,
            environment: harness.environment(),
        )
        let id = await show.state.record.id
        await show.relinquish()
        // The clock moved back an hour (or another Mac wrote it with a skewed clock).
        harness.lib.clock.advance(by: -3600)
        try await harness.relaunch()
        let check = try await harness.shows.launchCheck()
        #expect(check.resumable == nil)
        #expect(check.autoClosed.map(\.record.id) == [id])
        let closed = try #require(check.autoClosed.first?.record)
        #expect(try #require(closed.endedAt) <= harness.lib.clock.now())
    }

    // MARK: Nit: bindings.json schemaVersion

    @Test
    func `bindings files honour their schema version`() throws {
        let lib = try TestLibrary()
        let url = lib.url("bindings.json")
        // Pre-versioned (no schemaVersion): read as version 1.
        try lib.write("""
        {"bindings": [{"trigger": {"key": "pageDown"}, "command": "next"}]}
        """, to: "bindings.json")
        let old = try InputBindingTable.loadReporting(from: url, fileSystem: LiveFileSystem())
        #expect(old.newerSchema == nil)
        #expect(old.table.command(for: .key(KeyStroke(KeyStroke.pageDown))) == .next)

        // Newer: the bindings this version knows apply; unknown ones are skipped, not fatal.
        try lib.write("""
        {"schemaVersion": 3, "bindings": [
          {"trigger": {"key": "pageDown"}, "command": "next"},
          {"trigger": {"midi": 64}, "command": "next"},
          {"trigger": {"key": "z"}, "command": "teleport"}
        ]}
        """, to: "bindings.json")
        let newer = try InputBindingTable.loadReporting(from: url, fileSystem: LiveFileSystem())
        #expect(newer.newerSchema == 3)
        #expect(newer.skipped == 2)
        #expect(newer.table.command(for: .key(KeyStroke(KeyStroke.pageDown))) == .next)

        // A current file naming a retired command (R147's collapse toggle) still loads: that
        // binding is skipped, the others apply.
        try lib.write("""
        {"schemaVersion": 1, "bindings": [
          {"trigger": {"key": "o"}, "command": "toggleCollapseRepeats"},
          {"trigger": {"key": "pageDown"}, "command": "next"}
        ]}
        """, to: "bindings.json")
        let retired = try InputBindingTable.loadReporting(from: url, fileSystem: LiveFileSystem())
        #expect(retired.skipped == 0)
        #expect(retired.table.command(for: .key(KeyStroke(KeyStroke.pageDown))) == .next)
        #expect(retired.table.command(for: .key(KeyStroke("o"))) == nil)

        // The current version stays strict: a malformed binding is an error.
        try lib.write("""
        {"schemaVersion": 1, "bindings": [{"trigger": {"key": "z"}, "command": "teleport"}]}
        """, to: "bindings.json")
        #expect(throws: (any Error).self) {
            try InputBindingTable.loadReporting(from: url, fileSystem: LiveFileSystem())
        }
    }

    // MARK: #15 auto-scroll time is monotonic

    @Test
    func `the monotonic clock follows elapsed time, not the wall clock`() {
        let elapsed = Mutex(Duration.zero)
        let origin = Date(timeIntervalSince1970: 1_767_225_600)
        let clock = MonotonicClock(origin: origin) { elapsed.withLock { $0 } }
        #expect(clock.now() == origin)
        elapsed.withLock { $0 = .milliseconds(1500) }
        #expect(clock.now() == origin.addingTimeInterval(1.5))
        // The real one never goes backwards.
        let real = MonotonicClock()
        var last = real.now()
        for _ in 0 ..< 1000 {
            let now = real.now()
            #expect(now >= last)
            last = now
        }
    }
}
