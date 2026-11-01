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
}

/// One slot as played (P9-3 8.3): a song, or a medley with its members nested.
public enum PlayedSlot: Sendable, Hashable {
    case song(PlayedSong)
    /// Consecutive played members of one medley; `skipped` are its members skipped.
    case medley(slot: SetlistItemID, title: String?, members: [PlayedSong], skipped: [ShowItem])

    /// When the slot started: its (first) song's start.
    public var startedAt: Date? {
        switch self {
        case let .song(song): song.startedAt
        case let .medley(_, _, members, _): members.first?.startedAt
        }
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
        guard record.kind == .gig, let endedAt = record.endedAt else { return nil }
        self.init(
            id: record.id,
            setlistId: record.setlistId,
            setlistName: record.setlistName,
            details: record.gig,
            startedAt: record.startedAt,
            endedAt: endedAt,
            played: record.playedSongs,
            skipped: record.items.filter { $0.state == .skipped },
            closure: record.closure ?? .ended,
        )
    }

    /// Played songs that came from the request queue.
    public var requestCount: Int {
        played.count { $0.fromRequest }
    }

    /// The played list as slots: consecutive played members of one medley grouped under it,
    /// with that medley's skipped members (P9-3 8.3, the parent/child rule).
    public var slots: [PlayedSlot] {
        var slots: [PlayedSlot] = []
        for song in played {
            guard let ref = song.item.medley else {
                slots.append(.song(song))
                continue
            }
            if case let .medley(slot, title, members, skipped) = slots.last, slot == ref.slot {
                slots[slots.count - 1] = .medley(
                    slot: slot,
                    title: title,
                    members: members + [song],
                    skipped: skipped,
                )
                continue
            }
            slots.append(.medley(
                slot: ref.slot,
                title: ref.title,
                members: [song],
                skipped: skipped.filter { $0.medley?.slot == ref.slot },
            ))
        }
        return slots
    }
}

public extension ShowRecord {
    /// Songs played so far, in play order, derived from `events` (start = the last time the
    /// item became current or the show was resumed on it, end = when it was advanced past as
    /// played).
    ///
    /// Only items whose state is still `played` count (an item `previous` brought back is
    /// counted from its later play). A song's order is when it was last marked played.
    var playedSongs: [PlayedSong] {
        var becameCurrent: [ShowItemID: Date] = [:]
        var plays: [ShowItemID: Play] = [:]
        for (order, event) in events.enumerated() {
            switch event.kind {
            case .advanced, .autoClosed, .ended:
                if let played = event.fromItemId {
                    let start = becameCurrent[played] ?? startedAt
                    plays[played] = Play(start: start, end: max(event.at, start), order: order)
                }
            default:
                break
            }
            switch event.kind {
            // A resume restarts the current song's clock: the time the app was not running
            // (crash, relaunch) is not part of the song.
            case .advanced, .jumped, .previous, .requestPlayed, .resumed, .started:
                if let current = event.itemId {
                    becameCurrent[current] = event.at
                }
            // The song behind a break (R104) starts when the break ends.
            case .breakEnded:
                if let current = event.fromItemId {
                    becameCurrent[current] = event.at
                }
            default:
                break
            }
        }
        return items
            .compactMap { item -> (PlayedSong, Int)? in
                guard item.state == .played, let play = plays[item.itemId] else { return nil }
                let song = PlayedSong(
                    item: item,
                    startedAt: play.start,
                    endedAt: play.end,
                    fromRequest: item.origin == .request,
                )
                return (song, play.order)
            }
            .sorted { $0.1 < $1.1 }
            .map(\.0)
    }

    /// The play projection rows for this (finished, gig) show; empty for a rehearsal.
    var playRecords: [PlayRecord] {
        guard kind == .gig else { return [] }
        return playedSongs.map { played in
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

/// One play found in the event log (`playedSongs`).
private struct Play {
    var start: Date
    var end: Date
    /// Index of the event that marked it played.
    var order: Int
}
