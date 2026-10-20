// P3-13: accessibility identifiers of the section notes sheet and the library's notes rows.
// Mirror new IDs in the UITests target (it cannot import SegueUI).

public extension AccessibilityID {
    /// "Section Notes..." in the library detail pane.
    static let sectionNotesOpen = "segue.sectionNotes.open"
    /// One note in the library detail pane's summary.
    static let sectionNotesSummary = "segue.sectionNotes.summary"
    static let sectionNotesSheet = "segue.sectionNotes.sheet"
    static let sectionNotesDone = "segue.sectionNotes.done"
    /// A note's text field (existing or new).
    static let sectionNoteText = "segue.sectionNotes.note.text"
    /// A note's "Show on stage only" checkbox.
    static let sectionNoteStageOnly = "segue.sectionNotes.note.stageOnly"
    static let sectionNoteOccurrence = "segue.sectionNotes.note.occurrence"
    static let sectionNoteMove = "segue.sectionNotes.note.move"
    static let sectionNoteDelete = "segue.sectionNotes.note.delete"

    /// A group's heading, by its label ("segue.sectionNotes.group.chorus").
    static func sectionNotesGroup(_ title: String) -> String {
        "segue.sectionNotes.group.\(slug(title))"
    }

    /// A group's "Add Note" button.
    static func sectionNotesAdd(_ title: String) -> String {
        "segue.sectionNotes.add.\(slug(title))"
    }

    private static func slug(_ title: String) -> String {
        title.lowercased().split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            .joined(separator: "-")
    }
}
