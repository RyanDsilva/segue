import Foundation

/// Editing one slot, break rows and changeover (R85, R86, R105).
public extension SetlistStore {
    /// Replaces the overrides and note of the song slot with `entry.itemId` (its song
    /// stays), or the label and intermission of the break row with that ID, and saves.
    /// Throws `invalidOffsets` when no entry has that item ID or `entry` is not the same
    /// kind of slot (a song never turns into a break, or the other way round).
    @discardableResult
    func updateEntry(_ entry: SetlistEntry, in id: SetlistID) throws -> Setlist {
        try mutate(id) { entries in
            guard let index = entries.firstIndex(where: { $0.itemId == entry.itemId }),
                  entries[index].isBreak == entry.isBreak
            else {
                throw SetlistError.invalidOffsets(id)
            }
            if let info = entry.breakInfo {
                entries[index].kind = .break(info)
            } else {
                entries[index].overrides = entry.overrides
                entries[index].note = entry.note
            }
        }
    }

    /// Inserts a break row at `offset` (nil = append) and saves. Its label defaults to the
    /// part it opens ("Set 2", `Setlist.breakLabel(at:)`); automatic labels after it are
    /// renumbered. Throws `invalidOffsets`
    /// when `offset` is outside `0 ... entries.count`.
    @discardableResult
    func insertBreak(
        into id: SetlistID,
        at offset: Int? = nil,
        label: String? = nil,
        length: TimeInterval? = nil,
    ) throws -> Setlist {
        try mutateSetlist(id) { setlist in
            let position = offset ?? setlist.entries.count
            guard (0 ... setlist.entries.count).contains(position) else {
                throw SetlistError.invalidOffsets(id)
            }
            let info = SetlistBreak(
                label: label ?? setlist.breakLabel(at: position),
                length: length,
            )
            setlist.entries.insert(
                SetlistEntry(itemId: SetlistItemID(ids.next()), break: info),
                at: position,
            )
            setlist.renumberBreaks()
        }
    }
}
