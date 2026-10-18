import Foundation
import Support

/// One undo target per item (a song, a setlist, a gig), so the actions of exactly one item
/// can be dropped with `UndoManager.removeAllActions(withTarget:)` (WS2a 3.9).
@MainActor
final class UndoTargets<ID: Hashable> {
    final class Target {}

    private var targets: [ID: Target] = [:]

    func target(for id: ID) -> Target {
        if let target = targets[id] {
            return target
        }
        let target = Target()
        targets[id] = target
        return target
    }

    /// Drops every undo and redo action of `id`.
    func removeActions(of id: ID, from manager: UndoManager?) {
        guard let target = targets[id] else { return }
        manager?.removeAllActions(withTarget: target)
    }
}

/// Undo for a move to the Trash: Undo puts the items back from the receipt, Redo trashes
/// again (with a new receipt). The store work is async, so each step registers its
/// counterpart synchronously (keeping the undo and redo stacks in order) and does the file
/// work in a task. A step whose file work fails drops the item's remaining actions, so the
/// stacks never offer something that cannot happen.
@MainActor
struct TrashUndo {
    let manager: UndoManager?
    /// The item's undo target (`UndoTargets`).
    let target: AnyObject
    /// "Move to Trash", "Move Setlist to Trash", "Move Gig to Trash".
    let actionName: String
    /// Moves the item to the Trash again (Redo); nil when that failed.
    let trash: @MainActor () async -> TrashReceipt?
    /// Puts the item back from a receipt (Undo); false when that failed.
    let restore: @MainActor (TrashReceipt) async -> Bool

    /// Registers the undo of a delete whose receipt `pending` delivers.
    func register(pending: Task<TrashReceipt?, Never>) {
        guard let manager else { return }
        manager.registerUndo(withTarget: target) { _ in
            MainActor.assumeIsolated { undo(pending: pending, on: manager) }
        }
        manager.setActionName(actionName)
    }

    private func undo(pending: Task<TrashReceipt?, Never>, on manager: UndoManager) {
        // Registered while undoing, so this lands on the redo stack.
        manager.registerUndo(withTarget: target) { _ in
            MainActor.assumeIsolated {
                let again = Task { await trash() }
                register(pending: again)
            }
        }
        manager.setActionName(actionName)
        let target = target
        Task {
            guard let receipt = await pending.value, await restore(receipt) else {
                manager.removeAllActions(withTarget: target)
                return
            }
        }
    }
}
