// Owner: P3-13. Section notes (R87, R106): one concept over two stores. A chart note is a
// `{comment}` line in the `.cho` (portable, printed, shown everywhere); a stage-only note is
// a sidecar cue (`SongCue`, shown as a callout in live mode only). "Show on stage only"
// moves a note between them as one edit. Lyrics are never touched.

import ChordPro
import Editing
import Foundation

/// One note on a section, read from either store.
public struct SectionNote: Sendable, Hashable, Identifiable {
    /// Where the note lives.
    public enum Source: Sendable, Hashable {
        /// The `{comment}` line at this path (a chart note).
        case chart(BlockPath)
        /// The sidecar cue at this index in `Sidecar.cues` (a stage-only note).
        case stage(Int)
    }

    public var source: Source
    public var text: String
    /// Which occurrence of its section's label the note is on (1-based); nil = every one
    /// (a stage note pinned to the label), or the label occurs only once.
    public var occurrence: Int?

    public var id: Source {
        source
    }

    /// True for sidecar cues: shown in live mode only.
    public var isStageOnly: Bool {
        if case .stage = source {
            return true
        }
        return false
    }

    public init(source: Source, text: String, occurrence: Int? = nil) {
        self.source = source
        self.text = text
        self.occurrence = occurrence
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
    /// The header of the first written-out section with this label: where a new chart note
    /// goes (its first line). Nil when there is none (a label only `{chorus}` repeats use).
    public var chartTarget: BlockPath?
    /// The section headers in this group, for the section band's badge.
    public var headers: [BlockPath]
    public var notes: [SectionNote]

    /// Chart notes can be added here.
    public var acceptsChartNotes: Bool {
        chartTarget != nil
    }

    /// Stage-only notes can be added here.
    public var acceptsStageNotes: Bool {
        kind == .section
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

/// A planned section note edit: the `.cho` change (nil when only cues change) and the
/// sidecar cues after it. The host applies both as one undoable step.
public struct SectionNoteChange: Sendable, Equatable {
    public var source: SourceChange?
    public var cues: [SongCue]
    public var actionName: String

    public init(source: SourceChange?, cues: [SongCue], actionName: String) {
        self.source = source
        self.cues = cues
        self.actionName = actionName
    }
}

/// One section note edit.
public enum SectionNoteEdit: Sendable, Hashable {
    case setText(SectionNote.Source, String)
    /// The "Show on stage only" toggle: moves the note between the `.cho` and the sidecar.
    case setStageOnly(SectionNote.Source, Bool)
    /// Re-pins a stage note to another label and occurrence (nil = every one).
    case pin(SectionNote.Source, section: String, occurrence: Int?)
    case delete(SectionNote.Source)
    case add(group: SectionNoteGroup.ID, text: String, stageOnly: Bool)
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
        let built = Builder(sections: sections, cues: cues)
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

    public func group(id: SectionNoteGroup.ID) -> SectionNoteGroup? {
        groups.first { $0.id == id }
    }

    /// The group a note is in.
    public func group(of source: SectionNote.Source) -> SectionNoteGroup? {
        groups.first { group in group.notes.contains { $0.source == source } }
    }

    public func note(_ source: SectionNote.Source) -> SectionNote? {
        all.first { $0.source == source }
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

    /// Cues per render section (by label, case-insensitive after trimming, and 1-based
    /// occurrence of that label; a cue without an occurrence pins to every one), as cue
    /// indices, plus the indices of cues whose section no longer exists. Phase 2 interface.
    public static func pin(
        _ cues: [SongCue],
        to sections: [RenderSection],
    ) -> (pinned: [[Int]], unmatched: [Int]) {
        let anchors = Anchors(sections)
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

    static func key(_ label: String) -> String {
        label.trimmingCharacters(in: .whitespaces).lowercased()
    }
}

/// Labels and per-label occurrence numbers of a song's render sections.
struct Anchors {
    let keys: [String?]
    let occurrence: [Int]

    init(_ sections: [RenderSection]) {
        keys = sections.map { SectionNotes.label(of: $0).map(SectionNotes.key) }
        var seen: [String: Int] = [:]
        var occurrence: [Int] = []
        for key in keys {
            guard let key else {
                occurrence.append(0)
                continue
            }
            let count = (seen[key] ?? 0) + 1
            seen[key] = count
            occurrence.append(count)
        }
        self.occurrence = occurrence
    }

    func targets(of cue: SongCue) -> [Int] {
        let key = SectionNotes.key(cue.section)
        return keys.indices.filter { index in
            keys[index] == key && (cue.occurrence.map { $0 == occurrence[index] } ?? true)
        }
    }

    func count(of key: String) -> Int {
        keys.count { $0 == key }
    }
}

// MARK: - Building

private struct Builder {
    let sections: [RenderSection]
    let anchors: Anchors
    var groups: [SectionNoteGroup] = []
    var counts: [BlockPath: Int] = [:]
    /// Render section -> its group (before empty loose groups are dropped).
    private var groupOfSection: [Int?]
    /// Label key -> its section group.
    private var byKey: [String: Int] = [:]

    init(sections: [RenderSection], cues: [SongCue]) {
        self.sections = sections
        anchors = Anchors(sections)
        groupOfSection = Array(repeating: nil, count: sections.count)
        buildGroups()
        addChartNotes()
        addStageNotes(cues)
        // Loose runs show only when they hold notes (a cue cannot pin to them).
        groups.removeAll { $0.kind == .loose && $0.notes.isEmpty }
    }

    /// One group per label in order of first appearance, one per run of loose lines.
    private mutating func buildGroups() {
        var lastLabel: String?
        for (index, section) in sections.enumerated() {
            guard let key = anchors.keys[index], let label = SectionNotes.label(of: section) else {
                addLoose(index, after: lastLabel)
                continue
            }
            lastLabel = label
            let group = byKey[key] ?? newGroup(SectionNoteGroup(
                id: "section:\(key)",
                kind: .section,
                title: label,
                label: label,
                occurrences: anchors.count(of: key),
                chartTarget: nil,
                headers: [],
                notes: [],
            ))
            byKey[key] = group
            groupOfSection[index] = group
            if let header = section.path {
                groups[group].headers.append(header)
                groups[group].chartTarget = groups[group].chartTarget ?? header
            }
        }
    }

    private mutating func addLoose(_ index: Int, after label: String?) {
        if index > 0, anchors.keys[index - 1] == nil, let previous = groupOfSection[index - 1] {
            groupOfSection[index] = previous
            return
        }
        groupOfSection[index] = newGroup(SectionNoteGroup(
            id: "loose:\(index)",
            kind: .loose,
            title: label.map { "After \($0)" } ?? "Before the first section",
            label: nil,
            occurrences: 0,
            chartTarget: nil,
            headers: [],
            notes: [],
        ))
    }

    private mutating func newGroup(_ group: SectionNoteGroup) -> Int {
        groups.append(group)
        return groups.count - 1
    }

    /// Chart notes: in the section whose header owns their line (a section's parts after
    /// a `{chorus}` belong to it), else in their loose run.
    private mutating func addChartNotes() {
        let headerIndex = Dictionary(
            sections.enumerated().compactMap { index, section in
                section.path.map { ($0.block, index) }
            },
            uniquingKeysWith: { first, _ in first },
        )
        for (index, section) in sections.enumerated() {
            for case let .comment(text, _, path) in section.items {
                let owner = path.item == nil ? index : (headerIndex[path.block] ?? index)
                guard let group = groupOfSection[owner] else { continue }
                let repeated = anchors.keys[owner].map { anchors.count(of: $0) > 1 } ?? false
                groups[group].notes.append(SectionNote(
                    source: .chart(path),
                    text: text,
                    occurrence: repeated ? anchors.occurrence[owner] : nil,
                ))
                if let header = sections[owner].path {
                    counts[header, default: 0] += 1
                }
            }
        }
    }

    /// Stage notes, after the chart notes of their group, in sidecar order; a cue whose
    /// label or occurrence is gone goes to an orphaned group for its label.
    private mutating func addStageNotes(_ cues: [SongCue]) {
        var orphaned: [String: Int] = [:]
        for (index, cue) in cues.enumerated() {
            let note = SectionNote(
                source: .stage(index),
                text: cue.text,
                occurrence: cue.occurrence,
            )
            let targets = anchors.targets(of: cue)
            for header in targets.compactMap({ sections[$0].path }) {
                counts[header, default: 0] += 1
            }
            let key = SectionNotes.key(cue.section)
            if !targets.isEmpty, let group = byKey[key] {
                groups[group].notes.append(note)
            } else if let group = orphaned[key] {
                groups[group].notes.append(note)
            } else {
                orphaned[key] = newGroup(SectionNoteGroup(
                    id: "orphaned:\(key)",
                    kind: .orphaned,
                    title: cue.section,
                    label: cue.section,
                    occurrences: 0,
                    chartTarget: nil,
                    headers: [],
                    notes: [note],
                ))
            }
        }
    }
}
