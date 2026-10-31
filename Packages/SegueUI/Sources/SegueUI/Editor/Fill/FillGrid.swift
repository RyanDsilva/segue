// P8-7d (docs/phases/8-workstreams/P8-7-time-model-and-fills.md sections 12.4, 12.5). The fill
// editor's time and pitch frame: the span's chords on the song's timeline, the fill region
// (the departing chords plus the landing bar), its beats and bars, the snaps, and the
// conversion between a drawn note (a tick and a sounding pitch) and a chord-relative
// `PartEvent`.

import Diagrams
import Editing
import Library
import MusicTheory
import Playback

/// The Rhythm snap (section 12.2; default 8th).
enum FillRhythmSnap: String, CaseIterable, Hashable {
    case eighth
    case sixteenth
    case triplet

    var ticks: Int {
        switch self {
        case .eighth: Ticks.eighth
        case .sixteenth: Ticks.sixteenth
        case .triplet: Ticks.perQuarter / 3
        }
    }

    var title: String {
        switch self {
        case .eighth: "8th"
        case .sixteenth: "16th"
        case .triplet: "Triplet"
        }
    }

    /// "an eighth", "a sixteenth", "an eighth triplet".
    var spoken: String {
        switch self {
        case .eighth: "eighth"
        case .sixteenth: "sixteenth"
        case .triplet: "triplet eighth"
        }
    }
}

/// The Pitch snap (default Scale; ⌥ while placing bypasses it).
enum FillPitchSnap: String, CaseIterable, Hashable {
    case chordTones
    case scale
    case chromatic

    var title: String {
        switch self {
        case .chordTones: "Chord tones"
        case .scale: "Scale"
        case .chromatic: "Chromatic"
        }
    }
}

struct FillGrid: Equatable {
    struct Chord: Equatable {
        /// Ticks on the song's timeline.
        var onset: Int
        var length: Int
        /// Concert pitch.
        var symbol: ChordSymbol
        /// As the chart shows it.
        var name: String
        /// The placed bass note a `PartEvent` counts from (MIDI).
        var placed: Int
        var key: SongKey?
        var meter: Meter
    }

    struct Bar: Equatable {
        var tick: Int
        var number: Int
    }

    /// The span, start ... landing.
    var chords: [Chord]
    /// Ticks of the fill region: the span's start through the landing chord's first bar.
    var region: Range<Int>
    /// Every pulse in the region (ticks).
    var pulses: [Int]
    var bars: [Bar]
    var tuning: Tuning
    var home: Int
    var mode: FillMode?

    /// The instrument's range (MIDI).
    var range: ClosedRange<Int> {
        PartPitch.range(of: tuning)
    }

    /// The piano roll's rows: the lowest open string up to G3 (at least an octave above the
    /// highest open string), section 12.5.
    var rollRange: ClosedRange<Int> {
        let low = tuning.strings.min() ?? 28
        let high = max(55, (tuning.strings.max() ?? 43) + 12)
        return low ... high
    }

    static let empty = Self(
        chords: [],
        region: 0 ..< 1,
        pulses: [],
        bars: [],
        tuning: .bassStandard4,
        home: 0,
    )

    /// The grid of `span` (indices into `timeline.chords`) through `transform`, placed on
    /// `tuning` around `home`.
    static func make(
        // swiftlint:disable:previous function_parameter_count
        timeline: SongTimeline,
        span: ClosedRange<Int>,
        transform: DisplayTransform,
        tuning: Tuning,
        home: Int,
        mode: FillMode?,
    ) -> Self {
        guard timeline.chords.indices.contains(span.lowerBound),
              timeline.chords.indices.contains(span.upperBound)
        else { return .empty }
        var chords: [Chord] = []
        for timed in timeline.chords[span] {
            guard let symbol = PartPlay.concert(timed, transform: transform) else {
                return .empty
            }
            chords.append(Chord(
                onset: timed.onset,
                length: timed.length,
                symbol: symbol,
                name: transform.display(ChordToken(parsing: timed.token)),
                placed: PartPitch.placedBass(symbol, tuning: tuning, home: home),
                key: timed.key.map { $0.transposed(by: transform.concertSemitones) }
                    ?? transform.concertKey,
                meter: timed.meter,
            ))
        }
        let region = PhraseBuilder.fillWindow(timeline: timeline, chords: span, notes: [])
        let grid = timeline.grid(in: region)
        let pulses = grid.pulses
        let bars = grid.bars.map { Bar(tick: $0.tick, number: $0.number) }
        return Self(
            chords: chords,
            region: region,
            pulses: pulses,
            bars: bars,
            tuning: tuning,
            home: home,
            mode: mode,
        )
    }

    // MARK: Time

    /// The span chord sounding at `tick` (the landing after its onset).
    func chord(atTick tick: Int) -> Int {
        chords.lastIndex { $0.onset <= tick } ?? 0
    }

    /// `tick` on the rhythm grid.
    func snap(_ tick: Int, to rhythm: FillRhythmSnap) -> Int {
        let step = rhythm.ticks
        let snapped = Int((Double(tick) / Double(step)).rounded()) * step
        return min(max(snapped, region.lowerBound), region.upperBound - 1)
    }

    /// The step columns of `rhythm` across the region (their start ticks).
    func columns(_ rhythm: FillRhythmSnap) -> [Int] {
        let step = rhythm.ticks
        var first = (region.lowerBound + step - 1) / step * step
        if first > region.lowerBound, !region.lowerBound.isMultiple(of: step) {
            first = region.lowerBound
        }
        return Array(stride(from: first, to: region.upperBound, by: step))
    }

    /// "Bar 2 beat 4 and" for `tick`.
    func spokenPosition(_ tick: Int, timeline: SongTimeline) -> String {
        let position = timeline.barBeat(at: max(0, tick))
        let meter = chords.indices.contains(chord(atTick: tick))
            ? chords[chord(atTick: tick)].meter : .common
        var text = "bar \(position.bar) beat \(position.beat)"
        let pulse = meter.ticksPerPulse
        switch position.tick {
        case 0: break
        case pulse / 2: text += " and"
        case pulse / 4: text += " e"
        case pulse * 3 / 4: text += " a"
        case pulse / 3: text += " trip"
        case pulse * 2 / 3: text += " let"
        default: text += " plus \(position.tick) ticks"
        }
        return text.prefix(1).uppercased() + text.dropFirst()
    }

    // MARK: Events

    /// The tick a part event starts at.
    func tick(of event: PartEvent) -> Int {
        guard chords.indices.contains(event.chord) else { return region.lowerBound }
        return chords[event.chord].onset + event.at
    }

    /// The sounding pitch of a part event, before folding into the range.
    func rawMidi(of event: PartEvent) -> Int {
        guard chords.indices.contains(event.chord) else { return 0 }
        return chords[event.chord].placed + event.semitones
    }

    /// The sounding pitch, folded into the instrument's range.
    func midi(of event: PartEvent) -> Int {
        PartPitch.fold(rawMidi(of: event), into: range)
    }

    /// Whether the event was moved an octave into range.
    func isFolded(_ event: PartEvent) -> Bool {
        !range.contains(rawMidi(of: event))
    }

    /// Whether it starts past its chord's end (drawn with a warning, never moved).
    func isOutside(_ event: PartEvent) -> Bool {
        guard chords.indices.contains(event.chord), event.chord < chords.count - 1 else {
            return false
        }
        return event.at >= chords[event.chord].length
    }

    /// The event for a note starting at `tick` for `length` ticks at `midi`, pinned to
    /// `pin` (an open string's name), counted from the chord sounding at `tick`; keeps the
    /// articulations and velocity of `like`.
    func event(
        tick: Int,
        length: Int,
        midi: Int,
        pin: String? = nil,
        like: PartEvent? = nil,
    ) -> PartEvent {
        let index = chord(atTick: tick)
        let chord = chords.indices.contains(index) ? chords[index] : nil
        let semitones = min(max(midi - (chord?.placed ?? midi), -24), 35)
        var event = PartEvent.relative(
            chord: index,
            at: max(0, tick - (chord?.onset ?? tick)),
            len: max(1, length),
            semitones: semitones,
            velocity: like?.velocity,
            articulations: like?.articulations ?? [],
        )
        event.string = pin
        return event
    }

    // MARK: Pitch

    /// The open-string name a pin stores ("A1", "B0").
    func pin(string: Int) -> String? {
        guard tuning.strings.indices.contains(string) else { return nil }
        return Self.pitchName(tuning.strings[string])
    }

    /// "A1" for MIDI 33 (sharps).
    static func pitchName(_ midi: Int) -> String {
        let names = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]
        return names[((midi % 12) + 12) % 12] + String(midi / 12 - 1)
    }

    /// Where `event` is played: its pin when the tuning has that string, else the position
    /// nearest the hand.
    func position(of event: PartEvent) -> FretPosition? {
        PartPitch.position(midi(of: event), pin: event.string, tuning: tuning, home: home)
    }

    /// The pitch classes the Pitch snap allows over span chord `index`.
    func allowed(_ snap: FillPitchSnap, chord index: Int) -> Set<PitchClass>? {
        guard chords.indices.contains(index) else { return nil }
        let chord = chords[index]
        switch snap {
        case .chromatic: return nil
        case .chordTones: return Set(chord.symbol.tones.pitchClasses)
        case .scale:
            return Set(FillSpelling.passScale(chord.symbol, key: chord.key, mode: mode).keys)
        }
    }

    /// `midi` moved to the nearest pitch the snap allows over the chord at `tick` (ties go
    /// down), kept in the piano roll's rows.
    func snapPitch(_ midi: Int, _ snap: FillPitchSnap, atTick tick: Int) -> Int {
        let rows = rollRange
        let clamped = min(max(midi, rows.lowerBound), rows.upperBound)
        guard let allowed = allowed(snap, chord: chord(atTick: tick)), !allowed.isEmpty else {
            return clamped
        }
        for distance in 0 ... 12 {
            for candidate in [clamped - distance, clamped + distance]
                where rows.contains(candidate) && allowed.contains(PitchClass(midi: candidate))
            {
                return candidate
            }
        }
        return clamped
    }

    /// The next pitch from `midi` in `direction` (+1 up, -1 down) the snap allows over the
    /// chord at `tick`.
    func step(_ midi: Int, by direction: Int, _ snap: FillPitchSnap, atTick tick: Int) -> Int {
        let allowed = allowed(snap, chord: chord(atTick: tick))
        var candidate = midi + direction
        while rollRange.contains(candidate) {
            if allowed?.contains(PitchClass(midi: candidate)) ?? true {
                return candidate
            }
            candidate += direction
        }
        return midi
    }

    /// The chord's tones on frets 0 ... 15, labelled by degree (the neck's tint).
    func neckTones(chord index: Int) -> [NeckTone] {
        guard chords.indices.contains(index) else { return [] }
        return BassFretboard.tones(of: chords[index].symbol, frets: 0 ... 15, tuning: tuning)
    }
}
