import Foundation
import Library

/// Phase 2 (unit D): library metadata editing (tags, proficiency, notes, cues), undoable
/// from Edit > Undo (WS2a 3.9.1, A27).
public extension LibraryViewModel {
    /// Saves song `id`'s tags, proficiency, notes and cues to its sidecar, then reloads so
    /// lists, chips and search see the change. Failures are shown in the error banner. The
    /// change is one undo step ("Edit Tags", "Change Proficiency", "Edit Notes", "Edit
    /// Cues", or "Edit Song Details" when several fields changed).
    @discardableResult
    func updateMetadata(id: SongID, _ metadata: SongMetadata) async -> SongRecord? {
        let before = song(id: id).map { SongMetadata($0.sidecar) }
        guard let record = await writeMetadata(id: id, metadata) else { return nil }
        if let before, before != SongMetadata(record.sidecar) {
            registerMetadataUndo(
                id,
                actionName: Self.metadataActionName(before, SongMetadata(record.sidecar)),
                before: before,
                after: SongMetadata(record.sidecar),
            )
        }
        return record
    }

    /// Changes one part of song `id`'s metadata, starting from what the catalog holds.
    func editMetadata(id: SongID, _ change: (inout SongMetadata) -> Void) async {
        guard let record = song(id: id) else { return }
        var metadata = SongMetadata(record.sidecar)
        change(&metadata)
        guard metadata != SongMetadata(record.sidecar) else { return }
        await updateMetadata(id: id, metadata)
    }

    /// Known tags, most used first (for chips and token parsing).
    var tagNames: [String] {
        tags.map(\.tag)
    }
}

extension LibraryViewModel {
    /// The undo name for a change from `old` to `new`.
    static func metadataActionName(_ old: SongMetadata, _ new: SongMetadata) -> String {
        var names: [String] = []
        if old.tags != new.tags {
            names.append("Edit Tags")
        }
        if old.proficiency != new.proficiency {
            names.append("Change Proficiency")
        }
        if old.notes != new.notes {
            names.append("Edit Notes")
        }
        if old.cues != new.cues {
            names.append("Edit Cues")
        }
        return names.count == 1 ? names[0] : "Edit Song Details"
    }

    private func writeMetadata(id: SongID, _ metadata: SongMetadata) async -> SongRecord? {
        do {
            let record = try await store.updateMetadata(id: id, metadata)
            await reload()
            return record
        } catch {
            pendingErrorCode = UserMessage.code(for: error, else: .saveFailed)
            errorMessage = UserMessage.describe(error)
            await reload()
            return nil
        }
    }

    /// Undo writes `before` back (and reselects the song); its own undo re-applies `after`.
    /// A song gone from the library, or a failed write, drops that song's actions.
    private func registerMetadataUndo(
        _ id: SongID,
        actionName: String,
        before: SongMetadata,
        after: SongMetadata,
    ) {
        guard let manager = undoManager else { return }
        manager.registerUndo(withTarget: metadataTargets.target(for: id)) { [weak self] target in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.registerMetadataUndo(id, actionName: actionName, before: after, after: before)
                let previous = self.metadataWork
                self.metadataWork = Task { @MainActor in
                    await previous?.value
                    guard self.song(id: id) != nil else {
                        self.pendingErrorCode = .other
                        self.errorMessage = "That song is no longer in the library."
                        manager.removeAllActions(withTarget: target)
                        return
                    }
                    guard await self.writeMetadata(id: id, before) != nil else {
                        manager.removeAllActions(withTarget: target)
                        return
                    }
                    if self.editor == nil, self.detail != .song(id) {
                        self.selection = id
                        self.detail = .song(id)
                    }
                }
            }
        }
        manager.setActionName(actionName)
    }
}
