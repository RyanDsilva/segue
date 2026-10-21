import Editing
import Foundation
import Library
import Services
#if os(macOS)
    import AppKit
#endif

/// Opens the section notes sheet, scrolled to one group (nil: the top).
public struct SectionNotesRequest: Identifiable, Hashable, Sendable {
    public let id = UUID()
    public var group: SectionNoteGroup.ID?
    /// The instance of the band that opened the sheet: a new note's default placement
    /// (R144). Nil without a band, or for a label that occurs once.
    public var placement: NotePlacement?
    /// Open with a new note row on `group`, preset to `placement` and focused ("Add Note
    /// to Chorus #2...").
    public var addsNote: Bool
    /// Where the sheet was opened from (analytics, P3-17 section 7).
    public var entry: NoteEntry

    public init(
        group: SectionNoteGroup.ID? = nil,
        placement: NotePlacement? = nil,
        addsNote: Bool = false,
        entry: NoteEntry = .sheet,
    ) {
        self.group = group
        self.placement = placement
        self.addsNote = addsNote
        self.entry = entry
    }
}

/// What the sheet knew when it sent an edit, for the analytics row (P3-17 section 7).
public struct SectionNoteEditContext: Sendable, Hashable {
    public var entry: NoteEntry
    /// The `{chorus}` repeat hint was shown for this edit.
    public var repeatHint: Bool

    public init(entry: NoteEntry, repeatHint: Bool = false) {
        self.entry = entry
        self.repeatHint = repeatHint
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

    /// Opens the sheet on the group showing the section whose header is at `path`, with
    /// that section's instance as a new note's default placement; `addNote` also opens a new
    /// note row on it.
    func showSectionNotes(
        forSectionAt path: BlockPath?,
        entry: NoteEntry = .sheet,
        addNote: Bool = false,
    ) {
        let notes = sectionNotes
        let group = path.flatMap { notes.group(forSectionAt: $0)?.id }
        sectionNotesRequest = SectionNotesRequest(
            group: group,
            placement: path.flatMap { notes.placement(forSectionAt: $0) },
            addsNote: addNote && group != nil,
            entry: entry,
        )
    }

    /// The band context menu's "Add Note to Chorus #2..." title (R145 question 4): the
    /// band's label, and its instance when the label repeats. Nil when the section takes no
    /// notes (a new song's stage notes wait for its first save, but chart notes do not).
    func addNoteTitle(forSectionAt path: BlockPath) -> String? {
        let notes = sectionNotes
        guard let group = notes.group(forSectionAt: path), group.kind == .section,
              group.acceptsChartNotes || canEditStageNotes
        else { return nil }
        guard case let .instance(number) = notes.placement(forSectionAt: path) else {
            return "Add Note to \(group.title)..."
        }
        return "Add Note to \(group.title) #\(number)..."
    }

    /// Stage-only notes live in the sidecar, which a new song has only after its first save.
    var canEditStageNotes: Bool {
        if case .edit = mode {
            return persistCues != nil
        }
        return false
    }

    /// Applies `edit` as one undo step and returns the change (its `resultID` names the note
    /// afterwards). Returns nil (and says why) when it cannot apply.
    @discardableResult
    func editSectionNotes(
        _ edit: SectionNoteEdit,
        context: SectionNoteEditContext = SectionNoteEditContext(entry: .sheet),
    ) -> SectionNoteChange? {
        let change: SectionNoteChange
        do {
            change = try SectionNotes.change(edit, in: snapshot, cues: cues)
        } catch {
            errorMessage = Self.message(for: error)
            services.recordNoteEditFailure(error)
            return nil
        }
        let cuesChange = change.cues != cues
        guard change.source != nil || cuesChange else { return change }
        if cuesChange, !canEditStageNotes {
            errorMessage = "Stage-only notes can be added once the song is saved."
            return nil
        }
        services.recordNoteEdit(change, context: context)
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
        return change
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

extension ServicesHub {
    /// Row 23 for an applied section note edit (text edits and no-ops send nothing).
    func recordNoteEdit(_ change: SectionNoteChange, context: SectionNoteEditContext) {
        guard let outcome = change.outcome else { return }
        record(.notesEdited(NotesEditedSummary(
            action: NoteEditAction(outcome.action),
            kind: outcome.kind == .chart ? .chart : .stage,
            placement: NotePlacementKind(outcome.placement),
            entry: context.entry,
            repeatHint: context.repeatHint,
        )))
    }

    /// Row 16 when an edit named a note the song no longer has.
    func recordNoteEditFailure(_ error: SectionNoteError) {
        if error == .notFound {
            record(.errorOccurred(.sectionNoteGone))
        }
    }
}

private extension NoteEditAction {
    init(_ action: SectionNoteOutcome.Action) {
        self = switch action {
        case .add: .add
        case .move: .move
        case .toggle: .toggle
        case .delete: .delete
        }
    }
}

private extension NotePlacementKind {
    init(_ placement: SectionNoteOutcome.Placement) {
        self = switch placement {
        case .single: .single
        case .every: .every
        case .instance: .instance
        case .repeat: .repeat
        }
    }
}
