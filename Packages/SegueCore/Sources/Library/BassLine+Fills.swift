// P8-7e (docs/phases/8-workstreams/P8-7-time-model-and-fills.md section 14, R167 Q12, R168
// Q5, Q8, R175). Saved fills drawn on a chart in the bass-note view, whatever the walk-up
// density: note names after the chord units of the span, or a mini tab block under the line
// holding the span's first chord, in every pass the fill applies to. Pure; worked out once
// per render model or stage plan.

import ChordPro
import Diagrams
import Editing
import MusicTheory

extension BassLine {
    /// `sections` (in the order of `timeline`'s passes: pass `i` is `sections[i]`) with the
    /// applied fills of `context` drawn: on each departing chord of a play its `FillRun`
    /// (the walk-up there cleared), and, for a fill shown as tab (its own choice, "Fills as
    /// tab", or a span starting in a grid), one `.fillTab` item after the start chord's line
    /// with the runs kept for the stage neck only (`FillRun.inTab`).
    static func drawFills(
        _ sections: [RenderSection],
        timeline: SongTimeline,
        context: BassLineContext,
    ) -> [RenderSection] {
        guard !context.parts.applied.isEmpty, let bass = context.transform.options.bass
        else { return sections }
        let plays = context.parts.plays(in: timeline)
        guard !plays.isEmpty else { return sections }
        let drawing = FillDrawing(
            timeline: timeline,
            context: context,
            tuning: bass.tuning,
            allTab: bass.fillsAsTab,
        )
        var result = sections
        var tabs: [FillDrawing.Tab] = []
        for play in plays {
            let notes = play.resolve(
                timeline: timeline,
                transform: context.transform,
                tuning: drawing.tuning,
                home: drawing.home,
            ).filter { !$0.outside }
            guard let start = drawing.place(of: play.chords.lowerBound, in: result) else {
                continue
            }
            let asTab = drawing.allTab || play.part.show == .tab || start.chord == nil
            if asTab {
                tabs.append(FillDrawing.Tab(
                    section: start.section,
                    item: start.item,
                    block: drawing.tab(play, notes: notes),
                ))
            }
            for (ordinal, run) in drawing.runs(play, notes: notes).enumerated() {
                guard var run,
                      let place = drawing.place(of: play.chords.lowerBound + ordinal, in: result),
                      let chord = place.chord,
                      case var .lyrics(line) = result[place.section].items[place.item]
                else { continue }
                run.inTab = asTab
                line.chords[chord].fill = run
                line.chords[chord].approach = nil
                result[place.section].items[place.item] = .lyrics(line)
            }
        }
        FillDrawing.insert(tabs, into: &result)
        return result
    }
}

/// What drawing a song's fills needs, worked out once.
private struct FillDrawing {
    /// Where a timeline chord is drawn: its section and item, and its index among the line's
    /// chords (nil for a grid chord, drawn verbatim).
    struct Place {
        var section: Int
        var item: Int
        var chord: Int?
    }

    /// A tab block to insert after item `item` of section `section`.
    struct Tab {
        var section: Int
        var item: Int
        var block: FillTabBlock
    }

    let timeline: SongTimeline
    let context: BassLineContext
    let tuning: Tuning
    let allTab: Bool
    /// The song's hand position, as the stage neck and play-along place the bass.
    let home: Int

    init(timeline: SongTimeline, context: BassLineContext, tuning: Tuning, allTab: Bool) {
        self.timeline = timeline
        self.context = context
        self.tuning = tuning
        self.allTab = allTab
        let tonic = context.key?.tonic.pitchClass ?? timeline.chords.lazy
            .filter { !$0.isSilent }
            .compactMap { PartPlay.concert($0, transform: context.transform) }
            .first.map { ($0.bass ?? $0.root).pitchClass }
        home = tonic.map { BassFretboard.homeFret(tonic: $0, tuning: tuning) } ?? 0
    }

    /// The concert key in effect at a timeline chord.
    func key(at chord: TimedChord) -> SongKey? {
        context.concertKey(written: chord.key)
    }

    /// Where timeline chord `index` sits in `sections`: the item on its line in its pass's
    /// section, and the line's chord it is (the k-th `.chord` there, k counting the chords
    /// timed before it on that line in that pass).
    func place(of index: Int, in sections: [RenderSection]) -> Place? {
        guard timeline.chords.indices.contains(index) else { return nil }
        let timed = timeline.chords[index]
        guard sections.indices.contains(timed.pass) else { return nil }
        let items = sections[timed.pass].items
        for (itemIndex, item) in items.enumerated() {
            switch item {
            case let .lyrics(line) where line.path == timed.line:
                var before = 0
                var cursor = index - 1
                while cursor >= 0, timeline.chords[cursor].pass == timed.pass,
                      timeline.chords[cursor].line == timed.line
                {
                    if !timeline.chords[cursor].isSilent {
                        before += 1
                    }
                    cursor -= 1
                }
                let chords = line.chords.indices.filter { line.chords[$0].kind == .chord }
                guard chords.indices.contains(before) else { return nil }
                return Place(section: timed.pass, item: itemIndex, chord: chords[before])
            case let .verbatim(_, path) where path == timed.line:
                return Place(section: timed.pass, item: itemIndex, chord: nil)
            default:
                continue
            }
        }
        return nil
    }

    /// The run over each departing chord of `play` (nil where no note sounds over it),
    /// numbered across the whole fill.
    func runs(_ play: PartPlay, notes: [ResolvedNote]) -> [FillRun?] {
        let span = Array(timeline.chords[play.chords])
        let departing = span.count - 1
        guard departing > 0 else { return [] }
        var byChord = [[ResolvedNote]](repeating: [], count: departing)
        for note in notes {
            let ordinal = play.part.events[note.event].chord
            if ordinal < departing {
                byChord[ordinal].append(note)
            }
        }
        let total = byChord.reduce(0) { $0 + $1.count }
        let landing = PartPlay.concert(span[departing], transform: context.transform)
        let into = landing.map { ($0.bass ?? $0.root).chartName }
        let lastSounding = byChord.lastIndex { !$0.isEmpty }
        var number = 1
        return byChord.enumerated().map { ordinal, notes -> FillRun? in
            guard !notes.isEmpty,
                  let symbol = PartPlay.concert(span[ordinal], transform: context.transform)
            else { return nil }
            defer { number += notes.count }
            let key = key(at: span[ordinal])
            let scale = FillSpelling.passScale(symbol, key: key, mode: context.mode)
            let pitches = notes.map { PitchClass(midi: $0.midi) }
            let degrees = context.transform.options.nashville
                ? key.map { key in pitches.map { Nashville.degree(of: $0, in: key) } } : nil
            let isLast = ordinal == lastSounding
            return FillRun(
                part: play.part.id.description,
                notes: degrees ?? notes.map(\.name),
                chromatic: pitches.map { scale[$0] == nil },
                isLast: isLast,
                accessibility: Self.spoken(
                    notes.map(\.name),
                    into: isLast ? into : nil,
                ),
                pitches: pitches,
                pins: notes.map { note in
                    play.part.events[note.event].string == nil ? nil : note.position
                },
                firstNumber: number,
                total: total,
            )
        }
    }

    /// "fill: E, F sharp, G sharp into A".
    static func spoken(_ names: [String], into: String?) -> String {
        "fill: " + names.map(BassLine.spokenNote).joined(separator: ", ")
            + (into.map { " into " + BassLine.spokenNote($0) } ?? "")
    }

    /// `play` as a mini tab: its notes and the landing root, over the fill's window, with
    /// the chord names at their onsets.
    func tab(_ play: PartPlay, notes: [ResolvedNote]) -> FillTabBlock {
        let region = PartPlay.window(timeline: timeline, chords: play.chords, notes: notes)
        let grid = timeline.grid(in: region)
        let landing = timeline.chords[play.chords.upperBound]
        var tabNotes = notes.map { TabNote($0) }
        if let symbol = PartPlay.concert(landing, transform: context.transform) {
            tabNotes = PartPlay.tabNotes(
                notes,
                landing: symbol,
                onset: landing.onset,
                region: region,
                tuning: tuning,
                home: home,
            )
        }
        return FillTabBlock(
            part: play.part.id.description,
            notes: tabNotes,
            chords: timeline.chords[play.chords].map { chord in
                FillTabChord(
                    tick: max(chord.onset, region.lowerBound),
                    name: context.transform.display(ChordToken(parsing: chord.token)),
                )
            },
            ticks: region,
            pulses: grid.pulses,
            bars: grid.bars.map(\.tick),
            tuning: tuning,
            accessibility: TabLayout.spoken(tabNotes, tuning: tuning),
        )
    }

    /// `tabs` inserted into `sections`, last to first so earlier indices hold; two tabs after
    /// one line keep their played order.
    static func insert(_ tabs: [Tab], into sections: inout [RenderSection]) {
        let ordered = tabs.enumerated().sorted { lhs, rhs in
            (lhs.element.section, lhs.element.item, lhs.offset)
                > (rhs.element.section, rhs.element.item, rhs.offset)
        }
        for tab in ordered.map(\.element) {
            let items = sections[tab.section].items
            sections[tab.section].items.insert(
                .fillTab(tab.block),
                at: insertion(after: tab.item, in: items),
            )
        }
    }

    /// Where a tab goes after item `index`: right after a lyric line; after the last line of
    /// a grid (its consecutive verbatim lines).
    static func insertion(after index: Int, in items: [RenderItem]) -> Int {
        var next = index + 1
        if case .verbatim = items[index] {
            while next < items.count, case .verbatim = items[next] {
                next += 1
            }
        }
        return next
    }
}
