// Owner: P3-13. Plans section note edits over both stores (R106): chart notes through
// `DocumentEditor`'s comment operations (whole `{comment}` lines only), stage-only notes as
// the sidecar cue list. A toggle is one change carrying both halves.

import ChordPro
import Editing
import Foundation

public extension SectionNotes {
    /// Plans `edit` against the song as `snapshot` and `cues` hold it now.
    static func change(
        _ edit: SectionNoteEdit,
        in snapshot: SourceSnapshot,
        cues: [SongCue],
    ) throws(SectionNoteError) -> SectionNoteChange {
        var planner = SectionNotePlanner(snapshot: snapshot, cues: cues)
        return try planner.plan(edit)
    }
}

private struct SectionNotePlanner {
    let snapshot: SourceSnapshot
    let sections: [RenderSection]
    let notes: SectionNotes
    var cues: [SongCue]

    init(snapshot: SourceSnapshot, cues: [SongCue]) {
        self.snapshot = snapshot
        self.cues = cues
        sections = RenderModel(document: snapshot.document, options: DisplayOptions()).sections
        notes = SectionNotes(sections: sections, cues: cues)
    }

    mutating func plan(_ edit: SectionNoteEdit) throws(SectionNoteError) -> SectionNoteChange {
        switch edit {
        case let .setText(source, text):
            try setText(source, text)
        case let .setStageOnly(source, stageOnly):
            try setStageOnly(source, stageOnly)
        case let .pin(source, section, occurrence):
            try pin(source, section: section, occurrence: occurrence)
        case let .delete(source):
            try delete(source)
        case let .add(id, text, stageOnly):
            try add(to: id, text: text, stageOnly: stageOnly)
        }
    }

    private mutating func setText(
        _ source: SectionNote.Source,
        _ text: String,
    ) throws(SectionNoteError) -> SectionNoteChange {
        let text = try Self.cleaned(text)
        switch source {
        case let .chart(path):
            return try change(.setCommentText(path, text: text), name: "Edit Note")
        case let .stage(index):
            try checkCue(index)
            cues[index].text = text
            return done("Edit Note")
        }
    }

    private mutating func pin(
        _ source: SectionNote.Source,
        section: String,
        occurrence: Int?,
    ) throws(SectionNoteError) -> SectionNoteChange {
        guard case let .stage(index) = source else { throw .noAnchor }
        try checkCue(index)
        let label = section.trimmingCharacters(in: .whitespaces)
        guard !label.isEmpty else { throw .noAnchor }
        cues[index].section = label
        cues[index].occurrence = occurrence
        return done("Move Note")
    }

    private mutating func delete(
        _ source: SectionNote.Source,
    ) throws(SectionNoteError) -> SectionNoteChange {
        switch source {
        case let .chart(path):
            return try change(.removeComment(path), name: "Delete Note")
        case let .stage(index):
            try checkCue(index)
            cues.remove(at: index)
            return done("Delete Note")
        }
    }

    private mutating func add(
        to id: SectionNoteGroup.ID,
        text: String,
        stageOnly: Bool,
    ) throws(SectionNoteError) -> SectionNoteChange {
        let text = try Self.cleaned(text)
        guard let group = notes.group(id: id) else { throw .notFound }
        if stageOnly {
            guard group.acceptsStageNotes, let label = group.label else { throw .noAnchor }
            cues.append(SongCue(section: label, text: text))
            return done("Add Note")
        }
        guard let target = group.chartTarget else { throw .noAnchor }
        return try change(.insertComment(text, at: target), name: "Add Note")
    }

    private mutating func setStageOnly(
        _ source: SectionNote.Source,
        _ stageOnly: Bool,
    ) throws(SectionNoteError) -> SectionNoteChange {
        guard let note = notes.note(source), let group = notes.group(of: source) else {
            throw .notFound
        }
        switch (source, stageOnly) {
        case (.chart, false), (.stage, true):
            return done("")
        case let (.chart(path), true):
            // The cue pins to the label, and to this occurrence when the label repeats.
            guard group.kind == .section, let label = group.label else { throw .noAnchor }
            let text = CommentText.clean(note.text)
            guard !text.isEmpty else { throw .invalidText }
            cues.append(SongCue(section: label, occurrence: note.occurrence, text: text))
            return try change(.removeComment(path), name: "Show on Stage Only")
        case let (.stage(index), false):
            try checkCue(index)
            guard let target = chartTarget(for: cues[index]) else { throw .noAnchor }
            let text = try Self.cleaned(cues[index].text)
            cues.remove(at: index)
            return try change(.insertComment(text, at: target), name: "Show on Chart")
        }
    }

    /// Where a stage note becomes a chart note: the first line inside the first section it
    /// pins to; a `{chorus}` repeat sends it to the chorus it repeats (which every repeat
    /// shows), a section's part after a repeat to that section's header.
    private func chartTarget(for cue: SongCue) -> BlockPath? {
        for target in Anchors(sections).targets(of: cue) {
            if let header = header(of: target) {
                return header
            }
            if sections[target].isRepeat, let root = repeatRoot(of: target),
               let header = header(of: root)
            {
                return header
            }
        }
        return nil
    }

    private func header(of index: Int) -> BlockPath? {
        let section = sections[index]
        guard !section.isRepeat, section.kind != nil else { return nil }
        if let path = section.path {
            return path
        }
        // A section's part after a `{chorus}`: its items carry the section's block.
        return section.items.lazy.compactMap(Self.path).first.map { BlockPath(block: $0.block) }
    }

    /// The written-out chorus a `{chorus}` repeats: the closest earlier one with the same
    /// label, else the closest earlier chorus (as live mode expands it).
    private func repeatRoot(of index: Int) -> Int? {
        let wanted = SectionNotes.label(of: sections[index]).map(SectionNotes.key)
        let choruses = sections[..<index].indices.reversed().filter { candidate in
            let section = sections[candidate]
            return section.kind == .chorus && !section.isRepeat && !section.items.isEmpty
        }
        return choruses
            .first { SectionNotes.label(of: sections[$0]).map(SectionNotes.key) == wanted }
            ?? choruses.first
    }

    private static func path(of item: RenderItem) -> BlockPath? {
        switch item {
        case let .lyrics(line): line.path
        case let .comment(_, _, path): path
        case let .stanzaBreak(path): path
        case let .verbatim(_, path): path
        }
    }

    private func checkCue(_ index: Int) throws(SectionNoteError) {
        guard cues.indices.contains(index) else { throw .notFound }
    }

    private func done(_ name: String) -> SectionNoteChange {
        SectionNoteChange(source: nil, cues: cues, actionName: name)
    }

    private func change(
        _ operation: EditOperation,
        name: String,
    ) throws(SectionNoteError) -> SectionNoteChange {
        do {
            let planned = try DocumentEditor.change(for: operation, in: snapshot)
            var source = planned
            source.actionName = name
            return SectionNoteChange(source: source, cues: cues, actionName: name)
        } catch {
            switch error {
            case .invalidPath, .wrongBlockKind: throw .notFound
            case .notCommentText: throw .invalidText
            default: throw .edit(error)
            }
        }
    }

    private static func cleaned(_ text: String) throws(SectionNoteError) -> String {
        let text = CommentText.clean(text)
        guard CommentText.isValid(text) else { throw .invalidText }
        return text
    }
}
