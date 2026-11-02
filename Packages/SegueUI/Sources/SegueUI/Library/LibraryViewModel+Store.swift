import Foundation
import Library

/// Store round trips that only reload afterwards (refresh, rebuild, display toggles).
public extension LibraryViewModel {
    /// Rescans the folder for external edits, then reloads. A song whose files changed on
    /// disk loses its metadata undo actions (an undo must not overwrite another app's edit).
    func refresh() async {
        let before = Dictionary(catalog.map { ($0.id, $0.revision) }) { first, _ in first }
        do {
            try await store.refresh()
        } catch {
            pendingErrorCode = UserMessage.code(for: error, else: .indexRebuildFailed)
            errorMessage = UserMessage.describe(error)
        }
        await reload()
        for (id, revision) in before where song(id: id)?.revision != revision {
            metadataTargets.removeActions(of: id, from: undoManager)
        }
    }

    /// Deletes and rebuilds the index from the files on disk, then reloads.
    func rebuildIndex() async {
        do {
            try await store.rebuildIndex()
        } catch {
            pendingErrorCode = .indexRebuildFailed
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

    /// Writes song `id`'s stage memory (`LivePrefs`, e.g. its column choice) to its sidecar;
    /// the `.cho` is untouched.
    func updateLivePrefs(id: SongID, _ prefs: LivePrefs) async throws -> SongRecord {
        let record = try await store.updateLivePrefs(id: id, prefs)
        await reload()
        return record
    }
}
