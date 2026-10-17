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
    /// Marks current played; the first `pending` item in `items` becomes current (so items
    /// passed over by a jump are picked up again). At the end, current becomes nil.
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
/// record, appends an event stamped by the injected clock and (for a gig) writes the show
/// file atomically before returning. One controller per run.
public actor ShowController {
    private let environment: ShowEnvironment
    private var record: ShowRecord
    /// Song snapshots by song ID (see `ShowSlot.song`).
    private var snapshots: [SongID: SongRecord] = [:]

    private init(record: ShowRecord, environment: ShowEnvironment) {
        self.record = record
        self.environment = environment
    }

    /// Starts a run of `setlist`: the first entry becomes current. A gig is written to
    /// `shows/` at once; a rehearsal never is.
    /// - Parameter omitting: entries to start as `skipped` (their song is missing; the user
    ///   chose "Perform without them").
    public static func start(
        setlist: Setlist,
        kind: ShowKind,
        omitting: Set<SetlistItemID> = [],
        environment: ShowEnvironment,
    ) async throws -> ShowController {
        fatalError("unimplemented: unit A (ShowController.start)")
    }

    /// Resumes an unfinished show (from `ShowStore.launchCheck()`), at the same item and
    /// scroll position, appending a `resumed` event.
    public static func resume(
        _ record: ShowRecord,
        environment: ShowEnvironment,
    ) async throws -> ShowController {
        fatalError("unimplemented: unit A (ShowController.resume)")
    }

    /// The current state.
    public var state: ShowState {
        fatalError("unimplemented: unit A (ShowController.state)")
    }

    /// Applies `action`, persists (gig) and returns the new state. Actions that do nothing
    /// (e.g. `previous` at the first song) return the state unchanged without writing.
    @discardableResult
    public func perform(_ action: ShowAction) async throws -> ShowState {
        fatalError("unimplemented: unit A (ShowController.perform)")
    }

    /// Records the scroll position (0...1) of the current song. Written with the next
    /// action, or on its own when `scrollWriteInterval` has passed since the last write.
    public func updateScrollPosition(_ fraction: Double) async throws {
        fatalError("unimplemented: unit A (ShowController.updateScrollPosition)")
    }

    /// Writes a pending scroll position if one is due. The stage calls this on a timer
    /// (about every 0.5 s) so the last position reaches disk without another action.
    public func flushScrollPositionIfDue() async throws {
        fatalError("unimplemented: unit A (ShowController.flushScrollPositionIfDue)")
    }

    /// Ends the run: current (if any) is marked played, `endedAt` set, the file written, the
    /// play projection updated and the reorder diff computed. A rehearsal writes nothing.
    public func end() async throws -> ShowEnding {
        fatalError("unimplemented: unit A (ShowController.end)")
    }
}
