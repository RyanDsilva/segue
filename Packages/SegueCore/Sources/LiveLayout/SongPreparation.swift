// Owner: unit B, P8-2. Turns a layout request into measured passes: every part written out
// in full (R147), each shown pass in its show mode (R149), cues pinned to their sections,
// unmatched cues moved to the notes.

import ChordPro
import Editing
import Foundation
import Library

struct SongPreparation {
    let request: LayoutRequest
    let measurer: Measurer

    /// The song, or a medley's segments one after another (P9-3 9.1): each measured as a
    /// song, pass ids numbered through the whole plan, a member header on each segment's
    /// first pass. The first segment's notes sit at the top as for a song; a later member's
    /// notes go in its header.
    func measure() -> MeasuredSong {
        let segments = request.resolvedSegments
        guard segments.count > 1 || segments.first?.header != nil else {
            return measure(segments.first ?? LayoutSegment(model: request.model))
        }
        var result = MeasuredSong(notes: [], sections: [], lineCount: 0)
        for (index, segment) in segments.enumerated() {
            var song = measure(
                segment,
                next: index + 1 < segments.count ? segments[index + 1] : nil,
            )
            let offset = result.sections.count
            for position in song.sections.indices {
                song.sections[position].id += offset
                song.sections[position].segment = index
            }
            if let header = segment.header, !song.sections.isEmpty {
                song.sections[0].header = MeasuredHeader(
                    header: header,
                    // Led by "↳", so the transition never relies on colour alone (9.2).
                    transition: header.transition.map {
                        measurer.paragraph("\u{21B3} " + $0, role: .cue)
                    },
                    notes: index == 0 ? [] : song.notes,
                    rule: index > 0,
                )
            }
            if index == 0 {
                result.notes = song.notes
            }
            result.sections += song.sections
            result.lineCount += song.lineCount
        }
        return result
    }

    /// One song or member; `next` is the member after it in a medley, whose first chord the
    /// last chord walks up into (P9-3 9.1).
    private func measure(_ segment: LayoutSegment, next: LayoutSegment? = nil) -> MeasuredSong {
        let original = segment.model.sections
        let units = SongSections.units(of: original)
        // Cues pin to the song's own sections (song-relative label + occurrence) before the
        // passes reorder them; a cue shows on its part's first shown pass only, and a cue on
        // a part that is only skipped is simply not played (not "unmatched").
        let (pinned, unmatched) = pinCues(original, cues: segment.cues)
        let order = segment.passes ?? ArrangementResolver.fullSong(units)
        var arranged = ArrangedSections.build(original, order: order)
        // Counted before singer view drops anything, so both views scroll at one speed.
        let lineCount = arranged.reduce(0) { $0 + Self.lyricLines($1.section.items) }
        let singer = request.view == .singer
        if singer {
            // Lyrics only (P9-2 6.2): each pass through the singer transform, never walk-ups.
            for index in arranged.indices {
                arranged[index].section = SingerView.section(arranged[index].section)
            }
        } else if let walkUps = segment.walkUps {
            // Each pass gets the walk-up into what actually follows it (P8-4b section 8.6).
            let annotated = BassLine.annotate(
                arranged.map(\.section),
                origins: arranged.map(\.source),
                context: walkUps,
            )
            for index in arranged.indices {
                arranged[index].section = annotated[index]
            }
            boundaryWalkUp(&arranged, context: walkUps, into: next)
        }
        let titles = arranged.map { pass in
            units.first { $0.index == pass.source }?.title ?? ""
        }
        let names = PassNaming.names(
            titles: titles,
            shown: Array(repeating: true, count: arranged.count),
        )
        let measured = arranged.indices.map { index in
            section(
                arranged[index],
                name: names[index],
                cues: arranged[index].isFirstShown ? pinned[arranged[index].source] : [],
            )
        }
        // Singer view lays out no notes block: song and slot notes are player reminders (R178).
        var notes = (singer ? [] : segment.notes)
            .flatMap { $0.components(separatedBy: .newlines) }
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        notes += unmatched.map { "\($0.section): \($0.text)" }
        return MeasuredSong(
            notes: notes.map { measurer.paragraph($0, role: .note) },
            sections: measured,
            lineCount: lineCount,
        )
    }

    /// The walk-up from the member's last chord into the next member's first, planned in
    /// the next member's key (R178, R169); none without the next member's walk-ups.
    private func boundaryWalkUp(
        _ arranged: inout [ArrangedSection],
        context: BassLineContext,
        into next: LayoutSegment?,
    ) {
        guard let next, let nextContext = next.walkUps else { return }
        let units = SongSections.units(of: next.model.sections)
        let following = ArrangedSections.build(
            next.model.sections,
            order: next.passes ?? ArrangementResolver.fullSong(units),
        )
        let drawn = BassLine.annotateBoundary(
            MemberPasses(
                sections: arranged.map(\.section),
                origins: arranged.map(\.source),
                context: context,
            ),
            into: MemberPasses(
                sections: following.map(\.section),
                origins: following.map(\.source),
                context: nextContext,
            ),
        )
        for index in arranged.indices {
            arranged[index].section = drawn[index]
        }
    }

    private func section(
        _ pass: ArrangedSection,
        name passName: PassName,
        cues: [SongCue],
    ) -> MeasuredSection {
        let section = pass.section
        // A Chords only pass reads as First line in singer view, its tag kept (R178).
        let shownMode = request.view == .singer ? pass.mode.singer : pass.mode
        let name = SectionNotes.label(of: section)
        let tag: String? = switch pass.mode {
        case .chordsOnly: "CHORDS"
        case .firstLine: "1ST LINE"
        case .full, .skip: nil
        }
        return MeasuredSection(
            id: section.id,
            source: pass.source,
            position: pass.position,
            label: name,
            name: name,
            labelText: name.map { measurer.paragraph($0, role: .sectionLabel) },
            badge: name.flatMap { _ in passName.badgeText }
                .map { measurer.paragraph($0, role: .passBadge) },
            modeTag: tag.map { measurer.paragraph($0, role: .modeTag) },
            continuation: name.map { _ in
                measurer.paragraph(Self.continuationText, role: .labelDetail)
            },
            isChorus: section.kind == .chorus,
            tint: SectionTint(section.kind),
            kind: section.kind,
            mode: pass.mode,
            passName: passName,
            items: items(section.items, mode: shownMode),
            cues: cues.map { cue in
                MeasuredCue(text: cue.text, paragraph: measurer.paragraph(cue.text, role: .cue))
            },
            renderItems: section.items,
        )
    }

    /// The part's items as the show mode presents them (P8-2 section 6.3).
    private func items(_ items: [RenderItem], mode: PassMode) -> [MeasuredItem] {
        switch mode {
        case .full, .skip: items.map(item)
        case .chordsOnly: chordsOnly(items)
        case .firstLine: firstLine(items)
        }
    }

    /// Each chorded lyric line as a chord row; chordless lyric lines dropped (and the breaks
    /// around them collapsed to one); comments and tab lines kept.
    private func chordsOnly(_ items: [RenderItem]) -> [MeasuredItem] {
        var result: [MeasuredItem] = []
        for item in items {
            switch item {
            case let .lyrics(line):
                if !line.chords.isEmpty {
                    result.append(.chordRow(measurer.line(line).chords, line.path))
                }
            case .stanzaBreak:
                if case .stanzaBreak = result.last {
                    continue
                }
                result.append(self.item(item))
            case .comment, .fillTab, .verbatim:
                result.append(self.item(item))
            }
        }
        while case .stanzaBreak = result.first {
            result.removeFirst()
        }
        while case .stanzaBreak = result.last {
            result.removeLast()
        }
        return result
    }

    /// The comments before the first line, the first line, then "+ N more lines".
    private func firstLine(_ items: [RenderItem]) -> [MeasuredItem] {
        guard let first = Self.firstLineIndex(items) else { return items.map(item) }
        var result: [MeasuredItem] = items[..<first].compactMap { item in
            if case .comment = item {
                return self.item(item)
            }
            return nil
        }
        result.append(item(items[first]))
        // A fill whose tab sits under the first line still shows.
        var next = first + 1
        while next < items.count, case .fillTab = items[next] {
            result.append(item(items[next]))
            next += 1
        }
        let more = items[(first + 1)...].count(where: Self.isLine)
        if more > 0 {
            let text = more == 1
                ? "+ 1 more line (first line only)"
                : "+ \(more) more lines (first line only)"
            result.append(.moreLines(measurer.paragraph(text, role: .moreLines)))
        }
        return result
    }

    /// The first lyric line with words; else the first lyric or verbatim line.
    private static func firstLineIndex(_ items: [RenderItem]) -> Int? {
        items.firstIndex { item in
            if case let .lyrics(line) = item {
                return !line.lyrics.trimmingCharacters(in: .whitespaces).isEmpty
            }
            return false
        } ?? items.firstIndex(where: isLine)
    }

    /// A performed line (lyric or tab/grid), as opposed to a comment or a break.
    private static func isLine(_ item: RenderItem) -> Bool {
        switch item {
        case .lyrics, .verbatim: true
        case .comment, .fillTab, .stanzaBreak: false
        }
    }

    private func item(_ item: RenderItem) -> MeasuredItem {
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
        case let .fillTab(block):
            return .fillTab(block, height: PlacedFillTab.baseHeight(for: block.tuning))
        }
    }

    /// The gutter's second line on the parts of a section split between columns.
    static let continuationText = "(cont.)"

    /// Cues per section and the cues whose section no longer exists, by the section notes
    /// anchoring rule (`SectionNotes.pin`: display label, case-insensitive, and 1-based
    /// occurrence of that label).
    private func pinCues(_ sections: [RenderSection], cues: [SongCue])
        -> ([[SongCue]], [SongCue])
    {
        let (pinned, unmatched) = SectionNotes.pin(cues, to: sections)
        return (
            pinned.map { $0.map { cues[$0] } },
            unmatched.map { cues[$0] },
        )
    }

    /// Lyric lines as performed (the tempo scroll estimate): every shown pass counts all of
    /// its part's lyric lines, whatever its mode; `{chorus}` repeats are already written out.
    private static func lyricLines(_ items: [RenderItem]) -> Int {
        items.count { item in
            if case .lyrics = item {
                return true
            }
            return false
        }
    }
}
