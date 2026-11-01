// P9-3 9.1: the stage lays a medley out as one plan, so the show state carries every member
// of the current item's medley with its song.

import Library

extension ShowRecord {
    /// Every member of the current item's medley, in order, with its song from `song`;
    /// empty outside a medley.
    func medleySlots(song: (SongID) -> SongRecord?) -> [ShowSlot] {
        guard let slot = currentMedleySlot else { return [] }
        return items.indices.filter { items[$0].medley?.slot == slot }.map { index in
            ShowSlot(item: items[index], position: index, song: song(items[index].songId))
        }
    }
}
