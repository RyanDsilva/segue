// Phase 2 frozen interface (docs/phases/2-interfaces.md). Owner: unit A.

import Foundation
import Library
import Setlists
import Support

/// Where the show engine gets songs. `LibraryStore` conforms; tests may use it directly
/// (integration-first) or a small stand-in.
public protocol ShowSongSource: Sendable {
    /// The in-memory record (no IO): titles, up-next metadata, inserted songs.
    func cachedSong(id: SongID) async -> SongRecord?
    /// The song re-read from disk now; nil when its file is gone or unreadable.
    func freshSong(id: SongID) async -> SongRecord?
}

extension LibraryStore: ShowSongSource {
    public func cachedSong(id: SongID) async -> SongRecord? {
        try? song(id: id)
    }

    public func freshSong(id: SongID) async -> SongRecord? {
        try? reloadSong(id: id)
    }
}

/// The show state machine: every show action goes through `perform(_:)`, which updates the
/// record, appends an event stamped by the injected clock and writes the show file
/// atomically before returning. One controller per run.
///
/// Transitions are pure (`ShowRecord.apply`) and applied without suspending, so actions can
/// never interleave. Writes always take the latest record, one at a time, so an older
/// record can never overwrite a newer one. A failed write keeps the action in memory (the
/// stage keeps going), throws `ShowError.writeFailed` and is retried with the next action,
/// scroll flush or `end()`.
public actor ShowController {
    private let environment: ShowEnvironment
    private var record: ShowRecord
    /// Song snapshots by song ID (see `ShowSlot.song`).
    private var snapshots: [SongID: SongRecord] = [:]
    private var currentState: ShowState
    /// The `updatedAt` of the last successful write.
    private var lastWrite: Date?
    private var needsWrite = false
    /// The write loop in flight; later `persist()` calls wait for it (it picks up their
    /// record), so a caller never returns before its record landed.
    private var writeTask: Task<Void, any Error>?
    private var pendingSamples: [DurationSample] = []
    private var sendingSamples = false
    /// This run's hold on the show (released when it ends).
    private let claim: ShowClaim

    private init(record: ShowRecord, environment: ShowEnvironment, claim: ShowClaim) {
        self.record = record
        self.environment = environment
        self.claim = claim
        currentState = ShowState(record: record, current: nil, upNext: nil)
    }

    /// The setlist entries whose song is not in the library (the pre-show warning). Pass
    /// their item IDs as `omitting` to perform without them.
    public static func missingEntries(
        in setlist: Setlist,
        songs: any ShowSongSource,
    ) async -> [SetlistEntry] {
        var missing: [SetlistEntry] = []
        for entry in setlist.entries {
            guard let song = entry.songId else { continue }
            if await songs.cachedSong(id: song) == nil {
                missing.append(entry)
            }
        }
        return missing
    }

    /// Starts a run of `setlist`: the first entry becomes current. The run (gig or
    /// rehearsal) is written to `shows/` at once.
    /// - Parameter omitting: entries left out of the show because their song is missing
    ///   (`missingEntries(in:songs:)`; the pre-show warning lists them). They are removed,
    ///   not skipped, and the record keeps them as `omittedEntries`.
    public static func start(
        setlist: Setlist,
        kind: ShowKind,
        omitting: Set<SetlistItemID> = [],
        environment: ShowEnvironment,
    ) async throws -> ShowController {
        let now = SegueJSON.stamp(environment.clock.now())
        var items: [ShowItem] = []
        // Break rows are not stage items yet (R104's interstitial comes with the live
        // step); the record keeps them in `planned` so the show-end save keeps them.
        for entry in setlist.entries where !omitting.contains(entry.itemId) {
            guard let songId = entry.songId else { continue }
            let song = await environment.songs.cachedSong(id: songId)
            items.append(ShowItem(
                itemId: entry.itemId,
                songId: songId,
                title: displayTitle(song),
                origin: .setlist,
                overrides: entry.overrides,
                note: entry.note,
            ))
        }
        guard let first = items.first?.itemId else { throw ShowError.emptySetlist }
        items[0].state = .current
        let record = ShowRecord(
            id: ShowID(environment.ids.next()),
            kind: kind,
            setlistId: setlist.id,
            setlistName: setlist.name,
            planned: setlist.entries,
            items: items,
            currentItemId: first,
            events: [ShowEvent(at: now, kind: .started, itemId: first)],
            startedAt: now,
            updatedAt: now,
            gig: GigDetails(
                venue: ShowRecord.trimmed(setlist.venue),
                date: setlist.date ?? CalendarDay(now),
            ),
        )
        let claim = try await environment.store.claim(record.id)
        let controller = ShowController(record: record, environment: environment, claim: claim)
        await controller.takeSnapshotOfCurrent()
        await controller.refreshState()
        do {
            try await controller.persist()
        } catch {
            claim.release()
            throw error
        }
        return controller
    }

    /// Resumes an unfinished show (from `ShowStore.launchCheck()`), at the same item and
    /// scroll position, appending a `resumed` event.
    public static func resume(
        _ record: ShowRecord,
        environment: ShowEnvironment,
    ) async throws -> ShowController {
        if let reason = record.readOnly {
            throw ShowError.readOnly(record.id, reason)
        }
        guard !record.isFinished else { throw ShowError.finished(record.id) }
        // Only one run may hold a show: a second window or process resuming it would
        // overwrite this one's writes.
        let claim = try await environment.store.claim(record.id)
        // The latest record on disk (the one offered may predate a write by another run).
        let latest = await environment.store.reloaded(record.id) ?? record
        if latest.isFinished || latest.readOnly != nil {
            claim.release()
            if let reason = latest.readOnly {
                throw ShowError.readOnly(record.id, reason)
            }
            throw ShowError.finished(record.id)
        }
        var resumed = latest
        let now = SegueJSON.stamp(environment.clock.now())
        resumed.events.append(ShowEvent(at: now, kind: .resumed, itemId: latest.currentItemId))
        resumed.updatedAt = now
        let controller = ShowController(record: resumed, environment: environment, claim: claim)
        await controller.takeSnapshotOfCurrent()
        await controller.refreshState()
        do {
            try await controller.persist()
        } catch {
            claim.release()
            throw error
        }
        return controller
    }

    /// The current state.
    public var state: ShowState {
        currentState
    }

    /// True while a change (action, scroll position, timing sample) is not on disk yet,
    /// e.g. after a failed write that has not been retried successfully.
    public var hasUnsavedChanges: Bool {
        needsWrite || !pendingSamples.isEmpty || writeTask != nil
    }

    /// Applies `action`, persists and returns the new state. Actions that do nothing (e.g.
    /// `previous` at the first song) return the state unchanged without writing.
    @discardableResult
    public func perform(_ action: ShowAction) async throws -> ShowState {
        let title = await titleOfSong(named: action)
        guard !record.isFinished else { throw ShowError.finished(record.id) }
        let now = SegueJSON.stamp(environment.clock.now())
        var next = record
        let ids = environment.ids
        let completed = try next.apply(
            action,
            TransitionContext(now: now, newID: { ids.next() }, songTitle: title),
        )
        guard next != record else { return currentState }
        let previousCurrent = record.currentItemId
        next.updatedAt = now
        record = next
        queueSamples(for: completed, at: now)
        if record.currentItemId != previousCurrent {
            await takeSnapshotOfCurrent()
        }
        await refreshState()
        try await persistAndSendSamples()
        return currentState
    }

    /// Records the scroll position (0...1) of the current song. Written with the next
    /// action, or on its own when `scrollWriteInterval` has passed since the last write.
    public func updateScrollPosition(_ fraction: Double) async throws {
        guard let item = record.currentItemId else { return }
        try await updateScrollPosition(fraction, for: item)
    }

    /// Records the scroll position of `item`; dropped when `item` is no longer current (a
    /// late flush from the song just left must never land on the new one).
    public func updateScrollPosition(_ fraction: Double, for item: ShowItemID) async throws {
        guard !record.isFinished, record.currentItemId == item else { return }
        let clamped = fraction.isFinite ? min(max(fraction, 0), 1) : 0
        guard clamped != record.scrollPosition else { return }
        record.scrollPosition = clamped
        currentState.record.scrollPosition = clamped
        needsWrite = true
        try await flushScrollPositionIfDue()
    }

    /// Writes a pending scroll position if one is due. The stage calls this on a timer
    /// (about every 0.5 s) so the last position reaches disk without another action.
    public func flushScrollPositionIfDue() async throws {
        guard needsWrite || !pendingSamples.isEmpty else { return }
        let now = SegueJSON.stamp(environment.clock.now())
        if let lastWrite, now.timeIntervalSince(lastWrite) < environment.scrollWriteInterval {
            return
        }
        if needsWrite, !record.isFinished {
            record.updatedAt = now
            currentState.record.updatedAt = now
        }
        try await persistAndSendSamples()
    }

    /// Ends the run: current (if any) is marked played, `endedAt` set, the file written, the
    /// play projection updated and the reorder diff computed. A rehearsal is written too but
    /// gets no diff and no gig log entry. Calling it again after a failed write retries the
    /// write and returns the same ending.
    public func end() async throws -> ShowEnding {
        if !record.isFinished {
            let now = SegueJSON.stamp(environment.clock.now())
            let completed = record.finish(at: now, closure: .ended)
            queueSamples(for: completed.map { [$0] } ?? [], at: now)
            snapshots = [:]
            await refreshState()
        } else if !needsWrite, pendingSamples.isEmpty {
            throw ShowError.finished(record.id)
        }
        try await persistAndSendSamples()
        claim.release(removingFile: true)
        return ShowEnding(
            record: record,
            diff: record.kind == .gig ? ReorderDiff.compute(record) : nil,
            gigLogEntry: GigLogEntry(record),
        )
    }

    /// Lets go of the show without ending it (the stage went away; the show stays
    /// resumable). The controller must not be used afterwards.
    public func relinquish() {
        claim.release()
    }

    // MARK: - Songs

    /// The title of the song a search action names, looked up before the transition.
    private func titleOfSong(named action: ShowAction) async -> String? {
        switch action {
        case let .addRequest(songId, _), let .insertNext(songId), let .playNow(songId):
            await environment.songs.cachedSong(id: songId).map { Self.displayTitle($0) }
        default:
            nil
        }
    }

    /// The title a show item keeps: `{title}`, else the file name, else a placeholder.
    static func displayTitle(_ song: SongRecord?) -> String {
        guard let song else { return "Unknown song" }
        if let title = ShowRecord.trimmed(song.document.metadata.title) {
            return title
        }
        return URL(fileURLWithPath: song.relativePath).deletingPathExtension().lastPathComponent
    }

    /// Re-reads the current song from disk (an external edit applies now, never mid-song).
    /// A missing file keeps the last snapshot.
    private func takeSnapshotOfCurrent() async {
        guard let songId = record.currentItem?.songId else { return }
        if let fresh = await environment.songs.freshSong(id: songId) {
            snapshots[songId] = fresh
        } else if snapshots[songId] == nil,
                  let cached = await environment.songs.cachedSong(id: songId)
        {
            snapshots[songId] = cached
        }
    }

    /// Rebuilds `currentState` from the record and the snapshots. The songs the state may
    /// need are looked up first; the state is then built from one read of `record` without
    /// suspending, so an action landing during a lookup can never mix two records.
    private func refreshState() async {
        var looked: [SongID: SongRecord] = [:]
        for songId in songsForState() where snapshots[songId] == nil && looked[songId] == nil {
            if let song = await environment.songs.cachedSong(id: songId) {
                looked[songId] = song
            }
        }
        let record = record
        let current = record.currentIndex.map { index in
            let item = record.items[index]
            return ShowSlot(item: item, position: index, song: snapshots[item.songId])
        }
        var upNext: UpNext?
        if let request = record.queuedRequests.first {
            upNext = .request(request, song: snapshots[request.songId] ?? looked[request.songId])
        } else if let index = record.nextPendingIndex {
            let item = record.items[index]
            let song = snapshots[item.songId] ?? looked[item.songId]
            upNext = .item(ShowSlot(item: item, position: index, song: song))
        }
        currentState = ShowState(record: record, current: current, upNext: upNext)
    }

    /// The songs the footer may show (first queued request, next pending item).
    private func songsForState() -> [SongID] {
        var ids: [SongID] = []
        if let request = record.queuedRequests.first {
            ids.append(request.songId)
        }
        if let index = record.nextPendingIndex {
            ids.append(record.items[index].songId)
        }
        return ids
    }
}

// MARK: - Persistence

extension ShowController {
    private func queueSamples(for completed: [ShowItemID], at now: Date) {
        guard environment.durations != nil, !completed.isEmpty else { return }
        let played = record.playedSongs
        for itemId in completed {
            guard let song = played.first(where: { $0.item.itemId == itemId }) else { continue }
            pendingSamples.append(DurationSample(
                songId: song.item.songId,
                seconds: song.duration,
                source: record.kind == .gig ? .show : .rehearsal,
                runId: record.id.ulid,
                recordedAt: now,
            ))
        }
    }

    private func persistAndSendSamples() async throws {
        needsWrite = true
        var failure: (any Error)?
        do {
            try await persist()
        } catch {
            failure = error
        }
        do {
            try await sendSamples()
        } catch {
            failure = failure ?? error
        }
        if let failure {
            throw failure
        }
    }

    /// Writes the latest record and returns once it is on disk. While a write is in flight,
    /// a later call marks the record dirty and waits for the in-flight loop, which writes
    /// again until nothing is dirty, so it covers the caller's record too (or throws).
    private func persist() async throws {
        needsWrite = true
        if let writeTask {
            try await writeTask.value
            return
        }
        let task = Task { try await self.writeLoop() }
        writeTask = task
        try await task.value
    }

    private func writeLoop() async throws {
        defer { writeTask = nil }
        while needsWrite {
            needsWrite = false
            let snapshot = record
            do {
                try await environment.store.save(snapshot)
                lastWrite = snapshot.updatedAt
            } catch {
                needsWrite = true
                throw ShowError.writeFailed(Self.message(error))
            }
        }
    }

    private func sendSamples() async throws {
        guard let sink = environment.durations, !sendingSamples else { return }
        sendingSamples = true
        defer { sendingSamples = false }
        while let sample = pendingSamples.first {
            do {
                try await sink.record(sample)
            } catch {
                throw ShowError.writeFailed(Self.message(error))
            }
            pendingSamples.removeFirst()
        }
    }

    private static func message(_ error: any Error) -> String {
        (error as? any LocalizedError)?.errorDescription ?? String(describing: error)
    }
}
