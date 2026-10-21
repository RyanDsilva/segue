// Owner: P3-13, P3-17. Builds `SectionNotes` from a song's render sections and its cues:
// groups, derived chart note IDs, linked every-time copies (R145 question 2), re-anchored
// stage notes (R145 question 5) and placement order.

import ChordPro
import Editing
import Foundation

/// Reads a song's notes into groups: one per label in song order, loose runs that hold
/// notes, orphaned cues last.
struct SectionNotesBuilder {
    let sections: [RenderSection]
    let anchors: Anchors
    var groups: [SectionNoteGroup] = []
    var counts: [BlockPath: Int] = [:]
    /// Render section -> its group (before empty loose groups are dropped).
    private var groupOfSection: [Int?]
    /// Label key -> its section group.
    private var byKey: [String: Int] = [:]
    /// Display order within a group: chart notes in file order, then stage notes.
    private var order: [SectionNoteID: Int] = [:]

    init(sections: [RenderSection], cues: [SongCue]) {
        self.sections = sections
        anchors = Anchors(sections)
        groupOfSection = Array(repeating: nil, count: sections.count)
        buildGroups()
        addChartNotes()
        addStageNotes(cues)
        sortByPlacement()
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
                instances: anchors.instances(of: key),
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
            instances: [],
            notes: [],
        ))
    }

    private mutating func newGroup(_ group: SectionNoteGroup) -> Int {
        groups.append(group)
        return groups.count - 1
    }

    /// A `{comment}` line read from the song: where it is and whose section owns it.
    private struct ChartLine {
        var path: BlockPath
        var text: String
        /// The render section that owns it (a section's parts after a `{chorus}` belong to
        /// its first part).
        var owner: Int
        /// 1-based among same-text lines with the same owner.
        var ordinal: Int
    }

    /// Chart notes: in the section whose header owns their line, else in their loose run.
    /// Copies of one text and ordinal in every written-out instance of a repeated label read
    /// as one every-time note (R145 question 2).
    private mutating func addChartNotes() {
        let headerIndex = Dictionary(
            sections.enumerated().compactMap { index, section in
                section.path.map { ($0.block, index) }
            },
            uniquingKeysWith: { first, _ in first },
        )
        var lines: [ChartLine] = []
        var seen: [Int: [String: Int]] = [:]
        for (index, section) in sections.enumerated() {
            for case let .comment(text, _, path) in section.items {
                let owner = path.item == nil ? index : (headerIndex[path.block] ?? index)
                let ordinal = (seen[owner]?[text] ?? 0) + 1
                seen[owner, default: [:]][text] = ordinal
                lines.append(ChartLine(path: path, text: text, owner: owner, ordinal: ordinal))
            }
        }
        let linked = linkedCopies(lines)
        var emitted: Set<String> = []
        for line in lines {
            guard let group = groupOfSection[line.owner] else { continue }
            if let header = sections[line.owner].path {
                counts[header, default: 0] += 1
            }
            if let key = anchors.keys[line.owner], let copies = linked[LinkKey(
                label: key,
                text: line.text,
                ordinal: line.ordinal,
            )] {
                guard emitted.insert("\(key)\u{0}\(line.text)\u{0}\(line.ordinal)").inserted
                else { continue }
                append(SectionNote(
                    id: .chart(ChartNoteID(
                        anchor: .everyTime(label: key),
                        ordinal: line.ordinal,
                        text: line.text,
                    )),
                    sources: copies.map { .chart($0.path) },
                    text: line.text,
                    placement: .everyTime,
                    instances: copies.map { anchors.occurrence[$0.owner] },
                ), to: group)
                continue
            }
            append(chartNote(line), to: group)
        }
    }

    private func chartNote(_ line: ChartLine) -> SectionNote {
        guard let key = anchors.keys[line.owner] else {
            let run = groups[groupOfSection[line.owner] ?? 0].id
            let start = Int(run.dropFirst("loose:".count)) ?? line.owner
            return SectionNote(
                id: .chart(ChartNoteID(
                    anchor: .loose(start),
                    ordinal: line.ordinal,
                    text: line.text,
                )),
                sources: [.chart(line.path)],
                text: line.text,
            )
        }
        let number = anchors.occurrence[line.owner]
        return SectionNote(
            id: .chart(ChartNoteID(
                anchor: .instance(label: key, occurrence: number),
                ordinal: line.ordinal,
                text: line.text,
            )),
            sources: [.chart(line.path)],
            text: line.text,
            placement: anchors.count(of: key) > 1 ? .instance(number) : nil,
            instances: [number],
        )
    }

    private struct LinkKey: Hashable {
        var label: String
        var text: String
        var ordinal: Int
    }

    /// Text and ordinal present in every written-out instance of a label that occurs more
    /// than once, with its copies in song order.
    private func linkedCopies(_ lines: [ChartLine]) -> [LinkKey: [ChartLine]] {
        var byKey: [LinkKey: [ChartLine]] = [:]
        for line in lines {
            guard let key = anchors.keys[line.owner], anchors.count(of: key) > 1 else { continue }
            byKey[LinkKey(label: key, text: line.text, ordinal: line.ordinal), default: []]
                .append(line)
        }
        return byKey.filter { link, copies in
            let wanted = Set(anchors.instances(of: link.label).filter(\.acceptsChartNotes)
                .compactMap { anchors.index(of: link.label, occurrence: $0.occurrence) })
            return !wanted.isEmpty && Set(copies.map(\.owner)) == wanted
        }
    }

    /// Stage notes, after the chart notes of their group, in sidecar order; a cue whose
    /// label or occurrence is gone goes to an orphaned group for its label.
    private mutating func addStageNotes(_ stored: [SongCue]) {
        let (cues, unsure) = anchors.reanchor(stored)
        var orphaned: [String: Int] = [:]
        for (index, cue) in cues.enumerated() {
            let key = SectionNotes.key(cue.section)
            let repeated = anchors.count(of: key) > 1
            let note = SectionNote(
                id: .stage(cue.id),
                sources: [.stage(index)],
                text: cue.text,
                placement: repeated || anchors.count(of: key) == 0
                    ? cue.occurrence.map(NotePlacement.instance) ?? .everyTime
                    : nil,
                needsPlacementCheck: unsure.contains(cue.id),
            )
            let targets = anchors.targets(of: cue)
            for header in targets.compactMap({ sections[$0].path }) {
                counts[header, default: 0] += 1
            }
            if !targets.isEmpty, let group = byKey[key] {
                append(note, to: group)
            } else if let group = orphaned[key] {
                append(note, to: group)
            } else {
                orphaned[key] = newGroup(SectionNoteGroup(
                    id: "orphaned:\(key)",
                    kind: .orphaned,
                    title: cue.section,
                    label: cue.section,
                    occurrences: 0,
                    chartTarget: nil,
                    headers: [],
                    instances: [],
                    notes: [],
                ))
                append(note, to: orphaned[key] ?? 0)
            }
        }
    }

    private mutating func append(_ note: SectionNote, to group: Int) {
        order[note.id] = order.count
        groups[group].notes.append(note)
    }

    /// Section groups list every-time notes first, then #1, #2, ...; within one placement
    /// chart notes (file order) before stage notes (sidecar order).
    private mutating func sortByPlacement() {
        for index in groups.indices where groups[index].kind == .section {
            groups[index].notes.sort { left, right in
                (Self.rank(left), left.isStageOnly ? 1 : 0, order[left.id] ?? 0)
                    < (Self.rank(right), right.isStageOnly ? 1 : 0, order[right.id] ?? 0)
            }
        }
    }

    private static func rank(_ note: SectionNote) -> Int {
        switch note.placement {
        case .everyTime, nil: 0
        case let .instance(number): number
        }
    }
}
