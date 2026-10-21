import Editing
import Foundation
import Library
import Services

/// Section notes from the library detail pane (P3-13): one edit writes the song's `.cho`
/// and its sidecar cues together and is one step on Edit > Undo.
extension LibraryViewModel {
    /// The `.cho` and cues one side of a section note edit restores.
    private struct NotesState {
        var source: String
        var cues: [SongCue]
    }

    /// Plans `edit` on song `id` as the catalog holds it and writes it. Failures show in the
    /// error banner; returns the change when it applied (its `resultID` names the note
    /// afterwards), else nil.
    @discardableResult
    func editSectionNotes(
        id: SongID,
        _ edit: SectionNoteEdit,
        context: SectionNoteEditContext = SectionNoteEditContext(entry: .library),
    ) async -> SectionNoteChange? {
        guard let record = song(id: id), !record.isReadOnly else { return nil }
        let change: SectionNoteChange
        do {
            change = try SectionNotes.change(
                edit,
                in: SourceSnapshot(text: record.source),
                cues: record.sidecar.cues,
            )
        } catch {
            errorMessage = SongEditorViewModel.message(for: error)
            services.recordNoteEditFailure(error)
            return nil
        }
        let before = NotesState(source: record.source, cues: record.sidecar.cues)
        let after = NotesState(
            source: change.source.map { record.source.applying($0.edits) } ?? record.source,
            cues: change.cues,
        )
        guard after.source != before.source || after.cues != before.cues else { return change }
        guard await writeNotes(id: id, after, over: record) else { return nil }
        registerNotesUndo(id, actionName: change.actionName, before: before, after: after)
        services.recordNoteEdit(change, context: context)
        return change
    }

    private func writeNotes(id: SongID, _ state: NotesState, over record: SongRecord) async
        -> Bool
    {
        do {
            let saved = try await store.updateSectionNotes(
                id: id,
                source: state.source == record.source ? nil : state.source,
                cues: state.cues,
                basedOn: record.revision,
            )
            await applySaved(saved)
            return true
        } catch {
            errorMessage = UserMessage.describe(error)
            await reload()
            return false
        }
    }

    /// Undo writes `before` back over the song as the catalog then holds it (and reselects
    /// the song); its own undo re-applies `after`.
    private func registerNotesUndo(
        _ id: SongID,
        actionName: String,
        before: NotesState,
        after: NotesState,
    ) {
        guard let manager = undoManager else { return }
        manager.registerUndo(withTarget: metadataTargets.target(for: id)) { [weak self] target in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.registerNotesUndo(id, actionName: actionName, before: after, after: before)
                let previous = self.metadataWork
                self.metadataWork = Task { @MainActor in
                    await previous?.value
                    guard let record = self.song(id: id) else {
                        self.errorMessage = "That song is no longer in the library."
                        manager.removeAllActions(withTarget: target)
                        return
                    }
                    guard await self.writeNotes(id: id, before, over: record) else {
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
