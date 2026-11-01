// P3-15: no repeats within a show (decisions.md R102, R112). A song is performed at most
// once per show: adding a song that was already played, is playing now or is still
// upcoming (a pending item or a queued request) is refused, and an upcoming one can be
// moved to next instead. "Played" means actually played, in gigs and rehearsals alike; a
// skipped song may be added back, which reuses its skipped item. Break rows are never
// items, so they never count as songs.

import Foundation
import Library
import Setlists
import Support

/// Where a song stands in a show.
public enum SongStanding: Sendable, Equatable {
    /// Not in the show, or only dropped as a request.
    case free
    /// Skipped and never played: it may be added back (R112), reusing this item.
    case skipped(ShowItemID)
    /// Played tonight (an item marked played).
    case played
    /// The current song.
    case current
    /// A pending item: still to come in the set (`isNext` when `next` goes to it).
    case upcoming(ShowItemID, isNext: Bool)
    /// A queued request (`isNext` when it is the first one in the queue).
    case requested(ShowRequestID, isNext: Bool)
}

/// Why an action was refused under R102, carried by `ShowError.repeatRefused`.
public enum RepeatRefusal: Sendable, Equatable {
    case alreadyPlayed
    case playingNow
    /// Still to come in the set: `moveToNext` moves the existing item instead.
    case upcoming(ShowItemID, isNext: Bool)
    /// Already queued as a request: `moveToNext` moves it to the front of the queue.
    case requested(ShowRequestID, isNext: Bool)

    /// The one-step alternative the refusal offers ("Move to Next"); nil when there is
    /// none (played, playing now) or the song is already next.
    public var moveToNext: ShowAction? {
        switch self {
        case let .upcoming(item, isNext: false):
            .moveToNext(item)
        case let .requested(request, isNext: false):
            .moveRequestToFront(request)
        default:
            nil
        }
    }
}

public extension ShowRecord {
    /// Where `songId` stands in this show. Played wins over everything else (a show saved
    /// before R102 may hold a song twice), then current, upcoming, requested and skipped.
    func standing(of songId: SongID) -> SongStanding {
        standing(of: songId, excluding: nil)
    }

    /// The R102 refusal `action` meets, if any:
    /// - Insert Next and Add to Requests are refused for a song played, current, upcoming
    ///   or requested.
    /// - Play Now is refused only for a played song: on the current song it does nothing,
    ///   on an upcoming one it jumps to that item and on a requested one it plays that
    ///   request, so it never adds a second entry.
    /// - Bringing a skipped item back (unskip, jump, Move to Next) is refused when its song
    ///   is played, current, upcoming or requested elsewhere.
    func repeatRefusal(for action: ShowAction) -> RepeatRefusal? {
        switch action {
        case let .addRequest(songId, _), let .insertNext(songId):
            return Self.refusal(for: standing(of: songId))
        case let .playNow(songId):
            return standing(of: songId) == .played ? .alreadyPlayed : nil
        case let .jump(itemId), let .moveToNext(itemId), let .unskip(itemId):
            guard let item = items.first(where: { $0.itemId == itemId }),
                  item.state == .skipped
            else { return nil }
            return Self.refusal(for: standing(of: item.songId, excluding: itemId))
        default:
            return nil
        }
    }

    /// The song an action names (search actions) or acts on (item actions), for
    /// `ShowError.repeatRefused`.
    internal func songId(of action: ShowAction) -> SongID? {
        switch action {
        case let .addRequest(songId, _), let .insertNext(songId), let .playNow(songId):
            songId
        case let .jump(itemId), let .moveToNext(itemId), let .unskip(itemId):
            items.first { $0.itemId == itemId }?.songId
        default:
            nil
        }
    }

    private static func refusal(for standing: SongStanding) -> RepeatRefusal? {
        switch standing {
        case .free, .skipped:
            nil
        case .played:
            .alreadyPlayed
        case .current:
            .playingNow
        case let .upcoming(item, isNext):
            .upcoming(item, isNext: isNext)
        case let .requested(request, isNext):
            .requested(request, isNext: isNext)
        }
    }

    private func standing(of songId: SongID, excluding excluded: ShowItemID?) -> SongStanding {
        let mine = items.indices.filter { index in
            items[index].songId == songId && items[index].itemId != excluded
        }
        // A planned medley reprise (P9-3 decision 8) plays the song twice: while one of its
        // occurrences is still to come, it stands as current or upcoming, not played.
        let reprise = isPlannedReprise(songId)
        if !reprise, mine.contains(where: { items[$0].state == .played }) {
            return .played
        }
        if mine.contains(where: { items[$0].state == .current }) {
            return .current
        }
        let pending = reprise ? firstPendingIndex(of: songId).flatMap { index in
            mine.contains(index) ? index : nil
        } : mine.first(where: { items[$0].state == .pending })
        if let index = pending {
            return .upcoming(items[index].itemId, isNext: index == nextPendingIndex)
        }
        if reprise, mine.contains(where: { items[$0].state == .played }) {
            return .played
        }
        let queued = queuedRequests
        if let request = queued.first(where: { $0.songId == songId }) {
            return .requested(request.requestId, isNext: queued.first == request)
        }
        if let index = mine.first(where: { items[$0].state == .skipped }) {
            return .skipped(items[index].itemId)
        }
        return .free
    }
}

extension ShowRecord {
    /// Whether the plan holds `songId` as a medley member and as a plain slot.
    func isPlannedReprise(_ songId: SongID) -> Bool {
        planned.contains { $0.songId == songId }
            && planned.contains { $0.medley?.songIds.contains(songId) ?? false }
    }
}

// MARK: - Transitions

extension ShowRecord {
    /// Throws `repeatRefused` when `action` would perform or queue a song twice.
    func checkNoRepeat(_ action: ShowAction) throws {
        guard let refusal = repeatRefusal(for: action), let songId = songId(of: action) else {
            return
        }
        throw ShowError.repeatRefused(songId, refusal)
    }

    /// Move to Next for an item or a request; false for any other action.
    mutating func applyMoveToNext(_ action: ShowAction, at now: Date) throws -> Bool {
        switch action {
        case let .moveToNext(itemId):
            try moveToNext(itemId, at: now)
        case let .moveRequestToFront(requestId):
            try moveRequestToFront(requestId, at: now)
        default:
            return false
        }
        return true
    }

    /// Move to Next: a pending or skipped item (skipped goes back to pending) moves right
    /// after current, or, with nothing current, right after the last item that was. The
    /// current item and played items stay where they are.
    mutating func moveToNext(_ itemId: ShowItemID, at now: Date) throws {
        guard let index = items.firstIndex(where: { $0.itemId == itemId }) else {
            throw ShowError.itemNotFound(itemId)
        }
        guard items[index].state == .pending || items[index].state == .skipped else { return }
        // A medley member never leaves its medley (P9-3 8.2): it is only brought back.
        if items[index].medley != nil {
            if items[index].state == .skipped {
                items[index].state = .pending
                events.append(ShowEvent(at: now, kind: .unskipped, itemId: itemId))
            }
            return
        }
        if items[index].state == .skipped {
            items[index].state = .pending
            events.append(ShowEvent(at: now, kind: .unskipped, itemId: itemId))
        }
        let item = items.remove(at: index)
        let target = insertionIndex(afterCurrent: true)
        items.insert(item, at: target)
        if target != index {
            events.append(ShowEvent(at: now, kind: .reordered, itemId: itemId))
        }
    }

    /// The front of the request queue, so the footer shows it as the next request and `R`
    /// plays it. Recorded as a `reordered` event naming the request.
    mutating func moveRequestToFront(_ requestId: ShowRequestID, at now: Date) throws {
        guard let index = requests.firstIndex(where: { $0.requestId == requestId }) else {
            throw ShowError.requestNotFound(requestId)
        }
        guard requests[index].state == .queued,
              let front = requests.firstIndex(where: { $0.state == .queued }),
              front != index
        else { return }
        let request = requests.remove(at: index)
        requests.insert(request, at: front)
        events.append(ShowEvent(at: now, kind: .reordered, requestId: requestId))
    }
}
