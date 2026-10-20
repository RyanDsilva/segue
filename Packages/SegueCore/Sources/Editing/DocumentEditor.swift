// Owner: unit C (Editing). Frozen interface: docs/phases/1-interfaces.md.

import ChordPro
import Diagrams
import Foundation

/// A tree-level edit, as visual mode (and editor commands) express it.
///
/// Chord text in operations is source text (what goes between the brackets). Visual mode
/// converts what the user typed in the display key with `DisplayTransform.sourceChord`.
public enum EditOperation: Sendable, Hashable {
    /// Adds `[chord]` above the character at `at`. A chord already at that offset is
    /// replaced (no stacking); an authored stack there (`[A][B]text`) becomes the one chord.
    case insertChord(String, at: LyricPosition)
    /// Changes the text of one chord.
    case replaceChord(ChordRef, with: String)
    /// Moves a chord to another offset, same or another lyric line (drag).
    case moveChord(ChordRef, to: LyricPosition)
    /// Copies a chord to another offset (Option-drag).
    case duplicateChord(ChordRef, to: LyricPosition)
    case deleteChord(ChordRef)
    /// Replaces `range` (Character offsets into the line's lyric text) with `replacement`.
    /// Chords stay on their characters; chords inside a removed range move to its start.
    /// Throws `notLyricText` when the line would stop being the same lyric line.
    case editLyrics(BlockPath, range: Range<Int>, replacement: String)
    /// Splits a lyric line in two at a position (Return in visual mode); chords at or after
    /// the position go to the new line.
    case splitLine(at: LyricPosition)
    /// Joins a lyric line onto the previous lyric line (Backspace at line start).
    case joinWithPrevious(BlockPath)
    /// Sets or clears the label of the section whose header is at `path`
    /// (`{start_of_verse: Verse 2}`), keeping the directive's spelling.
    case setSectionLabel(BlockPath, label: String?)
    /// Sets the first metadata directive `name` (`key`, `capo`, `tempo`, ...; `meta` is not
    /// accepted here). `nil` removes it. When absent, it is inserted after the last leading
    /// metadata directive (or at the top).
    case setDirective(name: String, value: String?)
    /// Sets `{meta: <name> <value>}` (e.g. `tuning`); `nil` removes it.
    case setMeta(name: String, value: String?)
    /// Replaces every `{define}` with the same name by one canonical define, or inserts it
    /// after the leading metadata directives.
    case setDefine(ChordDefinition)
    case removeDefine(name: String)

    // MARK: Sections (P3-11, the section band; the slash menu's wrap uses `wrapSection`)

    /// Wraps the top-level blocks `first` ... `last` in `{start_of_<kind>: label}` ...
    /// `{end_of_<kind>}`. Throws `crossesSection` when the range is inside or crosses a
    /// section. `SectionLabels.next(for:in:)` proposes the numbered label.
    case wrapSection(first: BlockPath, last: BlockPath, kind: SectionKind, label: String?)
    /// `wrapSection` labelled by the numbering rule (`SectionLabels.proposal`) from the
    /// wrapped lyrics, numbering existing same-kind sections in the same step when this is
    /// the second distinct one ("Chorus" -> "Chorus 1", new "Chorus 2").
    case createSection(first: BlockPath, last: BlockPath, kind: SectionKind)
    /// `setSectionKind` labelled by the numbering rule (the band's V / C / B / I on exactly
    /// one section); no change when the section already is `kind`.
    case changeSectionKind(BlockPath, to: SectionKind)
    /// Re-spells the section's start (and end) directive as `kind` with `label`.
    case setSectionKind(BlockPath, kind: SectionKind, label: String?)
    /// Moves the section's top or bottom edge so `toLine` becomes its first (top) or last
    /// (bottom) line, clamped at the neighbouring sections and the leading metadata.
    case moveSectionEdge(BlockPath, edge: SectionEdge, toLine: BlockPath)
    /// Removes the section's start and end directives; its lines stay.
    case unwrapSection(BlockPath)
    /// Ends the section before the item `atLine` and starts a new one of the same kind
    /// there (numbered when the section has a label).
    case splitSection(BlockPath, atLine: BlockPath)
    /// Joins `second` (the next section after `first`) onto `first`. With `kind == nil`
    /// the two must be the same kind (else `sectionKindsDiffer`, so the caller can ask);
    /// otherwise the merged section becomes `kind`. Keeps `first`'s label.
    case mergeSections(first: BlockPath, second: BlockPath, kind: SectionKind?)
}

/// Which edge of a section band moves.
public enum SectionEdge: Sendable, Hashable {
    case top
    case bottom
}

public enum EditError: Error, Sendable, Hashable {
    /// The path does not exist in this snapshot.
    case invalidPath(BlockPath)
    /// The path exists but is not what the operation needs (e.g. not a lyric line).
    case wrongBlockKind(BlockPath)
    case invalidChord(ChordRef)
    case offsetOutOfRange(LyricPosition)
    /// Tab/grid sections are pass-through: never edited visually.
    case readOnlyBlock(BlockPath)
    /// Empty or bracket-containing chord text.
    case invalidChordText(String)
    /// A lyric edit or split that would turn the line into something else: a `#` comment,
    /// a `{directive}`, or a new `[chord]` typed as text.
    case notLyricText(BlockPath)
    /// A section wrap whose lines are inside or span an existing section (sections do not
    /// nest); the path is the section in the way.
    case crossesSection(BlockPath)
    /// A merge of two different kinds without a chosen kind.
    case sectionKindsDiffer(BlockPath, BlockPath)
}

/// Plans tree operations as minimal text edits (phase 1 spec, "Sync between modes").
///
/// Invariant: `snapshot.text.applying(change.edits)` parses to the tree the operation
/// describes, and every byte outside the touched lines is unchanged.
public enum DocumentEditor {
    public static func change(
        for operation: EditOperation,
        in snapshot: SourceSnapshot,
    ) throws(EditError) -> SourceChange {
        var planner = EditPlanner(snapshot: snapshot)
        let name: String = if let lyric = try planLyricOperation(operation, with: &planner) {
            lyric
        } else if let section = try planSectionOperation(operation, with: &planner) {
            section
        } else {
            try planDirectiveOperation(operation, with: &planner)
        }
        return planner.change(actionName: name)
    }

    /// Chord and lyric operations; `nil` for the directive ones.
    private static func planLyricOperation(
        _ operation: EditOperation,
        with planner: inout EditPlanner,
    ) throws(EditError) -> String? {
        switch operation {
        case let .insertChord(chord, position):
            try planner.insertChord(chord, at: position)
            return "Add Chord"
        case let .replaceChord(ref, chord):
            try planner.replaceChord(ref, with: chord)
            return "Change Chord"
        case let .moveChord(ref, position):
            try planner.moveChord(ref, to: position, keepingOriginal: false)
            return "Move Chord"
        case let .duplicateChord(ref, position):
            try planner.moveChord(ref, to: position, keepingOriginal: true)
            return "Duplicate Chord"
        case let .deleteChord(ref):
            try planner.deleteChord(ref)
            return "Delete Chord"
        case let .editLyrics(path, range, replacement):
            try planner.editLyrics(path, range: range, replacement: replacement)
            return "Edit Lyrics"
        case let .splitLine(position):
            try planner.splitLine(at: position)
            return "Split Line"
        case let .joinWithPrevious(path):
            try planner.joinWithPrevious(path)
            return "Join Lines"
        default:
            return nil
        }
    }

    /// Section label, directive, meta and define operations.
    private static func planDirectiveOperation(
        _ operation: EditOperation,
        with planner: inout EditPlanner,
    ) throws(EditError) -> String {
        switch operation {
        case let .setSectionLabel(path, label):
            try planner.setSectionLabel(path, label: label)
            return "Rename Section"
        case let .setDirective(directive, value):
            let name = DirectiveLine.canonicalName(directive)
            planner.setDirective(name: name, value: value)
            // `{duration}` is the song's length everywhere the UI names it (R80).
            if name == "duration" {
                return value == nil ? "Clear Length" : "Set Length"
            }
            return "Set \(directive.capitalized)"
        case let .setMeta(meta, value):
            planner.setMeta(name: meta, value: value)
            return "Set \(meta.capitalized)"
        case let .setDefine(definition):
            planner.setDefine(definition)
            return "Set Chord Shape"
        case let .removeDefine(define):
            planner.removeDefine(name: define)
            return "Remove Chord Shape"
        case .changeSectionKind, .createSection, .deleteChord, .duplicateChord, .editLyrics,
             .insertChord, .joinWithPrevious, .mergeSections, .moveChord, .moveSectionEdge,
             .replaceChord, .setSectionKind,
             .splitLine, .splitSection, .unwrapSection, .wrapSection:
            return ""
        }
    }

    /// Section band operations; `nil` for every other operation.
    private static func planSectionOperation(
        _ operation: EditOperation,
        with planner: inout EditPlanner,
    ) throws(EditError) -> String? {
        switch operation {
        case let .wrapSection(first, last, kind, label):
            try planner.wrapSection(first: first, last: last, kind: kind, label: label)
            return "New Section"
        case let .createSection(first, last, kind):
            try planner.createSection(first: first, last: last, kind: kind)
            return "New Section"
        case let .changeSectionKind(path, kind):
            try planner.changeSectionKind(path, to: kind)
            return "Change Section"
        case let .setSectionKind(path, kind, label):
            try planner.setSectionKind(path, kind: kind, label: label)
            return "Change Section"
        case let .moveSectionEdge(path, edge, line):
            try planner.moveSectionEdge(path, edge: edge, toLine: line)
            return "Resize Section"
        case let .unwrapSection(path):
            try planner.unwrapSection(path)
            return "Remove Section"
        case let .splitSection(path, line):
            try planner.splitSection(path, atLine: line)
            return "Split Section"
        case let .mergeSections(first, second, kind):
            try planner.mergeSections(first: first, second: second, kind: kind)
            return "Merge Sections"
        default:
            return nil
        }
    }
}
