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

/// Per-slot arrangements (P3-16, P8-3, R122, R123): open the sheet, save each change as one
/// undo step (R16), reset to the full song.
public extension SetlistsViewModel {
    /// Opens the Arrange Sections sheet for song slot or medley member `item` of setlist
    /// `id`.
    func openArrangement(_ item: SetlistItemID, in id: SetlistID) {
        guard setlist(id)?.songSlot(item) != nil else { return }
        arranging = ArrangingSlot(setlist: id, item: item)
    }

    /// The pre-show checklist's Edit: Arrange mode with slot `item`'s sheet open.
    func editArrangement(_ item: SetlistItemID, in id: SetlistID) {
        builderMode = .arrange
        openArrangement(item, in: id)
    }

    /// The one selected song slot or medley member in Arrange (Setlist > Arrange
    /// Sections...), if any.
    var arrangeableSelection: SetlistItemID? {
        guard let setlist = selected else { return nil }
        let selected = arrangeSelection.ordered(in: rowOrder(of: setlist))
        guard selected.count == 1, setlist.songSlot(selected[0]) != nil else { return nil }
        return selected[0]
    }

    /// Setlist > Arrange Sections...: the selected song slot's sheet.
    func arrangeSelectedSlot() {
        guard let id = selection, let item = arrangeableSelection else { return }
        openArrangement(item, in: id)
    }

    /// Saves slot `item`'s arrangement (nil = Reset to Full Song) as one undo step named
    /// `actionName`; nothing when it is unchanged. The entry is read inside the serialized
    /// write, so a save queued behind another edit of the slot never writes back a stale
    /// copy of it (R154). The song's `.cho` is never touched.
    func setArrangement(
        _ arrangement: SlotArrangement?,
        of item: SetlistItemID,
        in id: SetlistID,
        actionName: String,
    ) async {
        let changed = ChangeFlag()
        await mutate(undo: (id, actionName)) { store in
            guard let setlist = await store.setlist(id: id) else {
                throw SetlistError.setlistNotFound(id)
            }
            guard let slot = setlist.songSlot(item), slot.arrangement != arrangement
            else { return setlist }
            changed.isSet = true
            return try await store.updateSongSlot(
                item,
                overrides: slot.overrides,
                note: slot.note,
                arrangement: arrangement,
                in: id,
            )
        }
        if changed.isSet {
            services.record(.featureUsed(.setlistEdit, .builder))
        }
    }
}

/// Whether a serialized write changed anything (set inside the write, read after it).
@MainActor
private final class ChangeFlag {
    var isSet = false
}
