import Foundation
import Library
import Setlists

/// The set builder's two modes (R84): Pick ticks songs from the library into the set;
/// Arrange shows the set alone to reorder it and split it into parts.
public enum BuilderMode: String, Sendable, Hashable, CaseIterable {
    case pick
    case arrange

    var title: String {
        switch self {
        case .pick: "Pick"
        case .arrange: "Arrange"
        }
    }
}

/// Set building (P3-12, R84-R86): ticks, batch adds, break rows and keyboard moves. Every
/// action is one undo step (R16) through `mutate`.
public extension SetlistsViewModel {
    /// Pick: ticks `song` into setlist `id`, or unticks it (removes its entry). A tick
    /// appends to the end of the set, or to the end of the part whose break row is
    /// selected in Arrange.
    func toggle(_ song: SongID, in id: SetlistID) async {
        guard let setlist = setlist(id) else { return }
        if let index = setlist.entries.firstIndex(where: { $0.songId == song }) {
            await remove(in: id, atOffsets: IndexSet(integer: index))
        } else {
            await insert([song], into: id, at: tickPosition(in: setlist))
        }
    }

    /// Pick's ⌘A: ticks every song in `songs` (the rows the filter shows) that is not in the
    /// set yet, in list order, as one undo step. Returns how many were added.
    @discardableResult
    func tickAll(_ songs: [SongID], in id: SetlistID) async -> Int {
        guard let setlist = setlist(id) else { return 0 }
        let fresh = Self.fresh(songs, for: setlist)
        guard !fresh.isEmpty else { return 0 }
        await insert(fresh, into: id, at: tickPosition(in: setlist))
        return fresh.count
    }

    /// Library multi-select's Add to Setlist: adds `songs` in list order, skipping songs
    /// already in the setlist. Returns (added, already in the set).
    func addSongs(_ songs: [SongID], to id: SetlistID) async -> (added: Int, skipped: Int) {
        guard let setlist = setlist(id) else { return (0, 0) }
        let fresh = Self.fresh(songs, for: setlist)
        let unique = Set(songs).count
        guard !fresh.isEmpty else { return (0, unique) }
        await insert(fresh, into: id, at: nil)
        let added = fresh.count(where: { self.setlist(id)?.contains($0) == true })
        return (added, unique - fresh.count)
    }

    /// Arrange: inserts a break row ("Set N") after the selected rows, else at the end, and
    /// selects it.
    func insertBreak(in id: SetlistID) async {
        guard let setlist = setlist(id) else { return }
        let selected = arrangeSelection.ordered(in: setlist.entries.map(\.itemId))
        let position = selected.last
            .flatMap { last in setlist.entries.firstIndex { $0.itemId == last } }
            .map { $0 + 1 }
        let updated = await mutate(undo: (id, "Insert Break")) { store in
            try await store.insertBreak(into: id, at: position)
        }
        if let updated {
            let index = position ?? updated.entries.count - 1
            if updated.entries.indices.contains(index) {
                arrangeSelection.select(updated.entries[index].itemId)
            }
            services.record(.featureUsed(.setlistEdit, .builder))
        }
    }

    /// Arrange's ⌥↑ / ⌥↓: moves the selected rows one place up (-1) or down (+1) together.
    /// Nothing moves when the block is already at that end.
    func moveSelection(in id: SetlistID, by delta: Int) async {
        guard let setlist = setlist(id), delta == -1 || delta == 1 else { return }
        let ids = setlist.entries.map(\.itemId)
        let offsets = IndexSet(arrangeSelection.ordered(in: ids).compactMap(ids.firstIndex(of:)))
        guard let first = offsets.first, let last = offsets.last else { return }
        let destination = delta < 0 ? first - 1 : last + 2
        guard (0 ... ids.count).contains(destination), delta < 0 ? first > 0 : last < ids.count - 1
        else { return }
        await move(in: id, fromOffsets: offsets, toOffset: destination)
    }

    /// Whether Arrange's Move Up (-1) / Move Down (+1) can act on the selection now.
    func canMoveSelection(in id: SetlistID, by delta: Int) -> Bool {
        guard let setlist = setlist(id), setlist.readOnly == nil else { return false }
        let ids = setlist.entries.map(\.itemId)
        let selected = arrangeSelection.ordered(in: ids).compactMap(ids.firstIndex(of:))
        guard let first = selected.first, let last = selected.last else { return false }
        return delta < 0 ? first > 0 : last < ids.count - 1
    }

    /// Edits a break row's label and intermission.
    func updateBreak(_ entry: SetlistEntry, in id: SetlistID) async {
        await mutate(undo: (id, "Edit Break")) { store in
            try await store.updateEntry(entry, in: id)
        }
    }

    /// Where a tick lands: the end of the part whose break row is the only selected row in
    /// Arrange (before the next break), else the end of the set (nil).
    internal func tickPosition(in setlist: Setlist) -> Int? {
        let ids = setlist.entries.map(\.itemId)
        let selected = arrangeSelection.ordered(in: ids)
        guard selected.count == 1, let index = ids.firstIndex(of: selected[0]),
              setlist.entries[index].isBreak
        else { return nil }
        return setlist.entries[(index + 1)...].firstIndex(where: \.isBreak)
    }

    /// `songs` without the ones in `setlist` or repeated, in order.
    private static func fresh(_ songs: [SongID], for setlist: Setlist) -> [SongID] {
        var seen: Set<SongID> = []
        return songs.filter { !setlist.contains($0) && seen.insert($0).inserted }
    }
}
