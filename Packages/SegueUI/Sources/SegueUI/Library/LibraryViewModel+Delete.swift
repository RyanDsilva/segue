import Foundation
import Library
import Support

// Delete Song (WS2a 3.3): songs go to the Trash, with Edit > Undo. Whether to ask first
// (only when setlists use the song, A23) is decided by `LibrarySession`, which knows them.

public extension LibraryViewModel {
    /// Moves song `id` to the Trash. Pending edits are saved first: an editor open on the
    /// song is flushed, then closed (B-10), so the trashed file holds the latest text; if
    /// that save fails nothing is trashed and the editor shows why. Selection moves to the
    /// next row (else the previous one). Edit > Undo ("Move to Trash") puts it back.
    func moveSongToTrash(_ id: SongID) async {
        if let editor {
            guard await editor.flush() || editor.mode != .edit(id) else { return }
            if editor.mode == .edit(id) {
                closeEditor()
            }
        }
        let wasShown = detail == .song(id)
        let next = neighbour(of: id)
        let pending = Task { await trashSong(id) }
        guard await pending.value != nil else { return }
        if wasShown, editor == nil {
            selection = next
            detail = next.map(Detail.song) ?? .empty
        }
        TrashUndo(
            manager: undoManager,
            target: trashTargets.target(for: id),
            actionName: "Move to Trash",
            trash: { [weak self] in await self?.trashSong(id) },
            restore: { [weak self] receipt in await self?.restoreSong(receipt) ?? false },
        ).register(pending: pending)
    }

    /// The row after `id` in the list, else the one before it.
    func neighbour(of id: SongID) -> SongID? {
        guard let index = results.firstIndex(where: { $0.id == id }) else { return nil }
        if results.indices.contains(index + 1) {
            return results[index + 1].id
        }
        return index > 0 ? results[index - 1].id : nil
    }
}

extension LibraryViewModel {
    private func trashSong(_ id: SongID) async -> TrashReceipt? {
        let title = song(id: id).map(Self.sortTitle) ?? "The song"
        do {
            let receipt = try await store.deleteSong(id: id)
            // Its metadata edits cannot be undone once it is in the Trash.
            metadataTargets.removeActions(of: id, from: undoManager)
            if !receipt.leftBehind.isEmpty {
                errorMessage = "“\(title)” is in the Trash, but its metadata file could not be "
                    + "moved there and stays in the library folder."
            }
            await reload()
            return receipt
        } catch {
            errorMessage = UserMessage.describe(error)
            await reload()
            return nil
        }
    }

    private func restoreSong(_ receipt: TrashReceipt) async -> Bool {
        do {
            let record = try await store.restoreSong(receipt)
            await reload()
            guard let record else {
                errorMessage = "Could not undo Move to Trash: the song could not be read."
                return false
            }
            if editor == nil {
                selection = record.id
                detail = .song(record.id)
            }
            return true
        } catch {
            errorMessage = "Could not undo Move to Trash. " + UserMessage.describe(error)
            await reload()
            return false
        }
    }
}
