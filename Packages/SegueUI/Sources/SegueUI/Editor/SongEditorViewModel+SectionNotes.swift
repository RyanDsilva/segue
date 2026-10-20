import Editing
import Foundation
import Library
#if os(macOS)
    import AppKit
#endif

/// Opens the section notes sheet, scrolled to one group (nil: the top).
public struct SectionNotesRequest: Identifiable, Hashable, Sendable {
    public let id = UUID()
    public var group: SectionNoteGroup.ID?

    public init(group: SectionNoteGroup.ID? = nil) {
        self.group = group
    }
}

/// Section notes in the open editor (P3-13): chart notes edit the source through the
/// editor's own undo stack, stage-only notes the sidecar cues; a toggle that moves a note
/// between them is one undo step on that stack, and autosave writes the source as usual.
extension SongEditorViewModel {
    /// The song's notes as the editor holds it now.
    var sectionNotes: SectionNotes {
        SectionNotes(document: snapshot.document, cues: cues)
    }

    /// The section band's badge count for the section whose header is at `path`.
    func sectionNoteCount(forSectionAt path: BlockPath) -> Int {
        guard let sections = canvasModel?.sections ?? renderModel?.sections else { return 0 }
        return SectionNotes(sections: sections, cues: cues).count(forSectionAt: path)
    }

    /// Opens the sheet on the group showing the section whose header is at `path`.
    func showSectionNotes(forSectionAt path: BlockPath?) {
        sectionNotesRequest = SectionNotesRequest(
            group: path.flatMap { sectionNotes.group(forSectionAt: $0)?.id },
        )
    }

    /// Stage-only notes live in the sidecar, which a new song has only after its first save.
    var canEditStageNotes: Bool {
        if case .edit = mode {
            return persistCues != nil
        }
        return false
    }

    /// Applies `edit` as one undo step. Returns false (and says why) when it cannot apply.
    @discardableResult
    func editSectionNotes(_ edit: SectionNoteEdit) -> Bool {
        let change: SectionNoteChange
        do {
            change = try SectionNotes.change(edit, in: snapshot, cues: cues)
        } catch {
            errorMessage = Self.message(for: error)
            return false
        }
        let cuesChange = change.cues != cues
        guard change.source != nil || cuesChange else { return true }
        if cuesChange, !canEditStageNotes {
            errorMessage = "Stage-only notes can be added once the song is saved."
            return false
        }
        #if os(macOS)
            let manager = sourceEditor.undoManager
            manager.beginUndoGrouping()
            if let source = change.source {
                apply(source)
            }
            if cuesChange {
                setCues(change.cues)
            }
            manager.setActionName(change.actionName)
            manager.endUndoGrouping()
        #else
            if let source = change.source {
                apply(source)
            }
            if cuesChange {
                setCues(change.cues)
            }
        #endif
        return true
    }

    /// Replaces the cues, registers their undo on the editor's stack and writes the sidecar.
    private func setCues(_ new: [SongCue]) {
        let old = cues
        cues = new
        #if os(macOS)
            sourceEditor.undoManager.registerUndo(withTarget: self) { model in
                MainActor.assumeIsolated { model.setCues(old) }
            }
            visualController?.redrawOverlay()
        #endif
        guard case let .edit(id) = mode, let persistCues else { return }
        let previous = cuesTask
        cuesTask = Task { @MainActor [weak self] in
            await previous?.value
            do {
                _ = try await persistCues(id, new)
            } catch {
                self?.errorMessage = UserMessage.describe(error)
            }
        }
    }

    static func message(for error: SectionNoteError) -> String {
        switch error {
        case .notFound:
            "That note is no longer in the song."
        case .noAnchor:
            "Stage-only notes pin to a named section, and chart notes need a written-out section."
        case .invalidText:
            "A note needs some text on one line."
        case .edit:
            "That note could not be changed."
        }
    }
}
