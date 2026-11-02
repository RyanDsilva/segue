import Foundation
import Library
import Services
import Setlists
import Support

// Setlist builder undo and redo (WS2a 3.9, A27): whole-value snapshots written back through
// `SetlistStore.replace`, one target per setlist, and no undo over another app's edit (B-16).

public extension SetlistsViewModel {
    /// Re-reads every setlist file (Library > Refresh, app activation). A setlist that
    /// changed on disk since Segue last loaded or wrote it, or that disappeared, loses its
    /// undo actions, so an undo can never overwrite someone else's edit.
    func reloadFromDisk() async {
        let before = known
        do {
            loadIssues = try await store.reloadFromDisk()
        } catch {
            pendingErrorCode = UserMessage.code(for: error, else: .saveFailed)
            errorMessage = UserMessage.describe(error)
        }
        let current = await store.all()
        for (id, value) in before where current.first(where: { $0.id == id }) != value {
            editTargets.removeActions(of: id, from: undoManager)
        }
        await reload()
    }

    /// Show end "Save to Setlist" (`replaceEntries`), undoable afterwards as "Save Show Order".
    func saveShowOrder(_ entries: [SetlistEntry], in id: SetlistID) async throws {
        let result: Result<Void, any Error> = await serialized { [self] in
            let before = await store.setlist(id: id)
            do {
                let updated = try await store.replaceEntries(entries, in: id)
                await reload()
                if let before {
                    registerSnapshotUndo(
                        id,
                        actionName: "Save Show Order",
                        before: before,
                        after: updated,
                    )
                }
                return .success(())
            } catch {
                return .failure(error)
            }
        }
        try result.get()
    }
}

extension SetlistsViewModel {
    /// Registers Undo (write `before` back) whose own undo is the Redo (write `after`).
    func registerSnapshotUndo(
        _ id: SetlistID,
        actionName: String,
        before: Setlist,
        after: Setlist,
    ) {
        guard let manager = undoManager else { return }
        let target = editTargets.target(for: id)
        manager.registerUndo(withTarget: target) { [weak self] target in
            MainActor.assumeIsolated {
                guard let self else { return }
                if manager.isUndoing {
                    self.services.record(.featureUsed(.undoInBuilder, .builder))
                }
                // Registered while undoing (or redoing), so it lands on the other stack.
                self.registerSnapshotUndo(id, actionName: actionName, before: after, after: before)
                self.chain {
                    await self.write(before, target: target)
                }
            }
        }
        manager.setActionName(actionName)
    }

    /// New Setlist and Duplicate: Undo moves the new setlist to the Trash, Redo restores it.
    func registerCreationUndo(_ id: SetlistID, actionName: String) {
        guard let manager = undoManager else { return }
        let target = editTargets.target(for: id)
        manager.registerUndo(withTarget: target) { [weak self] target in
            MainActor.assumeIsolated {
                guard let self else { return }
                let box = ReceiptBox()
                manager.registerUndo(withTarget: target) { [weak self] target in
                    MainActor.assumeIsolated {
                        guard let self else { return }
                        self.registerCreationUndo(id, actionName: actionName)
                        self.chain {
                            guard let receipt = box.receipt,
                                  await (try? self.store.restore(receipt)) != nil
                            else {
                                manager.removeAllActions(withTarget: target)
                                return
                            }
                            await self.reload()
                            self.selection = id
                        }
                    }
                }
                manager.setActionName(actionName)
                self.chain {
                    do {
                        box.receipt = try await self.store.delete(id)
                    } catch {
                        self.pendingErrorCode = UserMessage.code(for: error, else: .saveFailed)
                        self.errorMessage = UserMessage.describe(error)
                        manager.removeAllActions(withTarget: target)
                    }
                    await self.reload()
                }
            }
        }
        manager.setActionName(actionName)
    }

    /// Writes a snapshot; on failure shows the banner and drops the setlist's actions.
    private func write(_ snapshot: Setlist, target: AnyObject) async {
        do {
            try await store.replace(snapshot)
            await reload()
            selection = snapshot.id
        } catch {
            pendingErrorCode = UserMessage.code(for: error, else: .saveFailed)
            errorMessage = "Could not undo the setlist change. " + UserMessage.describe(error)
            undoManager?.removeAllActions(withTarget: target)
            await reload()
        }
    }

    /// Queues `work` (an undo or redo write) after every setlist write queued before it.
    private func chain(_ work: @escaping @MainActor () async -> Void) {
        let previous = writeWork
        writeWork = Task { @MainActor in
            await previous?.value
            await work()
        }
    }

    /// Runs `work` on the write queue after every setlist write queued before it, and
    /// returns its result.
    func serialized<T: Sendable>(_ work: @escaping @MainActor () async -> T) async -> T {
        let previous = writeWork
        let task = Task { @MainActor in
            await previous?.value
            return await work()
        }
        writeWork = Task { @MainActor in
            _ = await task.value
        }
        return await task.value
    }
}

/// The receipt of a trash done in an undo step, read by its redo.
@MainActor
final class ReceiptBox {
    var receipt: TrashReceipt?
}
