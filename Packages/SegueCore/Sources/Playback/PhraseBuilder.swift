// P8-6 (docs/phases/8-workstreams/P8-6-audio.md section 6.3, R161, R162): the phrases the
// app plays, built from concert chords on the metronome's beat model. Pure.

import Foundation
import Library
import MusicTheory
import Shows

public enum PhraseBuilder {
    /// Seconds between strummed strings, low to high.
    public static let strumGap: TimeInterval = 0.025
    /// How long a heard chord rings.
    public static let chordLength: TimeInterval = 1.6
    /// How long a heard bass note rings.
    public static let bassNoteLength: TimeInterval = 1.2
    /// The audition tempo without `{tempo}`.
    public static let defaultTempo: Double = 90
    public static let chordVelocity: UInt8 = 80
    public static let bassVelocity: UInt8 = 96

    /// A chord (block, or strummed low to high) with its bass note underneath.
    public static func chord(
        _ chord: ChordSymbol,
        sound: ChordSound,
        style: ChordStyle,
        bass: UInt8?,
    ) -> Phrase {
        var events = strike(chord, sound: sound, style: style, at: 0, length: chordLength)
        if let bass {
            events.append(NoteEvent(
                voice: .bass,
                note: bass,
                velocity: bassVelocity,
                onset: 0,
                duration: chordLength,
            ))
        }
        return Phrase(events: events, length: chordLength)
    }

    /// A bass note alone.
    public static func bassNote(_ note: UInt8) -> Phrase {
        Phrase(
            events: [NoteEvent(
                voice: .bass,
                note: note,
                velocity: bassVelocity,
                onset: 0,
                duration: bassNoteLength,
            )],
            length: bassNoteLength,
        )
    }

    /// A walk-up audition [A3]: two bars at `tempo`. Bar 1: chord A on beat 1, bass A on
    /// beat 1 (and on the middle strong beat in a four-pulse bar unless a walk note takes
    /// it), the candidate's notes one per beat on the bar's last beats (subdivided from the
    /// last beat back when there are more notes than free beats). Bar 2: chord B and bass B
    /// on beat 1, held to the end. `candidate` nil or `hold`: the change with no walk-up.
    /// Each walk note (and B's bass after a walk) sits in the octave nearest the note
    /// before it, so the line moves stepwise. No click.
    public static func audition(
        _ change: ChordChange,
        candidate: WalkUpCandidate?,
        tempo: Double?,
        meter: MetronomeMeter,
        voices: PlaybackVoices,
    ) -> Phrase {
        let placement = voices.placement
        let interval = 60 / (tempo.flatMap { $0 > 0 ? $0 : nil } ?? defaultTempo)
        let pulses = max(1, meter.pulses)
        let bar = Double(pulses) * interval
        let from = ChordSymbol(parsing: change.fromName)
        let to = ChordSymbol(parsing: change.toName)
        var events: [NoteEvent] = []
        if let from {
            events += strike(from, sound: voices.sound, style: voices.style, at: 0, length: bar)
        }
        if let to {
            events += strike(to, sound: voices.sound, style: voices.style, at: bar, length: bar)
        }

        let walk = candidate.flatMap { $0.kind == .hold ? nil : $0 }?.offsets ?? []
        let slots = walkSlots(count: walk.count, pulses: pulses, compound: meter.isCompound)
            .map { $0 * interval }
        let bassA = from.map { Voicing.bassNote(of: $0, placement: placement) }
        var bassB = to.map { Voicing.bassNote(of: $0, placement: placement) }

        // Bar 1's bass: beat 1, the middle strong beat of a four-pulse bar when free.
        var bassOnsets: [(TimeInterval, UInt8)] = []
        if let bassA {
            bassOnsets.append((0, bassA))
            let middle = Double(pulses / 2) * interval
            if pulses == 4, !slots.contains(where: { abs($0 - middle) < 1e-9 }),
               slots.allSatisfy({ $0 > middle })
            {
                bassOnsets.append((middle, bassA))
            }
        }
        if let target = bassB, !walk.isEmpty {
            var previous = Int(bassA ?? target)
            for (slot, offset) in zip(slots, walk) {
                let note = nearest(Int(target) + offset, to: previous)
                bassOnsets.append((slot, UInt8(clamping: note)))
                previous = note
            }
            // B lands a step from the last walk note (`offsets.last` semitones from B).
            bassB = UInt8(clamping: previous - (walk.last ?? 0))
        }
        if let bassB {
            bassOnsets.append((bar, bassB))
        }
        events += held(bassOnsets, until: 2 * bar)
        return Phrase(events: events, length: 2 * bar)
    }

    /// Bass notes at their onsets, each held to the next one (the last to `end`).
    static func held(_ onsets: [(TimeInterval, UInt8)], until end: TimeInterval) -> [NoteEvent] {
        onsets.enumerated().map { index, entry in
            let next = index + 1 < onsets.count ? onsets[index + 1].0 : end
            return NoteEvent(
                voice: .bass,
                note: entry.1,
                velocity: bassVelocity,
                onset: entry.0,
                duration: next - entry.0,
            )
        }
    }

    /// The pulse offsets (from bar 1's start) of `count` walk notes ending at the bar's
    /// end: one per pulse on the last free pulses (pulse 1 is never free); with more notes
    /// than free pulses the last pulse splits into eighths (three in a compound meter),
    /// then the one before it, and so on.
    static func walkSlots(count: Int, pulses: Int, compound: Bool) -> [Double] {
        guard count > 0 else { return [] }
        let split = compound ? 3 : 2
        let free = max(1, pulses - 1)
        // Each free pulse, last first: how many slots it holds.
        var divisions = Array(repeating: 1, count: free)
        var total = free
        var index = free - 1
        while total < count, index >= 0 {
            total += split - 1
            divisions[index] = split
            index -= 1
        }
        var slots: [Double] = []
        for (offset, parts) in divisions.enumerated() {
            let start = Double(pulses - free + offset)
            for part in 0 ..< parts {
                slots.append(start + Double(part) / Double(parts))
            }
        }
        return Array(slots.suffix(count))
    }

    /// The chord voice struck at `onset` for `length` seconds.
    static func strike(
        _ chord: ChordSymbol,
        sound: ChordSound,
        style: ChordStyle,
        at onset: TimeInterval,
        length: TimeInterval,
    ) -> [NoteEvent] {
        Voicing.chord(chord, sound: sound).enumerated().map { index, note in
            let delay = style == .strum ? Double(index) * strumGap : 0
            return NoteEvent(
                voice: .chord,
                note: note,
                velocity: chordVelocity,
                onset: onset + delay,
                duration: length - delay,
            )
        }
    }

    /// `pitch` moved by octaves to sit nearest `reference` (ties go down).
    static func nearest(_ pitch: Int, to reference: Int) -> Int {
        var note = pitch
        while note - reference > 6 {
            note -= 12
        }
        while reference - note > 6 {
            note += 12
        }
        return note
    }
}
