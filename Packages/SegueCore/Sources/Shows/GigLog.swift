// Phase 2 frozen interface (docs/phases/2-interfaces.md). Owner: unit A.

import Foundation
import Library
import Setlists

/// One song as played, derived from the show's events.
public struct PlayedSong: Sendable, Hashable {
    public var item: ShowItem
    /// When it last became current.
    public var startedAt: Date
    /// When `next` (or `endShow`) moved past it as played.
    public var endedAt: Date
    public var fromRequest: Bool

    public init(item: ShowItem, startedAt: Date, endedAt: Date, fromRequest: Bool) {
        self.item = item
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.fromRequest = fromRequest
    }

    public var duration: TimeInterval {
        endedAt.timeIntervalSince(startedAt)
    }
}

/// A finished gig show as the gig log shows it.
public struct GigLogEntry: Sendable, Hashable, Identifiable {
    public var id: ShowID
    public var setlistId: SetlistID
    public var setlistName: String
    public var details: GigDetails
    public var startedAt: Date
    public var endedAt: Date
    /// Played songs in the order they were played.
    public var played: [PlayedSong]
    /// Skipped items in show order.
    public var skipped: [ShowItem]
    public var closure: ShowClosure

    public init(
        id: ShowID,
        setlistId: SetlistID,
        setlistName: String,
        details: GigDetails,
        startedAt: Date,
        endedAt: Date,
        played: [PlayedSong],
        skipped: [ShowItem],
        closure: ShowClosure,
    ) {
        self.id = id
        self.setlistId = setlistId
        self.setlistName = setlistName
        self.details = details
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.played = played
        self.skipped = skipped
        self.closure = closure
    }

    /// The entry for a finished record; nil if it is unfinished or a rehearsal.
    public init?(_ record: ShowRecord) {
        fatalError("unimplemented: unit A (GigLogEntry.init)")
    }
}

public extension ShowRecord {
    /// Songs played so far, in play order, derived from `events` (start = the last time the
    /// item became current, end = when it was advanced past as played).
    var playedSongs: [PlayedSong] {
        fatalError("unimplemented: unit A (ShowRecord.playedSongs)")
    }

    /// The play projection rows for this (finished, gig) show.
    var playRecords: [PlayRecord] {
        playedSongs.map { played in
            PlayRecord(
                songId: played.item.songId,
                showId: id.ulid,
                startedAt: played.startedAt,
                endedAt: played.endedAt,
                fromRequest: played.fromRequest,
            )
        }
    }
}
