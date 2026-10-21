// Owner: P3-13, P3-17. Plans section note edits over both stores (R106): chart notes through
// `DocumentEditor`'s comment operations (whole `{comment}` lines only), stage-only notes as
// the sidecar cue list. A toggle or a move is one change carrying both halves. Notes are
// named by `SectionNoteID` and resolved here, against the song as it is when the edit is
// planned (R144), so a queued edit never lands on another note.

import ChordPro
import Editing
import Foundation

public extension SectionNotes {
    /// Plans `edit` against the song as `snapshot` and `cues` hold it now. `newID` makes the
    /// ID of a new stage note (injected by tests).
    static func change(
        _ edit: SectionNoteEdit,
        in snapshot: SourceSnapshot,
        cues: [SongCue],
        newID: @escaping () -> CueID = { CueID() },
    ) throws(SectionNoteError) -> SectionNoteChange {
        var planner = SectionNotePlanner(snapshot: snapshot, cues: cues, newID: newID)
        return try planner.plan(edit)
    }
}

private struct SectionNotePlanner {
    let snapshot: SourceSnapshot
    let sections: [RenderSection]
    let anchors: Anchors
    let notes: SectionNotes
    let newID: () -> CueID
    /// The cues as the song reads them: placed cues re-anchored (R145 question 5), so any
    /// edit writes the corrected occurrence back.
    var cues: [SongCue]

    init(snapshot: SourceSnapshot, cues: [SongCue], newID: @escaping () -> CueID) {
        self.snapshot = snapshot
        self.newID = newID
        sections = RenderModel(document: snapshot.document, options: DisplayOptions()).sections
        anchors = Anchors(sections)
        self.cues = anchors.reanchor(cues).cues
        notes = SectionNotes(sections: sections, cues: cues)
    }

    mutating func plan(_ edit: SectionNoteEdit) throws(SectionNoteError) -> SectionNoteChange {
        switch edit {
        case let .setText(id, text):
            try setText(id, text)
        case let .setStageOnly(id, stageOnly):
            try setStageOnly(id, stageOnly)
        case let .place(id, placement):
            try place(id, placement)
        case let .pin(id, section, occurrence):
            try pin(id, section: section, occurrence: occurrence)
        case let .delete(id):
            try delete(id)
        case let .add(group, text, stageOnly, placement):
            try add(to: group, text: text, stageOnly: stageOnly, placement: placement)
        }
    }

    // MARK: Edits

    private mutating func setText(
        _ id: SectionNoteID,
        _ text: String,
    ) throws(SectionNoteError) -> SectionNoteChange {
        let text = try Self.cleaned(text)
        let note = try resolve(id)
        if let index = cueIndex(note) {
            cues[index].text = text
            return done("Edit Note", result: id)
        }
        // A linked note edits every copy.
        return try change(
            note.chartPaths.map { .setText($0, text) },
            name: "Edit Note",
            probe: note.chartPaths.first,
        )
    }

    private mutating func delete(
        _ id: SectionNoteID,
    ) throws(SectionNoteError) -> SectionNoteChange {
        let note = try resolve(id)
        let outcome = outcome(.delete, of: note)
        if let index = cueIndex(note) {
            cues.remove(at: index)
            return done("Delete Note", result: nil, outcome: outcome)
        }
        var planned = try change(note.chartPaths.map { .remove($0) }, name: "Delete Note")
        planned.outcome = outcome
        return planned
    }

    private mutating func pin(
        _ id: SectionNoteID,
        section: String,
        occurrence: Int?,
    ) throws(SectionNoteError) -> SectionNoteChange {
        let note = try resolve(id)
        guard let index = cueIndex(note) else { throw .noAnchor }
        let label = section.trimmingCharacters(in: .whitespaces)
        guard !label.isEmpty else { throw .noAnchor }
        cues[index].section = label
        cues[index].occurrence = occurrence
        cues[index].fingerprint = fingerprint(label: label, occurrence: occurrence)
        return done("Move Note", result: id, outcome: stageOutcome(.move, cues[index]))
    }

    private mutating func add(
        to groupID: SectionNoteGroup.ID,
        text: String,
        stageOnly: Bool,
        placement: NotePlacement?,
    ) throws(SectionNoteError) -> SectionNoteChange {
        let text = try Self.cleaned(text)
        guard let group = notes.group(id: groupID) else { throw .notFound }
        let placement = group.hasPlacements ? placement ?? .everyTime : nil
        if stageOnly {
            guard group.acceptsStageNotes, let label = group.label else { throw .noAnchor }
            let cue = try placedCue(label: label, placement: placement, in: group, text: text)
            cues.append(cue)
            return done("Add Note", result: .stage(cue.id), outcome: stageOutcome(.add, cue))
        }
        let targets: [BlockPath]
        if group.hasPlacements, let placement {
            targets = try chartTargets(placement, in: group)
        } else {
            guard let target = group.chartTarget else { throw .noAnchor }
            targets = [target]
        }
        var planned = try change(targets.map { .append(text, section: $0) }, name: "Add Note")
        planned.outcome = chartOutcome(.add, placement: placement, in: group)
        return planned
    }

    private mutating func setStageOnly(
        _ id: SectionNoteID,
        _ stageOnly: Bool,
    ) throws(SectionNoteError) -> SectionNoteChange {
        let note = try resolve(id)
        guard let group = notes.group(of: id) else { throw .notFound }
        switch (cueIndex(note), stageOnly) {
        case (nil, false), (.some, true):
            return done("", result: id)
        case (nil, true):
            // The cue pins to the label, and to the note's instance when the label repeats.
            guard group.kind == .section, let label = group.label else { throw .noAnchor }
            let text = CommentText.clean(note.text)
            guard !text.isEmpty else { throw .invalidText }
            let cue = try placedCue(label: label, placement: note.placement, in: group, text: text)
            cues.append(cue)
            var planned = try change(
                note.chartPaths.map { .remove($0) },
                name: "Show on Stage Only",
            )
            planned.resultID = .stage(cue.id)
            planned.outcome = stageOutcome(.toggle, cue)
            return planned
        case let (index?, false):
            let cue = cues[index]
            let targets = chartTargets(for: cue)
            guard !targets.isEmpty else { throw .noAnchor }
            let text = try Self.cleaned(cue.text)
            cues.remove(at: index)
            var planned = try change(
                targets.map { .append(text, section: $0) },
                name: "Show on Chart",
            )
            planned.outcome = SectionNoteOutcome(
                action: .toggle,
                kind: .chart,
                placement: placementKind(group.hasPlacements ? note.placement : nil, in: group),
            )
            return planned
        }
    }

    /// Moves a note to `placement` on its label as one step ("Move Note"). A chart note keeps
    /// the copies already in a target instance (so it does not move inside that section),
    /// gains one appended copy in each other target and loses the rest; moved to a `{chorus}`
    /// repeat it becomes a stage note there (R144).
    private mutating func place(
        _ id: SectionNoteID,
        _ placement: NotePlacement,
    ) throws(SectionNoteError) -> SectionNoteChange {
        let note = try resolve(id)
        guard let group = notes.group(of: id), group.kind == .section, let label = group.label
        else { throw .noAnchor }
        if case let .instance(number) = placement, group.instance(number) == nil {
            throw .noAnchor
        }
        if let index = cueIndex(note) {
            let occurrence = Self.occurrence(placement)
            cues[index].occurrence = occurrence
            cues[index].fingerprint = fingerprint(label: label, occurrence: occurrence)
            return done("Move Note", result: id, outcome: stageOutcome(.move, cues[index]))
        }
        if case let .instance(number) = placement, group.instance(number)?.isRepeat == true {
            let cue = try placedCue(label: label, placement: placement, in: group, text: note.text)
            cues.append(cue)
            var planned = try change(note.chartPaths.map { .remove($0) }, name: "Move Note")
            planned.resultID = .stage(cue.id)
            planned.outcome = stageOutcome(.move, cue)
            return planned
        }
        let targets = try chartTargets(placement, in: group)
        var kept: [BlockPath] = []
        var edits: [CommentEdit] = []
        for target in targets {
            if let path = note.chartPaths.first(where: { owner(of: $0) == target }) {
                kept.append(path)
            } else {
                edits.append(.append(note.text, section: target))
            }
        }
        edits += note.chartPaths.filter { !kept.contains($0) }.map { .remove($0) }
        guard !edits.isEmpty else { return done("", result: id) }
        var planned = try change(edits, name: "Move Note", probe: kept.first)
        planned.outcome = chartOutcome(.move, placement: placement, in: group)
        return planned
    }

    // MARK: Resolution

    private func resolve(_ id: SectionNoteID) throws(SectionNoteError) -> SectionNote {
        guard let note = notes.note(id) else { throw .notFound }
        return note
    }

    private func cueIndex(_ note: SectionNote) -> Int? {
        guard case let .stage(id) = note.id else { return nil }
        return cues.firstIndex { $0.id == id }
    }

    /// The section header that owns the `{comment}` line at `path`.
    private func owner(of path: BlockPath) -> BlockPath {
        BlockPath(block: path.block)
    }

    /// Section headers a chart note with `placement` goes in: every written-out instance, or
    /// the one instance. A repeat cannot hold a chart note (`noAnchor`).
    private func chartTargets(
        _ placement: NotePlacement,
        in group: SectionNoteGroup,
    ) throws(SectionNoteError) -> [BlockPath] {
        switch placement {
        case .everyTime:
            let targets = group.writtenOut.compactMap(\.chartTarget)
            if !targets.isEmpty {
                return targets
            }
            // A label only `{chorus}` repeats use: the chorus they repeat.
            guard let target = group.instances.lazy.compactMap(\.chartTarget).first else {
                throw .noAnchor
            }
            return [target]
        case let .instance(number):
            guard let instance = group.instance(number), instance.acceptsChartNotes,
                  let target = instance.chartTarget
            else { throw .noAnchor }
            return [target]
        }
    }

    /// Where a stage note becomes a chart note: an every-time cue in every written-out
    /// section it pins to (R145 question 2); a cue on a `{chorus}` repeat in the chorus it
    /// repeats; a section's part after a repeat under that section's header.
    private func chartTargets(for cue: SongCue) -> [BlockPath] {
        var targets: [BlockPath] = []
        for target in anchors.targets(of: cue) {
            if let header = anchors.chartTarget(of: target), !targets.contains(header) {
                targets.append(header)
            }
        }
        guard cue.occurrence == nil else { return Array(targets.prefix(1)) }
        // Every time: the written-out copies; the repeats' chorus only when nothing of the
        // label is written out.
        let written = anchors.targets(of: cue).compactMap { anchors.header(of: $0) }
        let unique = written.reduce(into: [BlockPath]()) {
            if !$0.contains($1) {
                $0.append($1)
            }
        }
        return unique.isEmpty ? Array(targets.prefix(1)) : unique
    }

    private func placedCue(
        label: String,
        placement: NotePlacement?,
        in group: SectionNoteGroup,
        text: String,
    ) throws(SectionNoteError) -> SongCue {
        let occurrence = placement.flatMap(Self.occurrence)
        if let occurrence, group.instance(occurrence) == nil {
            throw .noAnchor
        }
        return SongCue(
            id: newID(),
            section: label,
            occurrence: occurrence,
            text: text,
            fingerprint: fingerprint(label: label, occurrence: occurrence),
        )
    }

    private func fingerprint(label: String, occurrence: Int?) -> String? {
        guard let occurrence,
              let index = anchors.index(of: SectionNotes.key(label), occurrence: occurrence)
        else { return nil }
        return SectionNotes.fingerprint(of: sections[index])
    }

    private static func occurrence(_ placement: NotePlacement) -> Int? {
        if case let .instance(number) = placement {
            return number
        }
        return nil
    }
}

// MARK: - Results

extension SectionNotePlanner {
    /// Placed cues saved before fingerprints existed get one on the next write, when their
    /// occurrence still resolves.
    private mutating func stampFingerprints() {
        for index in cues.indices where cues[index].fingerprint == nil {
            cues[index].fingerprint = fingerprint(
                label: cues[index].section,
                occurrence: cues[index].occurrence,
            )
        }
    }

    private mutating func done(
        _ name: String,
        result: SectionNoteID?,
        outcome: SectionNoteOutcome? = nil,
    ) -> SectionNoteChange {
        stampFingerprints()
        return SectionNoteChange(
            source: nil,
            cues: cues,
            actionName: name,
            resultID: result,
            outcome: outcome,
        )
    }

    /// The `.cho` half of a change, with the chart note it leaves at `probe` (an untouched
    /// line of this snapshot) or at the first appended line as `resultID`.
    private mutating func change(
        _ edits: [CommentEdit],
        name: String,
        probe: BlockPath? = nil,
    ) throws(SectionNoteError) -> SectionNoteChange {
        stampFingerprints()
        let planned: SourceChange
        do {
            planned = try DocumentEditor.change(for: .editComments(edits), in: snapshot)
        } catch {
            switch error {
            case .invalidPath, .wrongBlockKind: throw .notFound
            case .notCommentText: throw .invalidText
            default: throw .edit(error)
            }
        }
        var source = planned
        source.actionName = name
        source.selectionAfter = nil
        return SectionNoteChange(
            source: source,
            cues: cues,
            actionName: name,
            resultID: resultID(of: planned, probe: probe),
        )
    }

    /// The chart note at the first appended line (the change's caret) or at `probe`, read
    /// from the song after the change.
    private func resultID(of change: SourceChange, probe: BlockPath?) -> SectionNoteID? {
        let offset: Int
        if let caret = change.selectionAfter?.lowerBound {
            offset = caret
        } else if let probe, let range = snapshot.sourceRange(of: probe) {
            offset = range.lowerBound + change.edits
                .filter { $0.range.upperBound <= range.lowerBound }
                .reduce(0) { $0 + $1.replacement.utf16.count - $1.range.count }
        } else {
            return nil
        }
        let after = SourceSnapshot(text: snapshot.text.applying(change.edits))
        guard let path = after.path(atSourceOffset: offset) else { return nil }
        return SectionNotes(document: after.document, cues: cues)
            .note(holding: .chart(path))?.id
    }

    private func outcome(_ action: SectionNoteOutcome.Action, of note: SectionNote)
        -> SectionNoteOutcome
    {
        let group = notes.group(of: note.id)
        return SectionNoteOutcome(
            action: action,
            kind: note.isStageOnly ? .stage : .chart,
            placement: group.map { placementKind($0.hasPlacements ? note.placement : nil, in: $0) }
                ?? .single,
        )
    }

    private func stageOutcome(_ action: SectionNoteOutcome.Action, _ cue: SongCue)
        -> SectionNoteOutcome
    {
        let group = notes.groups.first {
            $0.kind == .section && $0.label.map(SectionNotes.key) == SectionNotes.key(cue.section)
        }
        let placement: NotePlacement? = group?.hasPlacements == true
            ? cue.occurrence.map(NotePlacement.instance) ?? .everyTime
            : nil
        return SectionNoteOutcome(
            action: action,
            kind: .stage,
            placement: group.map { placementKind(placement, in: $0) } ?? .single,
        )
    }

    private func chartOutcome(
        _ action: SectionNoteOutcome.Action,
        placement: NotePlacement?,
        in group: SectionNoteGroup,
    ) -> SectionNoteOutcome {
        SectionNoteOutcome(
            action: action,
            kind: .chart,
            placement: placementKind(placement, in: group),
        )
    }

    private func placementKind(_ placement: NotePlacement?, in group: SectionNoteGroup)
        -> SectionNoteOutcome.Placement
    {
        switch placement {
        case nil: .single
        case .everyTime: .every
        case let .instance(number): group.instance(number)?.isRepeat == true ? .repeat : .instance
        }
    }

    private static func cleaned(_ text: String) throws(SectionNoteError) -> String {
        let text = CommentText.clean(text)
        guard CommentText.isValid(text) else { throw .invalidText }
        return text
    }
}

private extension SectionNote {
    var chartPaths: [BlockPath] {
        sources.compactMap { source in
            if case let .chart(path) = source {
                return path
            }
            return nil
        }
    }
}
