// P8-7c (docs/phases/8-workstreams/P8-7-time-model-and-fills.md sections 10, 11.1). What a
// fill span may be, and the generator's context built from the timeline, so the generator
// never reads the `.cho`. Pure.

import Diagrams
import Editing
import MusicTheory

/// Why a run of chords cannot take a fill (section 10), with the capsule's reason.
public enum FillSpanProblem: String, Sendable, Hashable, CaseIterable {
    case tooFewChords
    case tooManyChords
    case silence
    case tooLong

    public var reason: String {
        switch self {
        case .tooFewChords: "Select at least two chords"
        case .tooManyChords: "A fill covers at most 9 chords"
        case .silence: "A fill can't cross N.C."
        case .tooLong: "A fill covers at most 8 bars"
        }
    }
}

public enum FillSpan {
    /// The most bars of departing time (R168 Q11).
    public static let maxBars = 8

    /// Why `chords` (indices into `timeline.chords`, start ... landing) cannot take a fill,
    /// or nil: 2 ... 9 chords, no `N.C.` or unreadable chord, at most 8 bars from the start
    /// onset to the landing onset.
    public static func problem(
        timeline: SongTimeline,
        chords: ClosedRange<Int>,
    ) -> FillSpanProblem? {
        guard chords.lowerBound >= 0, chords.upperBound < timeline.chords.count else {
            return .tooFewChords
        }
        if chords.count < SpanAnchor.chordCount.lowerBound {
            return .tooFewChords
        }
        if chords.count > SpanAnchor.chordCount.upperBound {
            return .tooManyChords
        }
        let span = timeline.chords[chords]
        if span.contains(where: { $0.isSilent || ChordToken(parsing: $0.token).chord == nil }) {
            return .silence
        }
        let bars = span.dropLast().reduce(0.0) { total, chord in
            total + Double(chord.length) / Double(chord.meter.ticksPerBar)
        }
        return bars > Double(maxBars) + 1e-9 ? .tooLong : nil
    }

    /// The generator's facts for `chords` on `timeline` (section 11.1): each chord at concert
    /// pitch through `transform` in the key in effect, its length, meter, bar position and
    /// placed bass on `tuning` around `home`; the feel; whether the landing starts a section
    /// of `sections` (render sections in the timeline's order of origins) and its energy; the
    /// song's scale `mode` (the sidecar's, R170), else the default from the feel and key (a
    /// Bollywood feel in a minor key plans in harmonic minor, R161, R168). nil when the span
    /// has a problem.
    public static func context(
        // swiftlint:disable:previous function_parameter_count
        timeline: SongTimeline,
        chords: ClosedRange<Int>,
        transform: DisplayTransform,
        genre: BassGenre?,
        tuning: Tuning,
        home: Int,
        sections: [RenderSection] = [],
        mode: FillMode? = nil,
    ) -> FillContext? {
        guard problem(timeline: timeline, chords: chords) == nil else { return nil }
        var span: [FillSpanChord] = []
        for chord in timeline.chords[chords] {
            guard let symbol = PartPlay.concert(chord, transform: transform) else { return nil }
            let key = chord.key.map { $0.transposed(by: transform.concertSemitones) }
                ?? transform.concertKey
            let position = timeline.barBeat(at: max(0, chord.onset))
            span.append(FillSpanChord(
                chord: symbol,
                length: chord.length,
                estimated: chord.isEstimated,
                key: key,
                meter: FillMeter(
                    pulses: chord.meter.pulses,
                    ticksPerPulse: chord.meter.ticksPerPulse,
                    compound: chord.meter.isCompound,
                ),
                placed: PartPitch.placedBass(symbol, tuning: tuning, home: home),
                onsetInBar: (position.beat - 1) * chord.meter.ticksPerPulse + position.tick,
            ))
        }
        let last = timeline.chords[chords.upperBound - 1]
        let landing = timeline.chords[chords.upperBound]
        let firstOfPass = timeline.chords.firstIndex { $0.pass == landing.pass } == chords
            .upperBound
        let intoSection = landing.pass != last.pass && firstOfPass
        let content = timeline.passes.indices.contains(landing.pass)
            ? timeline.passes[landing.pass].content : nil
        let energy = intoSection
            ? content
            .flatMap {
                sections.indices.contains($0) ? BassLine.sectionEnergy(sections[$0]) : nil
            }
            : nil
        return FillContext(
            span: span,
            genre: genre,
            tempo: last.tempo,
            mode: FillMode.resolved(mode, genre: genre, key: span.first?.key),
            range: PartPitch.range(of: tuning),
            intoSection: intoSection,
            energyUp: energy,
        )
    }

    /// The span's written positions and basses, what a saved part anchors (`SpanAnchor`).
    public static func anchor(
        timeline: SongTimeline,
        chords: ClosedRange<Int>,
        units: [SongSectionUnit],
        sections: [RenderSection],
    ) -> SpanAnchor? {
        guard problem(timeline: timeline, chords: chords) == nil else { return nil }
        let span = timeline.chords[chords]
        guard let first = span.first, let last = span.last,
              let start = ChordAnchors.anchor(at: first.position, units: units, sections: sections),
              let end = ChordAnchors.anchor(at: last.position, units: units, sections: sections)
        else { return nil }
        let basses = span.compactMap { ChordAnchors.writtenBass($0.token)?.text }
        guard basses.count == span.count else { return nil }
        return SpanAnchor(start: start, end: end, spanBass: basses)
    }
}
