// P8-6b (docs/phases/8-workstreams/P8-6-audio.md section 7.5, R162 Q5-Q7, R167 Q8, R168 Q4).
// A play-along timeline as note events: roots on the strong beats plus the shown walk-up,
// chords struck on each downbeat, the click on every beat, fills in place of the bass line,
// and a one-bar count-in. Every position is a tick of the `SongTimeline` slice; seconds come
// from its tempo map times the session factor. Pure.

import Foundation
import Library
import MusicTheory
import Shows

extension PhraseBuilder {
    /// The click tick's velocity and length.
    public static let clickVelocity: UInt8 = 100
    public static let clickLength: TimeInterval = 0.05

    /// `timeline` as events with the toggled `voices`, at every `{tempo}` times `factor`.
    /// With `countIn`, one bar of click (always, whatever the Click toggle) comes first and
    /// every other event moves later by it.
    public static func playAlong(
        _ timeline: PlayAlongTimeline,
        voices: Set<VoiceToggle>,
        sound: ChordSound,
        style: ChordStyle,
        factor: Double = 1,
        countIn: Bool,
    ) -> Phrase {
        let clock = timeline.clock(factor: factor)
        let grid = PulseGrid(timeline.timeline)
        var events: [NoteEvent] = []
        if voices.contains(.chords) {
            events += chordEvents(timeline, grid: grid, clock: clock, sound: sound, style: style)
        }
        if voices.contains(.bass) {
            let notes = bassLine(timeline, grid: grid, walkUps: voices.contains(.walkUps))
            events += notes.map { note in
                let onset = clock.seconds(note.tick)
                return NoteEvent(
                    voice: .bass,
                    note: note.midi,
                    velocity: note.velocity,
                    onset: onset,
                    duration: clock.seconds(note.tick + note.length) - onset,
                )
            }
        }
        if voices.contains(.click) {
            events += grid.pulses.map { pulse in
                click(pulse.beat == 1 ? .downbeat : .plain, at: clock.seconds(pulse.tick))
            }
        }
        let body = Phrase(events: events, length: clock.total)
        guard countIn else { return body }
        return self.countIn(timeline, factor: factor).followed(by: body)
    }

    /// One bar of click in the range's first meter and tempo, beat 1 accented (a range
    /// without a tempo is never played, R192).
    public static func countIn(_ timeline: PlayAlongTimeline, factor: Double = 1) -> Phrase {
        let meter = timeline.startMeter
        let bpm = max(1, (timeline.startTempo ?? 1) * factor)
        let interval = 60 / bpm
        let events = (0 ..< max(1, meter.pulses)).map { pulse in
            click(pulse == 0 ? .downbeat : .plain, at: Double(pulse) * interval)
        }
        return Phrase(events: events, length: Double(max(1, meter.pulses)) * interval)
    }

    private static func click(_ accent: MetronomeAccent, at onset: TimeInterval) -> NoteEvent {
        NoteEvent(
            voice: .click(accent),
            note: 0,
            velocity: clickVelocity,
            onset: onset,
            duration: clickLength,
        )
    }

    // MARK: Chords

    /// Each chord struck at its onset (a push strikes early) and again on each later
    /// downbeat it covers, held to the next strike.
    private static func chordEvents(
        _ timeline: PlayAlongTimeline,
        grid: PulseGrid,
        clock: TickClock,
        sound: ChordSound,
        style: ChordStyle,
    ) -> [NoteEvent] {
        var events: [NoteEvent] = []
        for chord in timeline.chords {
            guard let concert = chord.concert else { continue }
            let onset = chord.timed.onset
            let end = onset + chord.timed.length
            // A pushed chord rings through the downbeat it anticipates.
            let gridOnset = onset + (chord.timed.push?.ticks ?? 0)
            let strikes = [onset] + grid.pulses(in: gridOnset + 1 ..< end)
                .filter { $0.beat == 1 }.map(\.tick)
            for (index, tick) in strikes.enumerated() {
                let next = index + 1 < strikes.count ? strikes[index + 1] : end
                let start = clock.seconds(tick)
                events += strike(
                    concert,
                    sound: sound,
                    style: style,
                    at: start,
                    length: clock.seconds(next) - start,
                )
            }
        }
        return events
    }

    // MARK: Bass

    /// A bass note on the tick grid.
    struct TickNote: Sendable, Hashable {
        var tick: Int
        var length: Int
        var midi: UInt8
        var velocity: UInt8
    }

    /// A bass note's start, before it is held to the next one (never past `end`).
    private struct Strike {
        var tick: Int
        var midi: UInt8
        var end: Int
    }

    /// Roots on the strong beats each chord covers (4/4: 1 and 3; compound: every pulse;
    /// otherwise 1), each held to the next note; the shown walk-up on the chord's last beats
    /// into the next chord (one per beat, subdivided when squeezed), stepwise, with the next
    /// root landing a step from it; fills replace all of it over their regions.
    static func bassLine(
        _ timeline: PlayAlongTimeline,
        grid: PulseGrid,
        walkUps: Bool,
    ) -> [TickNote] {
        var onsets: [Strike] = []
        var landing: UInt8?
        let chords = timeline.chords
        for (index, chord) in chords.enumerated() {
            let onset = chord.timed.onset
            let end = onset + chord.timed.length
            guard let root = landing ?? chord.bass else {
                landing = nil
                continue
            }
            landing = nil
            let meter = chord.timed.meter
            let gridOnset = onset + (chord.timed.push?.ticks ?? 0)
            var strikes = [onset] + grid.pulses(in: gridOnset + 1 ..< end)
                .filter { strong($0.beat, meter: meter) }.map(\.tick)
            if walkUps, index + 1 < chords.count, let target = chords[index + 1].bass,
               let walk = walk(chord, root: root, into: target, fills: timeline.fills)
            {
                strikes.removeAll { $0 >= (walk.notes.first?.tick ?? end) && $0 != onset }
                onsets += walk.notes.map { Strike(tick: $0.tick, midi: $0.midi, end: end) }
                landing = walk.landing
            }
            onsets += strikes.map { Strike(tick: $0, midi: root, end: end) }
        }
        // Each note held to the next one (never past its chord's end).
        onsets.sort { $0.tick < $1.tick }
        var notes: [TickNote] = []
        for (index, onset) in onsets.enumerated() {
            let next = index + 1 < onsets.count ? onsets[index + 1].tick : onset.end
            let stop = min(next, onset.end)
            guard stop > onset.tick else { continue }
            notes.append(TickNote(
                tick: onset.tick,
                length: stop - onset.tick,
                midi: onset.midi,
                velocity: bassVelocity,
            ))
        }
        return applying(timeline.fills, to: notes)
    }

    /// The walk notes of `chord`'s shown walk-up into a chord whose bass is `target`, each in
    /// the octave nearest the note before it, and where the target then lands (a step from
    /// the last walk note). Nil without a walk-up, or when a fill covers it (P8-7 9.3).
    private static func walk(
        _ chord: PlayAlongChord,
        root: UInt8,
        into target: UInt8,
        fills: [PlayAlongFill],
    ) -> (notes: [(tick: Int, midi: UInt8)], landing: UInt8)? {
        guard !chord.walk.isEmpty else { return nil }
        let slots = walkTicks(
            count: chord.walk.count,
            gridOnset: chord.timed.onset + (chord.timed.push?.ticks ?? 0),
            end: chord.timed.onset + chord.timed.length,
            meter: chord.timed.meter,
        )
        guard !slots.isEmpty,
              !slots.contains(where: { slot in fills.contains { $0.region.contains(slot) } })
        else { return nil }
        var previous = Int(root)
        var notes: [(tick: Int, midi: UInt8)] = []
        for (slot, offset) in zip(slots, chord.walk) {
            let note = nearest(Int(target) + offset, to: previous)
            notes.append((slot, UInt8(clamping: note)))
            previous = note
        }
        return (notes, UInt8(clamping: previous - (chord.walk.last ?? 0)))
    }

    /// `notes` with each fill's region handed to the fill: notes starting inside it are
    /// dropped, notes ringing into it are cut at its start, and the fill's notes are added.
    static func applying(_ fills: [PlayAlongFill], to notes: [TickNote]) -> [TickNote] {
        guard !fills.isEmpty else { return notes }
        var result = notes.compactMap { note -> TickNote? in
            var note = note
            for fill in fills {
                if fill.region.contains(note.tick) {
                    return nil
                }
                if note.tick < fill.region.lowerBound,
                   note.tick + note.length > fill.region.lowerBound
                {
                    note.length = fill.region.lowerBound - note.tick
                }
            }
            return note
        }
        for fill in fills {
            result += fill.notes.map {
                TickNote(tick: $0.tick, length: $0.length, midi: $0.midi, velocity: $0.velocity)
            }
        }
        return result.sorted { $0.tick < $1.tick }
    }

    /// Whether 1-based `beat` is a strong beat in `meter` (R162 Q7).
    static func strong(_ beat: Int, meter: Meter) -> Bool {
        if meter.isCompound {
            return true
        }
        return meter.pulses == 4 ? beat == 1 || beat == 3 : beat == 1
    }

    /// The ticks of `count` walk notes ending at `end`: one per pulse on the chord's last
    /// pulses (never its first), subdivided from the last pulse back when there are more
    /// notes than free pulses (`walkSlots`, as the audition places them). A chord shorter
    /// than two pulses is treated as two halves.
    static func walkTicks(count: Int, gridOnset: Int, end: Int, meter: Meter) -> [Int] {
        let span = end - gridOnset
        guard count > 0, span > 0 else { return [] }
        let pulse = meter.ticksPerPulse
        var pulses = span / pulse
        var unit = Double(pulse)
        var compound = meter.isCompound
        if pulses < 2 {
            pulses = 2
            unit = Double(span) / 2
            compound = false
        }
        return walkSlots(count: count, pulses: pulses, compound: compound).map { slot in
            end - Int(((Double(pulses) - slot) * unit).rounded())
        }
    }
}

/// Every pulse of a timeline slice's bar grid, with its 1-based beat in the bar (a meter
/// change starts a new bar).
struct PulseGrid: Sendable {
    struct Pulse: Sendable, Hashable {
        var tick: Int
        var beat: Int
    }

    let pulses: [Pulse]

    init(_ timeline: SongTimeline) {
        // Where a new meter's bars start: its first chord's grid onset.
        var changes: [Int] = []
        var previous: Meter?
        for chord in timeline.chords {
            if let previous, chord.meter != previous {
                changes.append(chord.onset + (chord.push?.ticks ?? 0))
            }
            previous = chord.meter
        }
        var pulses: [Pulse] = []
        var tick = 0
        var change = 0
        while tick < timeline.totalTicks {
            pulses.append(Pulse(tick: tick, beat: timeline.barBeat(at: tick).beat))
            let meter = timeline.chord(atTick: tick).map { timeline.chords[$0].meter }
                ?? timeline.chords.last?.meter ?? .common
            var next = tick + meter.ticksPerPulse
            while change < changes.count, changes[change] <= tick {
                change += 1
            }
            if change < changes.count, changes[change] < next {
                next = changes[change]
            }
            tick = next
        }
        self.pulses = pulses
    }

    /// The pulses whose tick lies in `range`.
    func pulses(in range: Range<Int>) -> [Pulse] {
        guard !range.isEmpty else { return [] }
        var low = 0
        var high = pulses.count
        while low < high {
            let mid = (low + high) / 2
            if pulses[mid].tick < range.lowerBound {
                low = mid + 1
            } else {
                high = mid
            }
        }
        var result: [Pulse] = []
        var index = low
        while index < pulses.count, pulses[index].tick < range.upperBound {
            result.append(pulses[index])
            index += 1
        }
        return result
    }
}

public extension Phrase {
    /// This phrase, then `next` starting where this one ends.
    func followed(by next: Phrase) -> Phrase {
        let shifted = next.events.map { event in
            var event = event
            event.onset += length
            return event
        }
        return Phrase(events: events + shifted, length: length + next.length)
    }
}
