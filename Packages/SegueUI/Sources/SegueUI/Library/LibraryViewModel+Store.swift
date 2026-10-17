import Foundation
import Library

/// Store round trips that only reload afterwards (refresh, rebuild, display toggles).
public extension LibraryViewModel {
    /// Rescans the folder for external edits, then reloads.
    func refresh() async {
        do {
            try await store.refresh()
        } catch {
            errorMessage = UserMessage.describe(error)
        }
        await reload()
    }

    /// Deletes and rebuilds the index from the files on disk, then reloads.
    func rebuildIndex() async {
        do {
            try await store.rebuildIndex()
        } catch {
            errorMessage = "The index could not be rebuilt (\(UserMessage.describe(error))). "
                + "The previous index is still in use."
        }
        await reload()
    }

    /// Writes song `id`'s display toggles (transpose, capo mode, Nashville, diagrams) to its
    /// sidecar; the `.cho` is untouched.
    func updateDisplayPrefs(id: SongID, _ prefs: DisplayPrefs) async throws -> SongRecord {
        let record = try await store.updateDisplayPrefs(id: id, prefs)
        await reload()
        return record
    }
}
