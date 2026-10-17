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

/// A state change the show engine performs. Argument-free commands from keys, pedals and
/// MIDI arrive as `LiveCommand` and map here through `LiveCommand.showAction`; the rest come
/// from UI (search overlay, request panel, drawer).
public enum ShowAction: Sendable, Equatable {
    /// Marks current played; the next `pending` item after it in `items` becomes current
    /// (items passed over by a jump stay pending and are not revisited automatically). At
    /// the end, current becomes nil.
    case next
    /// Current goes back to pending; the most recently played item becomes current again.
    case previous
    /// Marks current skipped and moves on like `next`.
    case skipCurrent
    /// Marks a pending item skipped (drawer). Skipping current is `skipCurrent`.
    case skip(ShowItemID)
    /// A skipped item back to pending.
    case unskip(ShowItemID)
    /// Makes `item` current (drawer). An interrupted current item goes back to pending.
    case jump(ShowItemID)
    /// Search "Play now": the first pending item of that song becomes current (like
    /// `jump`); when none, a new `.inserted` item is placed before current and made current.
    /// The interrupted item goes back to pending in its slot.
    case playNow(SongID)
    /// Search "Insert next": a new pending `.inserted` item right after current.
    case insertNext(SongID)
    /// Search "Add to requests".
    case addRequest(SongID, note: String?)
    /// `R`: the oldest queued request becomes an item before current and is made current;
    /// current goes back to pending (so `next` returns to it). No-op without requests.
    case playNextRequest
    /// The same for a specific request (request panel).
    case playRequest(ShowRequestID)
    case dropRequest(ShowRequestID)
    /// Drawer drag, as `Array.move(fromOffsets:toOffset:)` over `items`.
    case move(fromOffsets: IndexSet, toOffset: Int)
}

/// An item with the song snapshot the stage draws.
public struct ShowSlot: Sendable, Equatable {
    public var item: ShowItem
    /// Index in `ShowRecord.items`.
    public var position: Int
    /// The in-memory snapshot taken when the item became current (or was first shown as up
    /// next). It is never refreshed mid-song: an external edit applies on the next advance,
    /// and a deleted file keeps the last snapshot. Nil only if the song never loaded.
    public var song: SongRecord?

    public init(item: ShowItem, position: Int, song: SongRecord?) {
        self.item = item
        self.position = position
        self.song = song
    }
}

/// What the footer shows next.
public enum UpNext: Sendable, Equatable {
    /// A queued request wins over the next item ("Request: <title>").
    case request(ShowRequest, song: SongRecord?)
    case item(ShowSlot)
}

/// Everything the stage renders from the engine, replaced wholesale after each action.
public struct ShowState: Sendable, Equatable {
    public var record: ShowRecord
    public var current: ShowSlot?
    public var upNext: UpNext?

    public init(record: ShowRecord, current: ShowSlot?, upNext: UpNext?) {
        self.record = record
        self.current = current
        self.upNext = upNext
    }
}

/// The result of ending a show (or auto-closing a stale one).
public struct ShowEnding: Sendable, Equatable {
    /// The finished record (as written, for a gig).
    public var record: ShowRecord
    /// The planned-vs-performed diff when the order changed or songs were inserted; nil
    /// otherwise (no sheet). Always nil for a rehearsal.
    public var diff: ReorderDiff?
    /// The new gig log entry; nil for a rehearsal.
    public var gigLogEntry: GigLogEntry?

    public init(record: ShowRecord, diff: ReorderDiff?, gigLogEntry: GigLogEntry?) {
        self.record = record
        self.diff = diff
        self.gigLogEntry = gigLogEntry
    }
}

/// Errors from the show engine. Implementers may add cases.
public enum ShowError: Error, Equatable {
    /// The setlist has no performable entries.
    case emptySetlist
    /// No item, request or song with this ID.
    case itemNotFound(ShowItemID)
    case requestNotFound(ShowRequestID)
    case songNotFound(SongID)
    /// The show has already ended.
    case finished(ShowID)
    /// The show file is from a newer Segue and cannot be resumed.
    case readOnly(ShowID, ReadOnlyReason)
    /// `move` offsets out of range.
    case invalidOffsets
    /// `ShowStore` used before `load(root:)`.
    case notLoaded
    /// No stored show with this ID.
    case showNotFound(ShowID)
    /// Gig log edits need a finished show.
    case notFinished(ShowID)
    /// A gig rating outside `GigDetails.ratingRange`.
    case invalidRating(Int)
    /// Writing the show file or a timing sample failed. The action itself still took effect
    /// in memory (the stage keeps going); the write is retried with the next action, scroll
    /// flush or `end()`.
    case writeFailed(String)
}

/// Injected dependencies of a show run.
public struct ShowEnvironment: Sendable {
    public var store: ShowStore
    public var songs: any ShowSongSource
    public var clock: any Clock
    public var ids: any IDGenerator
    /// Receives one sample per completed song (gig and rehearsal), for phase 3.
    public var durations: (any DurationSampleSink)?
    /// Minimum seconds between scroll-only writes (1 s: kill -9 loses at most a second).
    public var scrollWriteInterval: TimeInterval

    public init(
        store: ShowStore,
        songs: any ShowSongSource,
        clock: any Clock,
        ids: any IDGenerator,
        durations: (any DurationSampleSink)? = nil,
        scrollWriteInterval: TimeInterval = 1,
    ) {
        self.store = store
        self.songs = songs
        self.clock = clock
        self.ids = ids
        self.durations = durations
        self.scrollWriteInterval = scrollWriteInterval
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
    private var writing = false
    private var pendingSamples: [DurationSample] = []
    private var sendingSamples = false

    private init(record: ShowRecord, environment: ShowEnvironment) {
        self.record = record
        self.environment = environment
        currentState = ShowState(record: record, current: nil, upNext: nil)
    }

    /// The setlist entries whose song is not in the library (the pre-show warning). Pass
    /// their item IDs as `omitting` to perform without them.
    public static func missingEntries(
        in setlist: Setlist,
        songs: any ShowSongSource,
    ) async -> [SetlistEntry] {
        var missing: [SetlistEntry] = []
        for entry in setlist.entries where await songs.cachedSong(id: entry.songId) == nil {
            missing.append(entry)
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
        for entry in setlist.entries where !omitting.contains(entry.itemId) {
            let song = await environment.songs.cachedSong(id: entry.songId)
            items.append(ShowItem(
                itemId: entry.itemId,
                songId: entry.songId,
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
        let controller = ShowController(record: record, environment: environment)
        await controller.takeSnapshotOfCurrent()
        await controller.refreshState()
        try await controller.persist()
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
        var resumed = record
        let now = SegueJSON.stamp(environment.clock.now())
        resumed.events.append(ShowEvent(at: now, kind: .resumed, itemId: record.currentItemId))
        resumed.updatedAt = now
        let controller = ShowController(record: resumed, environment: environment)
        await controller.takeSnapshotOfCurrent()
        await controller.refreshState()
        try await controller.persist()
        return controller
    }

    /// The current state.
    public var state: ShowState {
        currentState
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
        guard !record.isFinished else { return }
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
        return ShowEnding(
            record: record,
            diff: record.kind == .gig ? ReorderDiff.compute(record) : nil,
            gigLogEntry: GigLogEntry(record),
        )
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

    /// Rebuilds `currentState` from the record and the snapshots.
    private func refreshState() async {
        let current = record.currentIndex.map { index in
            let item = record.items[index]
            return ShowSlot(item: item, position: index, song: snapshots[item.songId])
        }
        var upNext: UpNext?
        if let request = record.queuedRequests.first {
            let song = await environment.songs.cachedSong(id: request.songId)
            upNext = .request(request, song: song)
        } else if let index = record.nextPendingIndex {
            let item = record.items[index]
            var song = snapshots[item.songId]
            if song == nil {
                song = await environment.songs.cachedSong(id: item.songId)
            }
            upNext = .item(ShowSlot(item: item, position: index, song: song))
        }
        currentState = ShowState(record: record, current: current, upNext: upNext)
    }

    // MARK: - Persistence

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

    /// Writes the latest record; while a write is in flight, later calls only mark it dirty
    /// and the in-flight loop writes again.
    private func persist() async throws {
        needsWrite = true
        guard !writing else { return }
        writing = true
        defer { writing = false }
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
