// Owner: P3-13, P3-17. Section notes (R87, R106): one concept over two stores. A chart note
// is a `{comment}` line in the `.cho` (portable, printed, shown everywhere); a stage-only
// note is a sidecar cue (`SongCue`, shown as a callout in live mode only). "Show on stage
// only" moves a note between them as one edit. Lyrics are never touched.
//
// P3-17 (R144, R145): every note has a stable `SectionNoteID` (a stage note its persisted
// `CueID`; a chart note an ID derived on read from its section, text and order), and a
// `NotePlacement` (every time, or one instance of its label, `{chorus}` repeats included).
// An every-time chart note on a label written out several times is one `{comment}` copy
// per written-out instance, read back as one linked note.

import ChordPro
import Editing
import Foundation

/// Where a note shows, for a label that occurs more than once (R144).
public enum NotePlacement: Sendable, Hashable {
    /// Every occurrence of the label.
    case everyTime
    /// One occurrence, 1-based, numbered as `Anchors` numbers them: written-out sections and
    /// `{chorus}` repeats share one sequence per label.
    case instance(Int)
}

/// A chart note's identity, derived on every read and never stored (R145 question 1 =
/// option I). Stable across edits that leave its section, its occurrence and its text alone.
public struct ChartNoteID: Sendable, Hashable {
    public enum Anchor: Sendable, Hashable {
        /// One written-out instance of a label (label key, 1-based occurrence).
        case instance(label: String, occurrence: Int)
        /// Copies in every written-out instance of a label, read as one note.
        case everyTime(label: String)
        /// A run of lines outside any section (its first render section).
        case loose(Int)
    }

    public var anchor: Anchor
    /// 1-based, among notes with the same text in the same section (or loose run).
    public var ordinal: Int
    public var text: String

    public init(anchor: Anchor, ordinal: Int, text: String) {
        self.anchor = anchor
        self.ordinal = ordinal
        self.text = text
    }
}

/// A section note's identity (R144): what the sheet keys rows, drafts and focus by, and what
/// every `SectionNoteEdit` names. Resolved against the song when an edit is planned, so a
/// queued edit never lands on another note.
public enum SectionNoteID: Sendable, Hashable {
    case stage(CueID)
    case chart(ChartNoteID)
}

/// One note on a section, read from either store.
public struct SectionNote: Sendable, Hashable, Identifiable {
    /// Where a note's line or cue is, in the song as it was read.
    public enum Source: Sendable, Hashable {
        /// The `{comment}` line at this path.
        case chart(BlockPath)
        /// The sidecar cue at this index in `Sidecar.cues`.
        case stage(Int)
    }

    public var id: SectionNoteID
    /// One source; a linked every-time chart note has one per copy, in song order.
    public var sources: [Source]
    public var text: String
    /// Where it shows; nil when the label occurs once, and for lines outside any section.
    public var placement: NotePlacement?
    /// The written-out instances a chart note's copies are in ("in #1, #2, #3"); the one
    /// instance for a chart note on one instance; empty for stage notes and loose lines.
    public var instances: [Int]
    /// A stage note on one instance whose section no longer matches the fingerprint it was
    /// placed with, and which could not be re-anchored to exactly one other instance: the
    /// sheet shows a quiet "Check placement" mark (R145 question 5).
    public var needsPlacementCheck: Bool

    public init(
        id: SectionNoteID,
        sources: [Source],
        text: String,
        placement: NotePlacement? = nil,
        instances: [Int] = [],
        needsPlacementCheck: Bool = false,
    ) {
        self.id = id
        self.sources = sources
        self.text = text
        self.placement = placement
        self.instances = instances
        self.needsPlacementCheck = needsPlacementCheck
    }

    /// True for sidecar cues: shown in live mode only.
    public var isStageOnly: Bool {
        if case .stage = id {
            return true
        }
        return false
    }

    /// True for an every-time chart note kept as one copy per written-out instance.
    public var isLinked: Bool {
        sources.count > 1
    }

    /// The one instance the note is on, if any.
    public var occurrence: Int? {
        if case let .instance(number) = placement {
            return number
        }
        return nil
    }
}

/// One occurrence of a label in the song: a written-out section or a `{chorus}` repeat.
public struct NoteInstance: Sendable, Hashable, Identifiable {
    /// 1-based, in the label's sequence.
    public var occurrence: Int
    public var isRepeat: Bool
    /// The section header (nil for a repeat).
    public var header: BlockPath?
    /// Where a chart note for this instance goes: the section's own header; for a repeat,
    /// the header of the written-out chorus it repeats (`repeatOf` when that has this label).
    public var chartTarget: BlockPath?
    /// For a repeat: the occurrence of the same label it repeats, if it repeats one.
    public var repeatOf: Int?
    /// The content fingerprint (`SongSections.fingerprint`, "repeat" for a repeat).
    public var fingerprint: String

    public var id: Int {
        occurrence
    }

    /// A chart note can sit here (a `{comment}` line cannot sit inside a `{chorus}` line).
    public var acceptsChartNotes: Bool {
        !isRepeat && chartTarget != nil
    }
}

/// The notes of one section label ("Chorus" covers every chorus), of a run of lines outside
/// any section, or of a label the song no longer has (orphaned cues, kept as phase 2 does).
public struct SectionNoteGroup: Sendable, Hashable, Identifiable {
    public enum Kind: Sendable, Hashable {
        /// A labelled section (or `{chorus}` repeat) of the song.
        case section
        /// Lines outside any section; notes here are chart notes only (a cue needs a label).
        case loose
        /// Cues whose label (or occurrence) the song no longer has.
        case orphaned
    }

    /// "section:<label>", "loose:<first render section>" or "orphaned:<label>".
    public var id: String
    public var kind: Kind
    /// The heading: the label as the song spells it, "Before the first section", "After
    /// <label>", or the orphaned cue's label.
    public var title: String
    /// The label stage notes pin to; nil for loose lines.
    public var label: String?
    /// How many times the label occurs in the song (repeats included).
    public var occurrences: Int
    /// The header of the first written-out section with this label (nil when there is
    /// none: a label only `{chorus}` repeats use).
    public var chartTarget: BlockPath?
    /// The section headers in this group, for the section band's badge.
    public var headers: [BlockPath]
    /// Every occurrence of the label, in song order (empty for loose and orphaned groups).
    public var instances: [NoteInstance]
    /// Ordered by placement (every time, then #1, #2, ...), chart notes in file order before
    /// stage notes in sidecar order within one placement.
    public var notes: [SectionNote]

    /// Chart notes can be added here.
    public var acceptsChartNotes: Bool {
        chartTarget != nil
    }

    /// Stage-only notes can be added here.
    public var acceptsStageNotes: Bool {
        kind == .section
    }

    /// The label occurs more than once, so notes carry a placement and the sheet a picker.
    public var hasPlacements: Bool {
        kind == .section && occurrences > 1
    }

    /// The occurrences that are written out (where every-time chart note copies go).
    public var writtenOut: [NoteInstance] {
        instances.filter(\.acceptsChartNotes)
    }

    public func instance(_ occurrence: Int) -> NoteInstance? {
        instances.first { $0.occurrence == occurrence }
    }

    /// The placement a new note gets with no band context (R145 question 3 = Every time);
    /// nil when the label occurs once.
    public var defaultPlacement: NotePlacement? {
        hasPlacements ? .everyTime : nil
    }
}

/// Why a section note edit cannot apply.
public enum SectionNoteError: Error, Sendable, Equatable {
    /// The note or group is not in this song any more.
    case notFound
    /// A stage-only note needs a section label; a chart note needs a written-out section.
    case noAnchor
    /// The text is empty or would not read back as one `{comment}`.
    case invalidText
    case edit(EditError)
}

/// What a planned edit did, for the closed analytics vocabulary (P3-17 section 7): no text,
/// labels or IDs. Nil on `SectionNoteChange` for text edits and no-ops.
public struct SectionNoteOutcome: Sendable, Hashable {
    public enum Action: String, Sendable, Hashable {
        case add
        case move
        case toggle
        case delete
    }

    public enum Kind: String, Sendable, Hashable {
        case chart
        case stage
    }

    public enum Placement: String, Sendable, Hashable {
        /// The label occurs once (or lines outside any section).
        case single
        case every
        case instance
        /// An instance that is a `{chorus}` repeat.
        case `repeat`
    }

    public var action: Action
    /// After the edit (before it, for a delete).
    public var kind: Kind
    public var placement: Placement

    public init(action: Action, kind: Kind, placement: Placement) {
        self.action = action
        self.kind = kind
        self.placement = placement
    }
}

/// A planned section note edit: the `.cho` change (nil when only cues change) and the
/// sidecar cues after it. The host applies both as one undoable step.
public struct SectionNoteChange: Sendable, Equatable {
    public var source: SourceChange?
    public var cues: [SongCue]
    public var actionName: String
    /// The note's ID after the edit: a new note's, a toggled or moved note's new one, a chart
    /// note's after its text changed. Nil for a delete. The sheet re-keys drafts and focus
    /// from it, so focus never jumps to another row.
    public var resultID: SectionNoteID?
    public var outcome: SectionNoteOutcome?

    public init(
        source: SourceChange?,
        cues: [SongCue],
        actionName: String,
        resultID: SectionNoteID? = nil,
        outcome: SectionNoteOutcome? = nil,
    ) {
        self.source = source
        self.cues = cues
        self.actionName = actionName
        self.resultID = resultID
        self.outcome = outcome
    }
}

/// One section note edit. Every case names notes by ID, resolved when the edit is planned.
public enum SectionNoteEdit: Sendable, Hashable {
    case setText(SectionNoteID, String)
    /// The "Show on stage only" toggle: moves the note between the `.cho` and the sidecar.
    case setStageOnly(SectionNoteID, Bool)
    /// Moves a note to another placement on its label ("Move Note"). A chart note moved to
    /// a `{chorus}` repeat becomes a stage note on it (R144).
    case place(SectionNoteID, NotePlacement)
    /// Re-pins a stage note to another label and occurrence (nil = every one): the
    /// orphaned cue's "Move to".
    case pin(SectionNoteID, section: String, occurrence: Int?)
    case delete(SectionNoteID)
    /// A new note; nil placement = the group's default (Every time, or implicit).
    case add(group: SectionNoteGroup.ID, text: String, stageOnly: Bool, placement: NotePlacement?)
}

/// Every section note of a song, grouped by section in song order, orphaned cues last.
public struct SectionNotes: Sendable, Equatable {
    public private(set) var groups: [SectionNoteGroup]
    /// Section header -> chart notes in that section plus cues pinned to it.
    public private(set) var counts: [BlockPath: Int]

    /// The notes of `document` (rendered with default options) and its sidecar `cues`.
    public init(document: SongDocument, cues: [SongCue]) {
        self.init(
            sections: RenderModel(document: document, options: DisplayOptions()).sections,
            cues: cues,
        )
    }

    public init(sections: [RenderSection], cues: [SongCue]) {
        let built = SectionNotesBuilder(sections: sections, cues: cues)
        groups = built.groups
        counts = built.counts
    }

    public var isEmpty: Bool {
        groups.allSatisfy(\.notes.isEmpty)
    }

    /// All notes in display order.
    public var all: [SectionNote] {
        groups.flatMap(\.notes)
    }

    /// The badge count for the section whose header is at `header`.
    public func count(forSectionAt header: BlockPath) -> Int {
        counts[header] ?? 0
    }

    /// The group showing the section whose header is at `header`.
    public func group(forSectionAt header: BlockPath) -> SectionNoteGroup? {
        groups.first { $0.headers.contains(header) }
    }

    /// The instance of the section whose header is at `header`: the placement a note added
    /// from that section's band defaults to. Nil when its label occurs once.
    public func placement(forSectionAt header: BlockPath) -> NotePlacement? {
        guard let group = group(forSectionAt: header), group.hasPlacements,
              let instance = group.instances.first(where: { $0.header == header })
        else { return nil }
        return .instance(instance.occurrence)
    }

    public func group(id: SectionNoteGroup.ID) -> SectionNoteGroup? {
        groups.first { $0.id == id }
    }

    /// The group a note is in.
    public func group(of id: SectionNoteID) -> SectionNoteGroup? {
        groups.first { group in group.notes.contains { $0.id == id } }
    }

    public func note(_ id: SectionNoteID) -> SectionNote? {
        all.first { $0.id == id }
    }

    /// The note holding the `{comment}` line at `path` or the cue at `index`.
    public func note(holding source: SectionNote.Source) -> SectionNote? {
        all.first { $0.sources.contains(source) }
    }

    // MARK: Anchoring (shared with live layout)

    /// The label a section shows in the gutter and cues pin to: its own label, else its
    /// kind's name; nil for loose lines.
    public static func label(of section: RenderSection) -> String? {
        if let label = section.label?.trimmingCharacters(in: .whitespaces), !label.isEmpty {
            return label
        }
        return section.kind.map(SectionLabels.displayName)
    }

    /// The content fingerprint a placed cue stores: the arrangement fingerprint (R123), so
    /// notes and arrangements always agree on whether a section moved.
    public static func fingerprint(of section: RenderSection) -> String {
        SongSections.fingerprint(of: section)
    }

    /// Cues per render section (by label, case-insensitive after trimming, and 1-based
    /// occurrence of that label; a cue without an occurrence pins to every one), as cue
    /// indices, plus the indices of cues whose section no longer exists. Placed cues are
    /// re-anchored first (`reanchor`). Phase 2 interface.
    public static func pin(
        _ cues: [SongCue],
        to sections: [RenderSection],
    ) -> (pinned: [[Int]], unmatched: [Int]) {
        let anchors = Anchors(sections)
        let cues = anchors.reanchor(cues).cues
        var pinned = Array(repeating: [Int](), count: sections.count)
        var unmatched: [Int] = []
        for (index, cue) in cues.enumerated() {
            let targets = anchors.targets(of: cue)
            if targets.isEmpty {
                unmatched.append(index)
            }
            for target in targets {
                pinned[target].append(index)
            }
        }
        return (pinned, unmatched)
    }

    /// Placed cues (an occurrence and a fingerprint) checked against the song (R145 question
    /// 5): a cue whose label and occurrence still name a section with its fingerprint is
    /// kept; otherwise, when exactly one section of that label has it, the cue moves to that
    /// occurrence; otherwise it keeps its occurrence and is listed in `unsure` (the sheet's
    /// "Check placement" mark). Same count and order as `cues`.
    public static func reanchor(
        _ cues: [SongCue],
        to sections: [RenderSection],
    ) -> (cues: [SongCue], unsure: Set<CueID>) {
        Anchors(sections).reanchor(cues)
    }

    static func key(_ label: String) -> String {
        label.trimmingCharacters(in: .whitespaces).lowercased()
    }
}
