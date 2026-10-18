import Foundation
import Library
import Services
import Support

// In-app import (WS2a 3.2, R15): File > Import Songs… and drag and drop on the library.

public extension LibraryViewModel {
    /// Whether import is possible now (a library is open and no show is on stage).
    var canImport: Bool {
        !isPerforming
    }

    /// Imports the files and folders at `urls` (read at once: drop and panel URLs carry a
    /// sandbox extension only for now). Pending edits are saved first. The first imported
    /// song is selected; the summary bar says what happened. Edit > Undo Import moves the
    /// imported songs to the Trash; Redo puts them back.
    func importSongs(_ urls: [URL], method: ImportMethod = .dragDrop) async {
        guard canImport, !urls.isEmpty else { return }
        await flushEditor()
        let summary: ImportSummary
        do {
            summary = try await store.importSongs(urls)
        } catch {
            errorMessage = UserMessage.describe(error)
            services.record(.errorOccurred(.importFailed))
            return
        }
        await reload()
        importSummary = summary
        recordImport(summary, files: urls.count, method: method)
        guard let first = summary.imported.first else { return }
        navigate { [weak self] in
            self?.selection = first.id
            self?.detail = .song(first.id)
        }
        registerImportUndo(summary.imported.map(\.id))
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
