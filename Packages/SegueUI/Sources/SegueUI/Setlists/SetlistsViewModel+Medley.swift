import Foundation
import Library
import Setlists

/// Medleys in the builder (P9-3 6.1-6.4): make, ungroup, add and move members, remove,
/// rename and transitions. Every action is one builder undo step (R16) through the
/// serialized snapshot path (R154).
public extension SetlistsViewModel {
    /// The rows Arrange shows, in order: each slot and break, and after an expanded medley's
    /// header its members (the order ↑ / ↓ and ⇧-click walk).
    func rowOrder(of setlist: Setlist) -> [SetlistItemID] {
        setlist.entries.flatMap { entry -> [SetlistItemID] in
            guard let medley = entry.medley, !collapsedMedleys.contains(entry.itemId) else {
                return [entry.itemId]
            }
            return [entry.itemId] + medley.members.map(\.itemId)
        }
    }

    /// The selected rows that Make Medley would join: two or more song slots or medleys
    /// with at least two songs among them; nil when a break or a member is selected, or
    /// the setlist is read-only (Setlist > Make Medley is disabled then).
    func medleyCandidates(in id: SetlistID) -> [SetlistItemID]? {
        guard let setlist = setlist(id), setlist.readOnly == nil else { return nil }
        let selected = arrangeSelection.ordered(in: rowOrder(of: setlist))
        let rows = selected.compactMap(setlist.entry)
        guard rows.count == selected.count, rows.count >= 2,
              rows.allSatisfy({ !$0.isBreak }),
              rows.reduce(0, { $0 + $1.songIds.count }) >= 2
        else { return nil }
        return rows.map(\.itemId)
    }

    /// The count Make Medley's context menu names ("Make Medley from 3 Songs").
    func medleyCandidateSongCount(in id: SetlistID) -> Int {
        guard let setlist = setlist(id), let rows = medleyCandidates(in: id) else { return 0 }
        return rows.compactMap(setlist.entry).reduce(0) { $0 + $1.songIds.count }
    }

    /// Setlist > Make Medley (⇧⌘M): joins the selected rows into one medley where the
    /// first of them was, and selects it.
    func makeMedley(in id: SetlistID) async {
        guard let rows = medleyCandidates(in: id) else { return }
        let made = ResultBox<SetlistItemID>()
        let updated = await mutate(undo: (id, "Make Medley")) { store in
            let result = try await store.makeMedley(from: rows, in: id)
            made.value = result.medley
            return result.setlist
        }
        if updated != nil, let medley = made.value {
            collapsedMedleys.remove(medley)
            arrangeSelection.select(medley)
            services.record(.featureUsed(.setlistEdit, .builder))
        }
    }

    /// The medley the single selected row is (or belongs to), if any.
    func selectedMedley(in id: SetlistID) -> SetlistItemID? {
        guard let setlist = setlist(id) else { return nil }
        let selected = arrangeSelection.ordered(in: rowOrder(of: setlist))
        guard selected.count == 1 else { return nil }
        if setlist.entry(selected[0])?.isMedley == true {
            return selected[0]
        }
        return setlist.member(selected[0])?.entry.itemId
    }

    /// Setlist > Ungroup Medley (⌥⇧⌘M): its members become slots in place.
    func ungroup(_ medley: SetlistItemID, in id: SetlistID) async {
        let first = setlist(id)?.entry(medley)?.medley?.members.first?.itemId
        let updated = await mutate(undo: (id, "Ungroup Medley")) { store in
            try await store.ungroup(medley, in: id)
        }
        if updated != nil {
            collapsedMedleys.remove(medley)
            // The members keep their item IDs as slots: select the first of them.
            arrangeSelection.select(first)
            services.record(.featureUsed(.setlistEdit, .builder))
        }
    }

    /// Context menu "Remove from Medley" (or dragging a member out): it becomes a slot
    /// right after the medley.
    func removeFromMedley(_ member: SetlistItemID, in id: SetlistID) async {
        let updated = await mutate(undo: (id, "Remove from Medley")) { store in
            try await store.removeFromMedley(member, in: id)
        }
        if updated != nil {
            arrangeSelection.select(member)
            services.record(.featureUsed(.setlistEdit, .builder))
        }
    }

    /// ⌫ or the row's remove button on a member: it leaves the set.
    func removeMember(_ member: SetlistItemID, in id: SetlistID) async {
        await mutate(undo: (id, "Remove Song")) { store in
            try await store.removeMember(member, in: id)
        }
        services.record(.featureUsed(.setlistEdit, .builder))
    }

    /// ⌥↑ / ⌥↓ on a member: one place within its medley. Returns false at the medley's
    /// edge (the caller beeps): a member never leaves its medley this way.
    @discardableResult
    func moveMember(_ member: SetlistItemID, by delta: Int, in id: SetlistID) async -> Bool {
        guard let setlist = setlist(id), let (_, index) = setlist.member(member),
              let count = setlist.member(member)?.entry.medley?.members.count,
              (0 ..< count).contains(index + delta)
        else { return false }
        await mutate(undo: (id, "Move Song in Medley")) { store in
            try await store.moveMember(member, to: index + delta, in: id)
        }
        services.record(.featureUsed(.setlistEdit, .builder))
        return true
    }

    /// Whether ⌥↑ (-1) / ⌥↓ (+1) can move the single selected member within its medley.
    func canMoveMember(by delta: Int, in id: SetlistID) -> Bool {
        guard let setlist = setlist(id), setlist.readOnly == nil,
              let member = selectedMember(in: id),
              let (entry, index) = setlist.member(member),
              let count = entry.medley?.members.count
        else { return false }
        return (0 ..< count).contains(index + delta)
    }

    /// The single selected row when it is a medley member.
    func selectedMember(in id: SetlistID) -> SetlistItemID? {
        guard let setlist = setlist(id) else { return nil }
        let selected = arrangeSelection.ordered(in: rowOrder(of: setlist))
        guard selected.count == 1, setlist.member(selected[0]) != nil else { return nil }
        return selected[0]
    }

    /// Renames `medley` (double-click the title, Return on its header); blank = "Medley".
    func renameMedley(_ medley: SetlistItemID, to title: String, in id: SetlistID) async {
        await mutate(undo: (id, "Rename Medley")) { store in
            try await store.renameMedley(medley, to: title, in: id)
        }
    }

    /// Commits a transition row (Return or focus loss): one undo step.
    func setTransition(_ text: String, member: SetlistItemID, in id: SetlistID) async {
        await mutate(undo: (id, "Edit Transition")) { store in
            try await store.setTransition(text, member: member, in: id)
        }
    }

    /// A member's slot popover (key, capo, note): saved like a song slot's.
    func updateSongSlot(_ entry: SetlistEntry, in id: SetlistID) async {
        await mutate(undo: (id, "Edit Song Settings")) { store in
            try await store.updateSongSlot(
                entry.itemId,
                overrides: entry.overrides,
                note: entry.note,
                arrangement: entry.arrangement,
                in: id,
            )
        }
    }

    /// Dropping library songs on a medley's member area: each joins at `offset` in order.
    /// A song already a member anywhere is refused (the store throws, nothing changes).
    func addToMedley(
        _ songs: [SongID],
        medley: SetlistItemID,
        at offset: Int?,
        in id: SetlistID,
    ) async {
        guard !songs.isEmpty else { return }
        await mutate(undo: (id, "Add to Medley")) { store in
            var updated: Setlist?
            for (step, song) in songs.enumerated() {
                updated = try await store.addToMedley(
                    song,
                    medley: medley,
                    at: offset.map { $0 + step },
                    in: id,
                )
            }
            guard let updated else { throw SetlistError.setlistNotFound(id) }
            return updated
        }
        services.record(.featureUsed(.setlistEdit, .builder))
    }

    /// Dragging a set row onto a medley's member area: the slot joins at `offset`.
    func moveIntoMedley(
        _ item: SetlistItemID,
        medley: SetlistItemID,
        at offset: Int?,
        in id: SetlistID,
    ) async {
        await mutate(undo: (id, "Add to Medley")) { store in
            try await store.moveIntoMedley(item, medley: medley, at: offset, in: id)
        }
        services.record(.featureUsed(.setlistEdit, .builder))
    }

    /// ← / → on a medley header and the disclosure chevron.
    func setCollapsed(_ medley: SetlistItemID, _ collapsed: Bool) {
        if collapsed {
            collapsedMedleys.insert(medley)
        } else {
            collapsedMedleys.remove(medley)
        }
    }
}

/// A value set inside a serialized write and read after it.
@MainActor
final class ResultBox<Value> {
    var value: Value?
}
