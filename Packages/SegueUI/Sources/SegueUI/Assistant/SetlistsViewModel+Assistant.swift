import Foundation
import Library
import Setlists

/// The set assistant's writes (P3-7, R114, R115): Build fills the open setlist as one undo
/// step, and song slots lock and unlock (saved in the file).
public extension SetlistsViewModel {
    /// Replaces setlist `id`'s entries with a built set and, when the request named a length,
    /// sets the setlist's target to it: one undo step ("Build Set" / "Rebuild Set").
    @discardableResult
    func applyAssistantSet(
        _ entries: [SetlistEntry],
        target: TimeInterval?,
        to id: SetlistID,
        rebuilt: Bool,
    ) async -> Setlist? {
        await mutate(undo: (id, rebuilt ? "Rebuild Set" : "Build Set")) { store in
            var updated = try await store.replaceEntries(entries, in: id)
            if let target, target != updated.targetDuration {
                updated = try await store.updateDetails(SetlistDetails(
                    venue: updated.venue,
                    date: updated.date,
                    targetDuration: target,
                    changeoverSeconds: updated.changeoverSeconds,
                ), of: id)
            }
            return updated
        }
    }

    /// Locks or unlocks song slots `items` (Rebuild keeps locked songs in place): one undo
    /// step.
    func setLocked(_ items: Set<SetlistItemID>, _ locked: Bool, in id: SetlistID) async {
        let name = locked ? (items.count == 1 ? "Lock Song" : "Lock Songs")
            : (items.count == 1 ? "Unlock Song" : "Unlock Songs")
        await mutate(undo: (id, name)) { store in
            try await store.setLocked(items, locked, in: id)
        }
    }

    /// Toggles the lock of song slot `item`.
    func toggleLock(_ item: SetlistItemID, in id: SetlistID) async {
        guard let entry = setlist(id)?.entry(item), !entry.isBreak else { return }
        await setLocked([item], !entry.locked, in: id)
    }
}
