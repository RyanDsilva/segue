// Phase 2, unit A1: the show state machine as pure transitions on `ShowRecord`.
//
// `ShowController` resolves everything that needs IO (song titles, IDs, the clock) first,
// then applies an action here synchronously, so a transition can never interleave with
// another one on the actor and the result is deterministic for a given input.

import Foundation
import Library
import Support

/// Inputs a transition needs from outside the record.
struct TransitionContext {
    /// The action's timestamp (already stamped to millisecond precision).
    var now: Date
    /// Mints new item and request IDs.
    var newID: () -> ULID
    /// The title of the song the action names (play now, insert next, add request); nil when
    /// that song is not in the library.
    var songTitle: String?
}

extension ShowRecord {
    /// Applies `action` and returns the items it marked played (for duration samples). An
    /// action that changes nothing leaves the record equal to before (no event appended).
    mutating func apply(_ action: ShowAction, _ context: TransitionContext) throws -> [ShowItemID] {
        if let played = try applyNavigation(action, at: context.now) {
            return played
        }
        try applyAddition(action, context)
        return []
    }

    /// Actions that move through the existing items; nil for the others.
    private mutating func applyNavigation(
        _ action: ShowAction,
        at now: Date,
    ) throws -> [ShowItemID]? {
        switch action {
        case .next:
            return advance(marking: .played, at: now)
        case .skipCurrent:
            return advance(marking: .skipped, at: now)
        case .previous:
            goBack(at: now)
        case let .skip(itemId):
            return try skip(itemId, at: now)
        case let .unskip(itemId):
            let index = try indexOfItem(itemId)
            if items[index].state == .skipped {
                items[index].state = .pending
                events.append(ShowEvent(at: now, kind: .unskipped, itemId: itemId))
            }
        case let .jump(itemId):
            _ = try indexOfItem(itemId)
            jump(to: itemId, at: now)
        case let .move(offsets, destination):
            try move(fromOffsets: offsets, toOffset: destination, at: now)
        default:
            return nil
        }
        return []
    }

    /// Actions that add songs or work the request queue.
    private mutating func applyAddition(_ action: ShowAction, _ context: TransitionContext) throws {
        switch action {
        case let .playNow(songId):
            try playNow(songId, context)
        case let .insertNext(songId):
            try insertNext(songId, context)
        case let .addRequest(songId, note):
            try addRequest(songId, note: note, context)
        case .playNextRequest:
            if let request = queuedRequests.first {
                try playRequest(request.requestId, context)
            }
        case let .playRequest(requestId):
            try playRequest(requestId, context)
        case let .dropRequest(requestId):
            guard let index = requests.firstIndex(where: { $0.requestId == requestId }) else {
                throw ShowError.requestNotFound(requestId)
            }
            if requests[index].state == .queued {
                requests[index].state = .dropped
                events.append(ShowEvent(
                    at: context.now,
                    kind: .requestDropped,
                    requestId: requestId,
                ))
            }
        default:
            break
        }
    }

    /// Drawer skip: a pending item is marked skipped; skipping current is `skipCurrent`.
    private mutating func skip(_ itemId: ShowItemID, at now: Date) throws -> [ShowItemID] {
        let index = try indexOfItem(itemId)
        if items[index].state == .current {
            return advance(marking: .skipped, at: now)
        }
        if items[index].state == .pending {
            items[index].state = .skipped
            events.append(ShowEvent(at: now, kind: .skipped, itemId: itemId))
        }
        return []
    }

    private mutating func insertNext(_ songId: SongID, _ context: TransitionContext) throws {
        guard let title = context.songTitle else { throw ShowError.songNotFound(songId) }
        let item = ShowItem(
            itemId: ShowItemID(context.newID()),
            songId: songId,
            title: title,
            origin: .inserted,
        )
        items.insert(item, at: insertionIndex(afterCurrent: true))
        events.append(ShowEvent(at: context.now, kind: .inserted, itemId: item.itemId))
    }

    private mutating func addRequest(
        _ songId: SongID,
        note: String?,
        _ context: TransitionContext,
    ) throws {
        guard let title = context.songTitle else { throw ShowError.songNotFound(songId) }
        let request = ShowRequest(
            requestId: ShowRequestID(context.newID()),
            songId: songId,
            title: title,
            addedAt: context.now,
            note: Self.trimmed(note),
        )
        requests.append(request)
        events.append(ShowEvent(
            at: context.now,
            kind: .requestAdded,
            requestId: request.requestId,
        ))
    }

    /// Ends the run: current (if any) is marked played and `endedAt` set to `now`. A stale
    /// close passes the show's last update as `now` (open question 15).
    /// - Returns: the item marked played, if any.
    mutating func finish(at now: Date, closure: ShowClosure) -> ShowItemID? {
        let leaving = currentItemId
        if let index = currentIndex {
            items[index].state = .played
        }
        currentItemId = nil
        let kind: ShowEvent.Kind = closure == .ended ? .ended : .autoClosed
        events.append(ShowEvent(at: now, kind: kind, fromItemId: leaving))
        endedAt = now
        updatedAt = now
        self.closure = closure
        return leaving
    }

    /// Index of the item `next` picks: the first pending item after the current one in
    /// playing order (decisions.md, phase 2 build rulings: songs passed over by "Play now"
    /// stay pending and are not revisited automatically). With nothing current, the first
    /// pending item after the last one that was current.
    var nextPendingIndex: Int? {
        let start = (currentIndex ?? cursorIndex).map { $0 + 1 } ?? 0
        return items[start...].firstIndex { $0.state == .pending }
    }

    /// With nothing current (the end was reached): the item that was current last, from the
    /// most recent event that left it.
    private var cursorIndex: Int? {
        guard currentItemId == nil else { return currentIndex }
        // Only `next` / `skipCurrent` leave nothing current, and both name the item left.
        for event in events.reversed() where event.kind == .advanced || event.kind == .skipped {
            if let anchor = event.fromItemId,
               let index = items.firstIndex(where: { $0.itemId == anchor })
            {
                return index
            }
        }
        return nil
    }

    /// The item the most recent `advanced` event marked played that is still played: what
    /// `previous` returns to.
    var lastPlayedItemId: ShowItemID? {
        let played = Set(items.lazy.filter { $0.state == .played }.map(\.itemId))
        return events.last { event in
            event.kind == .advanced && event.fromItemId.map(played.contains) == true
        }?.fromItemId
    }

    // MARK: - Private

    private func indexOfItem(_ itemId: ShowItemID) throws -> Int {
        guard let index = items.firstIndex(where: { $0.itemId == itemId }) else {
            throw ShowError.itemNotFound(itemId)
        }
        return index
    }

    /// Where a song added during the show goes: before current (play now, requests) or right
    /// after it (insert next). Without a current item, right after the last one that was
    /// current, so `next` reaches it.
    private func insertionIndex(afterCurrent: Bool) -> Int {
        if let current = currentIndex {
            return afterCurrent ? current + 1 : current
        }
        return cursorIndex.map { $0 + 1 } ?? 0
    }

    /// Makes `itemId` current with the scroll at the top. The caller has already moved the
    /// previous current item to its new state.
    private mutating func makeCurrent(_ itemId: ShowItemID?) {
        currentItemId = itemId
        scrollPosition = 0
        if let itemId, let index = items.firstIndex(where: { $0.itemId == itemId }) {
            items[index].state = .current
        }
    }

    /// Sends current back to pending (interrupted) and returns its ID.
    private mutating func interruptCurrent() -> ShowItemID? {
        guard let index = currentIndex else { return nil }
        items[index].state = .pending
        return items[index].itemId
    }

    /// `next` (mark played) or `skipCurrent` (mark skipped): the next pending item in playing
    /// order becomes current, or none at the end.
    private mutating func advance(marking mark: ItemState, at now: Date) -> [ShowItemID] {
        let leaving = currentIndex.map { items[$0].itemId }
        let next = nextPendingIndex.map { items[$0].itemId }
        if leaving == nil, mark == .skipped || next == nil {
            return []
        }
        if let index = currentIndex {
            items[index].state = mark
        }
        makeCurrent(next)
        if mark == .played {
            events.append(ShowEvent(at: now, kind: .advanced, itemId: next, fromItemId: leaving))
            return leaving.map { [$0] } ?? []
        }
        events.append(ShowEvent(at: now, kind: .skipped, itemId: leaving, fromItemId: leaving))
        if let next {
            // Moving on without playing: `advanced` with no `fromItemId`.
            events.append(ShowEvent(at: now, kind: .advanced, itemId: next))
        }
        return []
    }

    private mutating func goBack(at now: Date) {
        guard let back = lastPlayedItemId else { return }
        let leaving = interruptCurrent()
        makeCurrent(back)
        events.append(ShowEvent(at: now, kind: .previous, itemId: back, fromItemId: leaving))
    }

    private mutating func jump(to itemId: ShowItemID, at now: Date) {
        guard itemId != currentItemId else { return }
        let leaving = interruptCurrent()
        makeCurrent(itemId)
        events.append(ShowEvent(at: now, kind: .jumped, itemId: itemId, fromItemId: leaving))
    }

    /// Play now: the first pending item of the song is jumped to without moving it (open
    /// question 16); otherwise a new inserted item goes before current and becomes current.
    private mutating func playNow(_ songId: SongID, _ context: TransitionContext) throws {
        if let pending = items.first(where: { $0.songId == songId && $0.state == .pending }) {
            jump(to: pending.itemId, at: context.now)
            return
        }
        guard let title = context.songTitle else { throw ShowError.songNotFound(songId) }
        let item = ShowItem(
            itemId: ShowItemID(context.newID()),
            songId: songId,
            title: title,
            origin: .inserted,
        )
        items.insert(item, at: insertionIndex(afterCurrent: false))
        events.append(ShowEvent(at: context.now, kind: .inserted, itemId: item.itemId))
        jump(to: item.itemId, at: context.now)
    }

    /// A queued request becomes an item before current and is made current; current goes
    /// back to pending (open question 5). A request no longer queued is left alone.
    private mutating func playRequest(
        _ requestId: ShowRequestID,
        _ context: TransitionContext,
    ) throws {
        guard let index = requests.firstIndex(where: { $0.requestId == requestId }) else {
            throw ShowError.requestNotFound(requestId)
        }
        guard requests[index].state == .queued else { return }
        let request = requests[index]
        requests[index].state = .played
        let item = ShowItem(
            itemId: ShowItemID(context.newID()),
            songId: request.songId,
            title: request.title,
            origin: .request,
            requestId: requestId,
            note: request.note,
        )
        items.insert(item, at: insertionIndex(afterCurrent: false))
        let leaving = interruptCurrent()
        makeCurrent(item.itemId)
        events.append(ShowEvent(
            at: context.now,
            kind: .requestPlayed,
            itemId: item.itemId,
            fromItemId: leaving,
            requestId: requestId,
        ))
    }

    /// Drawer drag with `Array.move(fromOffsets:toOffset:)` semantics. One `reordered` event
    /// per moved item; a drag that changes nothing is a no-op.
    private mutating func move(
        fromOffsets offsets: IndexSet,
        toOffset destination: Int,
        at now: Date,
    ) throws {
        guard !offsets.isEmpty,
              offsets.allSatisfy(items.indices.contains),
              (0 ... items.count).contains(destination)
        else {
            throw ShowError.invalidOffsets
        }
        let moving = offsets.map { items[$0] }
        var remaining = items.enumerated().filter { !offsets.contains($0.offset) }.map(\.element)
        let target = destination - offsets.count(in: 0 ..< destination)
        remaining.insert(contentsOf: moving, at: target)
        guard remaining.map(\.itemId) != items.map(\.itemId) else { return }
        items = remaining
        for item in moving {
            events.append(ShowEvent(at: now, kind: .reordered, itemId: item.itemId))
        }
    }

    static func trimmed(_ text: String?) -> String? {
        guard let text = text?.trimmingCharacters(in: .whitespacesAndNewlines),
              !text.isEmpty
        else {
            return nil
        }
        return text
    }
}
