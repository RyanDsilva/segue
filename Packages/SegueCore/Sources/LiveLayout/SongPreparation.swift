// Owner: unit B. Turns a layout request into measured sections: repeats collapsed (or
// expanded), cues pinned to their sections, unmatched cues moved to the notes.

import ChordPro
import Editing
import Foundation
import Library

struct SongPreparation {
    let request: LayoutRequest
    let measurer: Measurer

    func measure() -> MeasuredSong {
        let original = request.model.sections
        // Cues pin to the song's own sections (song-relative label + occurrence) before an
        // arrangement reorders them; a cue shows on its section's first play only, and a
        // cue on a skipped section is simply not played (not "unmatched").
        let (pinned, unmatched) = pinCues(original)
        let sections: [RenderSection]
        let cues: [[SongCue]]
        if let order = request.arrangement {
            let arranged = ArrangedSections.build(original, order: order)
            sections = arranged.map(\.section)
            cues = arranged.map { $0.isFirstPlay ? pinned[$0.source] : [] }
        } else {
            sections = original
            cues = pinned
        }
        let collapsed = RepeatCollapser.collapse(sections, enabled: request.collapseRepeats)
        let measured = sections.indices.map { index in
            section(index, sections: sections, collapsed: collapsed[index], cues: cues[index])
        }
        var notes = request.notes
            .flatMap { $0.components(separatedBy: .newlines) }
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        notes += unmatched.map { "\($0.section): \($0.text)" }
        return MeasuredSong(
            notes: notes.map { measurer.paragraph($0, role: .note) },
            sections: measured,
            lineCount: lineCount(sections),
        )
    }

    private func section(
        _ index: Int,
        sections: [RenderSection],
        collapsed: CollapsedSection,
        cues: [SongCue],
    ) -> MeasuredSection {
        let section = sections[index]
        var name = RepeatCollapser.displayLabel(section)
        var detail: String?
        let body: MeasuredSection.Body
        if let root = collapsed.repeatOf {
            name = name ?? RepeatCollapser.displayLabel(sections[root]) ?? "Chorus"
            // The count is the gutter's small second line, so "Verse 2 x2" never wraps
            // between its words.
            detail = "x\(collapsed.occurrence)"
            body = .collapsed(
                line: measurer.paragraph(Self.repeatText(sections[root]), role: .collapsedRepeat),
                differing: collapsed.differingItems.map { items(section.items[$0]) },
            )
        } else if section.isRepeat {
            if let target = RepeatCollapser.repeatTarget(of: index, in: sections) {
                body = .full(sections[target].items.map(items))
            } else {
                body = .collapsed(
                    line: measurer.paragraph(Self.repeatText(section), role: .collapsedRepeat),
                    differing: [],
                )
            }
        } else {
            body = .full(section.items.map(items))
        }
        let label = name.map { name in detail.map { "\(name) \($0)" } ?? name }
        return MeasuredSection(
            id: section.id,
            label: label,
            name: name,
            labelText: name.map { measurer.paragraph($0, role: .sectionLabel) },
            labelDetail: detail.map { measurer.paragraph($0, role: .labelDetail) },
            continuation: name.map { _ in
                measurer.paragraph(Self.continuationText, role: .labelDetail)
            },
            isChorus: section.kind == .chorus,
            tint: SectionTint(section.kind),
            body: body,
            cues: cues.map { cue in
                MeasuredCue(text: cue.text, paragraph: measurer.paragraph(cue.text, role: .cue))
            },
        )
    }

    private func items(_ item: RenderItem) -> MeasuredItem {
        switch item {
        case let .lyrics(line):
            return .lyric(measurer.line(line))
        case let .comment(text, _, path):
            return .comment(measurer.paragraph(text, role: .comment), path)
        case let .verbatim(source, path):
            let text = Measurer.expandedTabs(source)
            let width = measurer.metrics.width(of: text, role: .verbatim, size: referenceSize)
            return .verbatim(text: text, width: width, path: path)
        case let .stanzaBreak(path):
            return .stanzaBreak(path)
        }
    }

    /// The gutter's second line on the parts of a section split between columns.
    static let continuationText = "(cont.)"

    /// "Repeat chorus", or "Repeat <label>" for a differently named section.
    static func repeatText(_ section: RenderSection) -> String {
        let label = RepeatCollapser.displayLabel(section) ?? "Chorus"
        if label.caseInsensitiveCompare("Chorus") == .orderedSame {
            return "Repeat chorus"
        }
        return "Repeat \(label)"
    }

    /// Cues per section and the cues whose section no longer exists, by the section notes
    /// anchoring rule (`SectionNotes.pin`: display label, case-insensitive, and 1-based
    /// occurrence of that label).
    private func pinCues(_ sections: [RenderSection]) -> ([[SongCue]], [SongCue]) {
        let (pinned, unmatched) = SectionNotes.pin(request.cues, to: sections)
        return (
            pinned.map { $0.map { request.cues[$0] } },
            unmatched.map { request.cues[$0] },
        )
    }

    /// Lyric lines as performed: `{chorus}` repeats count their chorus's lines.
    private func lineCount(_ sections: [RenderSection]) -> Int {
        sections.indices.reduce(0) { total, index in
            let source = sections[index].isRepeat
                ? RepeatCollapser.repeatTarget(of: index, in: sections).map { sections[$0] }
                : sections[index]
            let lines = source?.items.count { item in
                if case .lyrics = item {
                    return true
                }
                return false
            } ?? 0
            return total + lines
        }
    }
}
