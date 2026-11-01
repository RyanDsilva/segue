// P9-3 8.2: medleys inside a running show. Consecutive items with the same
// `ShowMedleyRef.slot` are one medley; nothing is ever inserted between its members, and it
// moves as one block.

import Foundation
import Library
import Setlists

extension ShowRecord {
    /// The medley the current item plays in, if any.
    var currentMedleySlot: SetlistItemID? {
        currentItem?.medley?.slot
    }

    /// The index of the last item of the medley block holding `index`; nil when that item is
    /// not a medley member.
    func medleyEnd(of index: Int) -> Int? {
        guard let slot = items[index].medley?.slot else { return nil }
        var end = index
        while end + 1 < items.count, items[end + 1].medley?.slot == slot {
            end += 1
        }
        return end
    }

    /// The first pending item of `songId` after the current item, else the first pending one
    /// (a reprise may leave both occurrences pending, P9-3 8.2).
    func firstPendingIndex(of songId: SongID) -> Int? {
        let start = (currentIndex ?? cursorIndex).map { $0 + 1 } ?? 0
        let pending = items.indices.filter {
            items[$0].songId == songId && items[$0].state == .pending
        }
        return pending.first { $0 >= start } ?? pending.first
    }

    /// `offsets` widened to whole medley blocks and `destination` moved out of any medley
    /// block it falls inside.
    func medleyBlockMove(_ offsets: IndexSet, _ destination: Int) -> (IndexSet, Int) {
        var widened = offsets
        for index in offsets {
            guard let slot = items[index].medley?.slot else { continue }
            for other in items.indices where items[other].medley?.slot == slot {
                widened.insert(other)
            }
        }
        var target = destination
        if target > 0, target < items.count,
           let slot = items[target].medley?.slot, items[target - 1].medley?.slot == slot,
           !widened.contains(target)
        {
            target = (medleyEnd(of: target) ?? target) + 1
        }
        return (widened, target)
    }
}
