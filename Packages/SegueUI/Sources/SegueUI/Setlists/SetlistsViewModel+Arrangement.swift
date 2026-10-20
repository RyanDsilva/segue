import Foundation
import Library
import Setlists

/// A song slot whose Arrange Sections sheet is open.
public struct ArrangingSlot: Identifiable, Hashable, Sendable {
    public var setlist: SetlistID
    public var item: SetlistItemID

    public var id: SetlistItemID {
        item
    }
}

/// Per-slot arrangements (P3-16, R122, R123): open the sheet, save each change as one undo
/// step (R16), reset to the full song.
public extension SetlistsViewModel {
    /// Opens the Arrange Sections sheet for song slot `item` of setlist `id`.
    func openArrangement(_ item: SetlistItemID, in id: SetlistID) {
        guard setlist(id)?.entry(item)?.songId != nil else { return }
        arranging = ArrangingSlot(setlist: id, item: item)
    }

    /// The pre-show checklist's Edit: Arrange mode with slot `item`'s sheet open.
    func editArrangement(_ item: SetlistItemID, in id: SetlistID) {
        builderMode = .arrange
        openArrangement(item, in: id)
    }

    /// The one selected song slot in Arrange (Setlist > Arrange Sections...), if any.
    var arrangeableSelection: SetlistItemID? {
        guard let setlist = selected else { return nil }
        let selected = arrangeSelection.ordered(in: setlist.entries.map(\.itemId))
        guard selected.count == 1, setlist.entry(selected[0])?.songId != nil else { return nil }
        return selected[0]
    }

    /// Setlist > Arrange Sections...: the selected song slot's sheet.
    func arrangeSelectedSlot() {
        guard let id = selection, let item = arrangeableSelection else { return }
        openArrangement(item, in: id)
    }

    /// Saves slot `item`'s arrangement (nil = Reset to Full Song) as one undo step named
    /// `actionName`. The song's `.cho` is never touched.
    func setArrangement(
        _ arrangement: SlotArrangement?,
        of item: SetlistItemID,
        in id: SetlistID,
        actionName: String,
    ) async {
        guard var entry = await store.setlist(id: id)?.entry(item), entry.songId != nil,
              entry.arrangement != arrangement
        else { return }
        entry.arrangement = arrangement
        await mutate(undo: (id, actionName)) { store in
            try await store.updateEntry(entry, in: id)
        }
        services.record(.featureUsed(.setlistEdit, .builder))
    }
}
