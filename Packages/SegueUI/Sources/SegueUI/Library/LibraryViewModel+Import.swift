import Foundation
import Library
import Services
import Support

// In-app import (WS2a 3.2, R15): File > Import Songs… and drag and drop on the library.

public extension LibraryViewModel {
    /// Whether import is possible now: always with a library open. During a show only
    /// files that are already ChordPro import (R109); the rest wait for the review sheet,
    /// which is off on stage.
    var canImport: Bool {
        true
    }

    /// Imports the files and folders at `urls` (read at once: drop and panel URLs carry a
    /// sandbox extension only for now). Pending edits are saved first. Files that are
    /// already ChordPro import directly; files that need conversion open the review sheet
    /// (P3-4, R96). The first imported song is selected (never during a show); the summary
    /// bar says what happened. Edit > Undo Import moves the imported songs to the Trash;
    /// Redo puts them back.
    func importSongs(_ urls: [URL], method: ImportMethod = .dragDrop) async {
        await importWithReview(urls, method: method)
    }

    /// After an import wrote its songs: reload, the summary bar, analytics, the first song
    /// selected and Edit > Undo Import.
    func finishImport(
        _ summary: ImportSummary,
        files: Int,
        method: ImportMethod,
        nearDuplicate: Bool = false,
    ) async {
        await reload()
        recordImport(summary, files: files, method: method, nearDuplicate: nearDuplicate)
        showImported(summary, bar: true)
    }

    /// Shows what an import (or an accepted paste) wrote: the summary bar when `bar`, the
    /// first song selected, and Edit > Undo Import (one step for all of them).
    func showImported(_ summary: ImportSummary, bar: Bool) {
        if bar {
            importSummary = summary
        }
        guard let first = summary.imported.first else { return }
        registerImportUndo(summary.imported.map(\.id))
        // On stage nothing in the main window moves: no selection change, no editor closed.
        guard !isPerforming else { return }
        navigate { [weak self] in
            self?.selection = first.id
            self?.detail = .song(first.id)
        }
    }

    /// Hides the summary bar.
    func dismissImportSummary() {
        importSummary = nil
    }
}

extension LibraryViewModel {
    /// Undo moves the imported songs to the Trash, Redo restores them (same IDs), each step
    /// registering its counterpart synchronously so the stacks stay in order. The file work
    /// runs in order through `importWork`.
    private func registerImportUndo(_ ids: [SongID]) {
        guard let manager = undoManager else { return }
        importCount += 1
        let target = importTargets.target(for: importCount)
        register(on: manager, target: target, ids: ids)
    }

    private func register(on manager: UndoManager, target: AnyObject, ids: [SongID]) {
        manager.registerUndo(withTarget: target) { [weak self] target in
            MainActor.assumeIsolated {
                guard let self else { return }
                let trashed = self.chainImportWork { await self.trashImported(ids) }
                manager.registerUndo(withTarget: target) { [weak self] target in
                    MainActor.assumeIsolated {
                        guard let self else { return }
                        self.register(on: manager, target: target, ids: ids)
                        _ = self.chainImportWork {
                            guard await self.restoreImported(trashed.value) else {
                                manager.removeAllActions(withTarget: target)
                                return []
                            }
                            return []
                        }
                    }
                }
                manager.setActionName("Import")
            }
        }
        manager.setActionName("Import")
    }

    /// Runs `work` after the import undo work queued before it.
    private func chainImportWork(
        _ work: @escaping @MainActor () async -> [TrashReceipt],
    ) -> Task<[TrashReceipt], Never> {
        let previous = importWork
        let task = Task { @MainActor in
            await previous?.value
            return await work()
        }
        importWork = Task { _ = await task.value }
        return task
    }

    private func trashImported(_ ids: [SongID]) async -> [TrashReceipt] {
        await flushEditor()
        var receipts: [TrashReceipt] = []
        for id in ids {
            do {
                if case .edit(id) = editor?.mode {
                    closeEditor()
                }
                try await receipts.append(store.deleteSong(id: id))
            } catch {
                errorMessage = UserMessage.describe(error)
            }
        }
        importSummary = nil
        await reload()
        return receipts
    }

    private func restoreImported(_ receipts: [TrashReceipt]) async -> Bool {
        var restored = true
        for receipt in receipts {
            do {
                try await store.restoreSong(receipt)
            } catch {
                errorMessage = "Could not redo the import. " + UserMessage.describe(error)
                restored = false
            }
        }
        await reload()
        return restored
    }
}
