// Phase 2 frozen interface (docs/phases/2-interfaces.md). Owner: unit A.

import Foundation
import Library
import Setlists
import Support

/// Stable identity of a show (ULID). A finished gig show is also a gig log entry.
public struct ShowID: Sendable, Hashable, Comparable, Codable, CustomStringConvertible {
    public let ulid: ULID

    public init(_ ulid: ULID) {
        self.ulid = ulid
    }

    public var description: String {
        ulid.description
    }

    public static func < (lhs: Self, rhs: Self) -> Bool {
        lhs.ulid < rhs.ulid
    }

    public init(from decoder: any Decoder) throws {
        ulid = try ULID(from: decoder)
    }

    public func encode(to encoder: any Encoder) throws {
        try ulid.encode(to: encoder)
    }
}

/// Stable identity of a request in a show's queue (ULID).
public struct ShowRequestID: Sendable, Hashable, Comparable, Codable, CustomStringConvertible {
    public let ulid: ULID

    public init(_ ulid: ULID) {
        self.ulid = ulid
    }

    public var description: String {
        ulid.description
    }

    public static func < (lhs: Self, rhs: Self) -> Bool {
        lhs.ulid < rhs.ulid
    }

    public init(from decoder: any Decoder) throws {
        ulid = try ULID(from: decoder)
    }

    public func encode(to encoder: any Encoder) throws {
        try ulid.encode(to: encoder)
    }
}

/// A show item is a setlist item (same ID) or a song added during the show (new ID).
public typealias ShowItemID = SetlistItemID

/// What kind of run this is.
public enum ShowKind: String, Sendable, Hashable, Codable {
    /// A real gig: persisted on every action, becomes a gig log entry, feeds play stats.
    case gig
    /// A rehearse-setlist run: written like a gig so it can be resumed after a crash, but
    /// never in the gig log or play stats; its output is song timings (`DurationSampleSink`).
    case rehearsal
}

/// Where an item came from.
public enum ItemOrigin: String, Sendable, Hashable, Codable {
    /// Planned: one of the setlist's entries.
    case setlist
    /// Played from the request queue (`ShowItem.requestId` names the request).
    case request
    /// Added during the show by "Play now" or "Insert next" from search.
    case inserted
}

/// One item's state in the show. Exactly one item is `current` while the show runs (none
/// once the last item has been advanced past). An item interrupted by "Play now" goes back
/// to `pending` (decisions.md, phase 2); the event log records the interruption.
public enum ItemState: String, Sendable, Hashable, Codable {
    case pending
    case current
    case played
    case skipped
}

/// One item of a show, in performed order (`ShowRecord.items`).
public struct ShowItem: Sendable, Hashable, Codable, Identifiable {
    public var itemId: ShowItemID
    public var songId: SongID
    /// The song's title when the item was added, so the gig log reads right after the song
    /// is renamed or deleted.
    public var title: String
    public var origin: ItemOrigin
    /// Set when `origin == .request`.
    public var requestId: ShowRequestID?
    public var overrides: SetlistOverrides
    public var note: String?
    public var state: ItemState

    public var id: ShowItemID {
        itemId
    }

    public init(
        itemId: ShowItemID,
        songId: SongID,
        title: String,
        origin: ItemOrigin,
        requestId: ShowRequestID? = nil,
        overrides: SetlistOverrides = SetlistOverrides(),
        note: String? = nil,
        state: ItemState = .pending,
    ) {
        self.itemId = itemId
        self.songId = songId
        self.title = title
        self.origin = origin
        self.requestId = requestId
        self.overrides = overrides
        self.note = note
        self.state = state
    }
}

/// A request in the show's queue.
public struct ShowRequest: Sendable, Hashable, Codable, Identifiable {
    public enum State: String, Sendable, Hashable, Codable {
        case queued
        /// Became an item (`ShowItem.requestId`) and was made current.
        case played
        /// Removed from the queue without playing.
        case dropped
    }

    public var requestId: ShowRequestID
    public var songId: SongID
    public var title: String
    public var addedAt: Date
    /// "table 4".
    public var note: String?
    public var state: State

    public var id: ShowRequestID {
        requestId
    }

    public init(
        requestId: ShowRequestID,
        songId: SongID,
        title: String,
        addedAt: Date,
        note: String? = nil,
        state: State = .queued,
    ) {
        self.requestId = requestId
        self.songId = songId
        self.title = title
        self.addedAt = addedAt
        self.note = note
        self.state = state
    }
}

/// One entry of the show's action timeline. Timestamps come from the injected clock and are
/// the raw input for the gig log's played list and phase 3's learned song durations.
public struct ShowEvent: Sendable, Hashable, Codable {
    public enum Kind: String, Sendable, Hashable, Codable {
        /// The show started; `itemId` = the first current item.
        case started
        /// Resumed after a relaunch; `itemId` = current.
        case resumed
        /// `next`: `fromItemId` marked played, `itemId` became current (nil at the end).
        /// After `skipCurrent` (or `next` with nothing current) `fromItemId` is nil: the
        /// show moved on to `itemId` without playing anything.
        case advanced
        /// `previous`: `fromItemId` back to pending, `itemId` (last played) current again.
        case previous
        /// `itemId` skipped (`fromItemId` = the item left when the skipped one was current;
        /// an `advanced` event without `fromItemId` then names the new current item).
        case skipped
        case unskipped
        /// Play now / jump: `itemId` became current, `fromItemId` was interrupted (back to
        /// pending).
        case jumped
        /// A song was inserted (`itemId`), by play now or insert next.
        case inserted
        /// The drawer reordered items; `itemId` = the moved item.
        case reordered
        case requestAdded
        /// `requestId` became item `itemId` and current; `fromItemId` was interrupted.
        case requestPlayed
        case requestDropped
        /// `endShow`; `fromItemId` = the current item, marked played if it was current.
        case ended
        /// Closed on a later launch because it was untouched for 12 hours; stamped with the
        /// show's last update. Like `ended`, `fromItemId` (the item then current) is marked
        /// played.
        case autoClosed
        /// The stage showed the break row `itemId` (R104): the set reached the part it opens.
        case breakStarted
        /// The break `itemId` ended (Next, or any other move on stage); `fromItemId` = the
        /// item current behind it, whose song starts now.
        case breakEnded
    }

    public var at: Date
    public var kind: Kind
    public var itemId: ShowItemID?
    public var fromItemId: ShowItemID?
    public var requestId: ShowRequestID?

    public init(
        at: Date,
        kind: Kind,
        itemId: ShowItemID? = nil,
        fromItemId: ShowItemID? = nil,
        requestId: ShowRequestID? = nil,
    ) {
        self.at = at
        self.kind = kind
        self.itemId = itemId
        self.fromItemId = fromItemId
        self.requestId = requestId
    }
}

/// The editable gig log fields (decisions.md: venue, date, notes, rating only).
public struct GigDetails: Sendable, Hashable, Codable {
    public var venue: String?
    public var date: CalendarDay?
    public var notes: String?
    /// 1...5; nil = not rated.
    public var rating: Int?

    public init(
        venue: String? = nil,
        date: CalendarDay? = nil,
        notes: String? = nil,
        rating: Int? = nil,
    ) {
        self.venue = venue
        self.date = date
        self.notes = notes
        self.rating = rating
    }

    /// Valid ratings.
    public static let ratingRange = 1 ... 5
}

/// Whether the show-end reorder review (Save to setlist / Discard) still waits for an
/// answer. Stored on the show so a review survives a quit or crash until it is resolved.
public enum ReorderReviewState: String, Sendable, Hashable, Codable {
    /// The played order differs from the plan and nobody has answered yet.
    case pending
    /// Saved to the setlist.
    case saved
    /// Discarded (the setlist kept its order), or the setlist could not take it.
    case discarded
}

/// How a show was closed.
public enum ShowClosure: String, Sendable, Hashable, Codable {
    /// The performer ended it (`endShow`).
    case ended
    /// Auto-closed on launch after 12 hours untouched (decisions.md, phase 2).
    case stale
}

/// `shows/<ulid>.show.json`: one run of a setlist, written atomically on every action while
/// it runs. A finished gig show (`endedAt` set) is its own gig log entry.
///
/// Played and skipped state lives here, never on the setlist, so a setlist stays reusable.
/// Versioning follows the sidecar rules (older migrate forward, newer open read-only).
public struct ShowRecord: Sendable, Hashable, Codable, Identifiable {
    /// History: 1 = phase 2; 2 = phase 3 (`planned` may hold break rows, `breakId`, the
    /// `breakStarted` / `breakEnded` events). A v1 build opens a v2 file read-only.
    public static let currentSchemaVersion = 2

    public var id: ShowID
    public var schemaVersion: Int
    public var kind: ShowKind
    public var setlistId: SetlistID
    /// The setlist's name at start (the gig log's title if it is renamed or deleted).
    public var setlistName: String
    /// The setlist's entries at start: the planned order the show-end diff compares with.
    public var planned: [SetlistEntry]
    /// All items in performed order (reorder moves them; inserted songs and played requests
    /// are added). Item IDs are unique.
    public var items: [ShowItem]
    /// The item with state `current`; nil before start or after the last item.
    public var currentItemId: ShowItemID?
    /// The break row (from `planned`) the stage shows before the current song (R104): the
    /// set reached the part it opens. Next ends it; the show clock keeps running.
    public var breakId: SetlistItemID?
    /// Scroll position in the current song: 0 = top, 1 = bottom of the overflow. Written at
    /// most once a second while scrolling (debounced), and with every action.
    public var scrollPosition: Double
    public var requests: [ShowRequest]
    public var events: [ShowEvent]
    public var startedAt: Date
    /// Last write; drives the 12-hour resume/auto-close rule.
    public var updatedAt: Date
    public var endedAt: Date?
    public var closure: ShowClosure?
    /// Prefilled from the setlist (venue, date) at start; edited in the gig log afterwards.
    public var gig: GigDetails
    /// Set when a gig finishes with a reorder diff: `.pending` until the review is answered.
    /// Nil for rehearsals, unchanged orders and shows written before reviews were stored.
    public var reorderReview: ReorderReviewState?
    /// Runtime state, not persisted: non-nil when the file is from a newer Segue.
    public var readOnly: ReadOnlyReason?

    private enum CodingKeys: String, CodingKey {
        case id
        case schemaVersion
        case kind
        case setlistId
        case setlistName
        case planned
        case items
        case currentItemId
        case breakId
        case scrollPosition
        case requests
        case events
        case startedAt
        case updatedAt
        case endedAt
        case closure
        case gig
        case reorderReview
    }

    public init(
        id: ShowID,
        schemaVersion: Int = Self.currentSchemaVersion,
        kind: ShowKind,
        setlistId: SetlistID,
        setlistName: String,
        planned: [SetlistEntry],
        items: [ShowItem],
        currentItemId: ShowItemID?,
        breakId: SetlistItemID? = nil,
        scrollPosition: Double = 0,
        requests: [ShowRequest] = [],
        events: [ShowEvent] = [],
        startedAt: Date,
        updatedAt: Date,
        endedAt: Date? = nil,
        closure: ShowClosure? = nil,
        gig: GigDetails = GigDetails(),
        reorderReview: ReorderReviewState? = nil,
        readOnly: ReadOnlyReason? = nil,
    ) {
        self.id = id
        self.schemaVersion = schemaVersion
        self.kind = kind
        self.setlistId = setlistId
        self.setlistName = setlistName
        self.planned = planned
        self.items = items
        self.currentItemId = currentItemId
        self.breakId = breakId
        self.scrollPosition = scrollPosition
        self.requests = requests
        self.events = events
        self.startedAt = startedAt
        self.updatedAt = updatedAt
        self.endedAt = endedAt
        self.closure = closure
        self.gig = gig
        self.reorderReview = reorderReview
        self.readOnly = readOnly
    }

    /// True once ended or auto-closed.
    public var isFinished: Bool {
        endedAt != nil
    }

    /// Index of the current item in `items`.
    public var currentIndex: Int? {
        currentItemId.flatMap { id in items.firstIndex { $0.itemId == id } }
    }

    /// The current item.
    public var currentItem: ShowItem? {
        currentIndex.map { items[$0] }
    }

    /// The break the stage shows now, if any.
    public var currentBreak: SetlistBreak? {
        breakId.flatMap { id in planned.first { $0.itemId == id }?.breakInfo }
    }

    /// Requests still waiting, oldest first.
    public var queuedRequests: [ShowRequest] {
        requests.filter { $0.state == .queued }
    }

    /// Planned entries left out of the show at start because their song was missing
    /// (decisions.md, phase 2 build rulings: removed, not skipped). Derived: items are never
    /// removed during a show, so a planned song entry without an item was left out (break
    /// rows are never items yet).
    public var omittedEntries: [SetlistEntry] {
        let present = Set(items.map(\.itemId))
        return planned.filter { !$0.isBreak && !present.contains($0.itemId) }
    }
}
