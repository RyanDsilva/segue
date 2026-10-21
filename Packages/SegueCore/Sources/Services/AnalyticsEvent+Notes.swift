import Foundation

// Section note placement analytics (P3-17 section 7, R144): row 23 of the closed vocabulary.
// Enums and booleans only: never note text, section labels, song titles or note IDs.

/// Row 23: `Segue.Notes.edited`, daily per action, kind and placement.
public struct NotesEditedSummary: Sendable, Hashable {
    public var action: NoteEditAction
    /// The note's kind after the edit (before it, for a delete).
    public var kind: NoteKind
    public var placement: NotePlacementKind
    public var entry: NoteEntry
    /// The `{chorus}` repeat hint was shown for this edit.
    public var repeatHint: Bool

    public init(
        action: NoteEditAction,
        kind: NoteKind,
        placement: NotePlacementKind,
        entry: NoteEntry,
        repeatHint: Bool,
    ) {
        self.action = action
        self.kind = kind
        self.placement = placement
        self.entry = entry
        self.repeatHint = repeatHint
    }
}

public enum NoteEditAction: String, Sendable, CaseIterable {
    case add
    case move
    case toggle
    case delete
}

public enum NoteKind: String, Sendable, CaseIterable {
    case chart
    case stage
}

public enum NotePlacementKind: String, Sendable, CaseIterable {
    /// The label occurs once (or lines outside any section).
    case single
    case every
    case instance
    /// An instance that is a `{chorus}` repeat.
    case `repeat`
}

/// Where the edit started.
public enum NoteEntry: String, Sendable, CaseIterable {
    /// The section band's context menu ("Add Note to Chorus #2...", "Section Notes...").
    case bandMenu
    /// The section band's note badge (or its VoiceOver action).
    case badge
    /// The sheet opened from the editor without a band (Song menu, toolbar).
    case sheet
    /// The editor's slash menu Note item.
    case slash
    /// The library detail pane.
    case library
}
