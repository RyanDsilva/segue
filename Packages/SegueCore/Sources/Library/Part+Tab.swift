// P8-7d (docs/phases/8-workstreams/P8-7-time-model-and-fills.md section 12.6): a resolved note
// as the mini tab's input. Pure.

import Diagrams
import MusicTheory

public extension TabNote {
    /// `note` as drawn in a mini tab; `isLanding` marks the landing chord's root.
    init(_ note: ResolvedNote, isLanding: Bool = false) {
        self.init(
            tick: note.tick,
            length: note.len,
            position: note.position,
            articulations: note.articulations,
            name: note.name,
            isLanding: isLanding,
        )
    }
}

public extension PartPlay {
    /// The ticks a fill is shown and heard over (sections 12.3, 12.6): from the bar before
    /// its first note (never before the span's start) through the landing chord's first bar.
    /// `chords` are indices into `timeline.chords`, start ... landing.
    static func window(
        timeline: SongTimeline,
        chords: ClosedRange<Int>,
        notes: [ResolvedNote],
    ) -> Range<Int> {
        guard timeline.chords.indices.contains(chords.lowerBound),
              timeline.chords.indices.contains(chords.upperBound)
        else { return 0 ..< 0 }
        let start = timeline.chords[chords.lowerBound].onset
        let first = notes.filter { !$0.outside }.map(\.tick).min() ?? start
        let bar = timeline.barBeat(at: max(0, first)).bar
        let before = timeline.tick(of: BarBeat(bar: max(1, bar - 1), beat: 1, tick: 0))
        let from = max(start, min(before, first))
        let landing = timeline.chords[chords.upperBound]
        let downbeat = landing.onset + (landing.push?.ticks ?? 0)
        let landingBar = timeline.barBeat(at: max(0, downbeat)).bar
        var through = timeline.tick(of: BarBeat(bar: landingBar + 1, beat: 1, tick: 0))
        through = min(max(through, landing.onset + 1), max(timeline.totalTicks, landing.onset + 1))
        return from ..< max(from + 1, through)
    }

    /// What a mini tab draws (section 12.6): `notes` (those past their chord's end left out),
    /// then the landing chord's root in the landing bar, at its onset (or the region's start)
    /// unless a note already starts there. The fill editor and the stage both use it.
    static func tabNotes(
        // swiftlint:disable:previous function_parameter_count
        _ notes: [ResolvedNote],
        landing: ChordSymbol,
        onset: Int,
        region: Range<Int>,
        tuning: Tuning,
        home: Int,
    ) -> [TabNote] {
        let drawn = notes.filter { !$0.outside }.map { TabNote($0) }
        let tick = max(onset, region.lowerBound)
        guard !drawn.contains(where: { $0.tick == tick }) else { return drawn }
        let placed = PartPitch.placedBass(landing, tuning: tuning, home: home)
        return drawn + [TabNote(
            tick: tick,
            length: max(1, region.upperBound - tick),
            position: PartPitch.position(placed, pin: nil, tuning: tuning, home: home),
            name: (landing.bass ?? landing.root).chartName,
            isLanding: true,
        )]
    }
}

public extension SongTimeline {
    /// Every pulse in `region` (ticks) and every bar starting in it (its tick and 1-based
    /// number): a fill's beat ruler and bar lines.
    func grid(in region: Range<Int>) -> (pulses: [Int], bars: [(tick: Int, number: Int)]) {
        var pulses: [Int] = []
        var bars: [(tick: Int, number: Int)] = []
        var tick = region.lowerBound - region.lowerBound % Ticks.sixteenth
        while tick < region.upperBound {
            let position = barBeat(at: tick)
            if tick >= region.lowerBound, position.tick == 0 {
                pulses.append(tick)
                if position.beat == 1 {
                    bars.append((tick: tick, number: position.bar))
                }
            }
            tick += Ticks.sixteenth
        }
        return (pulses, bars)
    }
}
