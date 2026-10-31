// Owner: P3-13, P3-17. How section notes anchor to a song's sections: label + 1-based
// occurrence (shared with live layout and per-slot arrangements), the fingerprint
// re-anchoring of placed cues (R145 question 5), and where a chart note's line goes.

import ChordPro
import Editing
import Foundation

/// Labels and per-label occurrence numbers of a song's render sections.
struct Anchors {
    let sections: [RenderSection]
    let keys: [String?]
    let occurrence: [Int]

    init(_ sections: [RenderSection]) {
        self.sections = sections
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

    /// The render section of occurrence `number` of label `key`.
    func index(of key: String, occurrence number: Int) -> Int? {
        keys.indices.first { keys[$0] == key && occurrence[$0] == number }
    }

    func reanchor(_ cues: [SongCue]) -> (cues: [SongCue], unsure: Set<CueID>) {
        var cues = cues
        var unsure: Set<CueID> = []
        for position in cues.indices {
            let cue = cues[position]
            guard let number = cue.occurrence, let fingerprint = cue.fingerprint else { continue }
            let key = SectionNotes.key(cue.section)
            // A cue whose occurrence is gone is orphaned, not re-anchored.
            guard let current = index(of: key, occurrence: number) else { continue }
            if SectionNotes.fingerprint(of: sections[current]) == fingerprint {
                continue
            }
            let matches = keys.indices.filter { index in
                keys[index] == key && SectionNotes.fingerprint(of: sections[index]) == fingerprint
            }
            if matches.count == 1 {
                cues[position].occurrence = occurrence[matches[0]]
            } else {
                unsure.insert(cue.id)
            }
        }
        return (cues, unsure)
    }

    // MARK: Where chart notes go

    /// The header a chart note for render section `index` goes under: its own header; a
    /// section's part after a `{chorus}` its section's header; nil for a repeat.
    func header(of index: Int) -> BlockPath? {
        let section = sections[index]
        guard !section.isRepeat, section.kind != nil else { return nil }
        if let path = section.path {
            return path
        }
        // A section's part after a `{chorus}`: its items carry the section's block.
        return section.items.lazy.compactMap(Self.path).first.map { BlockPath(block: $0.block) }
    }

    /// Where a chart note for render section `index` goes: its header; a `{chorus}` repeat
    /// sends it to the chorus it repeats (which every repeat shows).
    func chartTarget(of index: Int) -> BlockPath? {
        if let header = header(of: index) {
            return header
        }
        if sections[index].isRepeat, let root = repeatRoot(of: index) {
            return header(of: root)
        }
        return nil
    }

    /// The written-out chorus a `{chorus}` repeats: the closest earlier one with the same
    /// label, else the closest earlier chorus (as live mode expands it).
    func repeatRoot(of index: Int) -> Int? {
        let wanted = keys[index]
        let choruses = sections[..<index].indices.reversed().filter { candidate in
            let section = sections[candidate]
            return section.kind == .chorus && !section.isRepeat && !section.items.isEmpty
        }
        return choruses.first { keys[$0] == wanted } ?? choruses.first
    }

    /// Every occurrence of label `key`, in song order.
    func instances(of key: String) -> [NoteInstance] {
        keys.indices.filter { keys[$0] == key }.map { index in
            let section = sections[index]
            let root = section.isRepeat ? repeatRoot(of: index) : nil
            return NoteInstance(
                occurrence: occurrence[index],
                isRepeat: section.isRepeat,
                header: section.isRepeat ? nil : header(of: index),
                chartTarget: chartTarget(of: index),
                repeatOf: root.flatMap { keys[$0] == key ? occurrence[$0] : nil },
                fingerprint: SectionNotes.fingerprint(of: section),
            )
        }
    }

    static func path(of item: RenderItem) -> BlockPath? {
        switch item {
        case let .lyrics(line): line.path
        case let .comment(_, _, path): path
        case let .stanzaBreak(path): path
        case let .verbatim(_, path): path
        case .fillTab: nil
        }
    }
}
