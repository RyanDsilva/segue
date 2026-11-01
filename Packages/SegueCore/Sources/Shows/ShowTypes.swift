// Phase 2 frozen interface (docs/phases/2-interfaces.md). Owner: unit A. The show
// engine's value types (split from ShowController.swift).

import Foundation
import Library
import Setlists
import Support

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
    /// "Move to Next" (R102): a pending (or skipped) item moves right after current, so
    /// `next` reaches it. The answer to adding a song that is already upcoming.
    case moveToNext(ShowItemID)
    /// "Move to Next" for a queued request (R102): it moves to the front of the queue, so it
    /// is the footer's next request and `R` plays it.
    case moveRequestToFront(ShowRequestID)
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
    /// Every member of the medley the current item plays in, in order, with its song (P9-3
    /// 9.1: the stage lays them out as one plan); empty outside a medley.
    public var medley: [ShowSlot]

    public init(
        record: ShowRecord,
        current: ShowSlot?,
        upNext: UpNext?,
        medley: [ShowSlot] = [],
    ) {
        self.record = record
        self.current = current
        self.upNext = upNext
        self.medley = medley
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
    /// The show is open in another Segue window or process (its claim is held), so it
    /// cannot be started, resumed or closed here.
    case claimedElsewhere(ShowID)
    /// R102: the action would play or queue a song a second time in this show.
    case repeatRefused(SongID, RepeatRefusal)
}

/// Injected dependencies of a show run.
public struct ShowEnvironment: Sendable {
    /// Where the run is written; nil for an unsaved run (a single-song session, R150): it is
    /// never claimed or written, so nothing reaches `shows/`, the gig log or play stats.
    public var store: ShowStore?
    public var songs: any ShowSongSource
    public var clock: any Clock
    public var ids: any IDGenerator
    /// Minimum seconds between scroll-only writes. With the stage's flush tick
    /// (`LiveSession.flushTick`, 0.25 s) a scroll change reaches disk within a second, so
    /// kill -9 loses at most a second of scrolling.
    public var scrollWriteInterval: TimeInterval

    public init(
        store: ShowStore?,
        songs: any ShowSongSource,
        clock: any Clock,
        ids: any IDGenerator,
        scrollWriteInterval: TimeInterval = 0.75,
    ) {
        self.store = store
        self.songs = songs
        self.clock = clock
        self.ids = ids
        self.scrollWriteInterval = scrollWriteInterval
    }
}
