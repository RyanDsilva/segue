// P8-7c (docs/phases/8-workstreams/P8-7-time-model-and-fills.md sections 9.2, 9.4). A part's
// events resolved to sounding notes on the timeline: the one resolver hearing, the stage, the
// neck, the mini tab and later exports read. Pure.

import Diagrams
import Editing
import MusicTheory

/// One note of a part as it sounds in a play.
public struct ResolvedNote: Sendable, Hashable {
    /// Index into `Part.events`.
    public var event: Int
    /// Ticks from the timeline's start.
    public var tick: Int
    /// Ticks, clipped at its chord's end (the landing chord's notes are not clipped).
    public var len: Int
    /// Sounding pitch.
    public var midi: Int
    /// Spelled in the key in effect at its chord (section 9.2).
    public var name: String
    /// By the pin when the tuning has that string, else the position nearest the hand.
    public var position: FretPosition?
    public var articulations: Set<Articulation>
    public var velocity: UInt8
    /// Moved by an octave into the instrument's range (the editor marks it).
    public var folded: Bool
    /// Starts past its chord's end after a timing edit: drawn with a warning, skipped in
    /// playback and on stage, never moved.
    public var outside: Bool

    /// The velocity played: ghost 40, accent +20, slide / hammer / pull -15.
    public var playedVelocity: UInt8 {
        if articulations.contains(.ghost) {
            return 40
        }
        var value = Int(velocity)
        if articulations.contains(.accent) {
            value += 20
        }
        if !articulations.isDisjoint(with: [.slide, .hammer, .pull]) {
            value -= 15
        }
        return UInt8(clamping: min(max(value, 1), 127))
    }

    /// The length played: ghost and staccato notes sound half as long.
    public var playedLength: Int {
        articulations.isDisjoint(with: [.ghost, .staccato]) ? len : max(1, len / 2)
    }
}

public extension PartPlay {
    /// The play's notes in tick order (section 9.4): each event's pitch is its chord's placed
    /// bass note (`BassFretboard.suggested` around `home`, as the play-along bass voice
    /// places it) plus `deg` and `oct`, at concert pitch through `transform`; folded by
    /// octaves into the tuning's range (lowest open string ... highest + 20 frets).
    func resolve(
        timeline: SongTimeline,
        transform: DisplayTransform,
        tuning: Tuning,
        home: Int,
    ) -> [ResolvedNote] {
        let span = Array(timeline.chords[chords])
        let concert = span.map { Self.concert($0, transform: transform) }
        let range = PartPitch.range(of: tuning)
        var previous: Int?
        var notes: [ResolvedNote] = []
        let order = part.events.indices.sorted { left, right in
            let lhs = part.events[left]
            let rhs = part.events[right]
            return lhs.chord != rhs.chord ? lhs.chord < rhs.chord : lhs.at < rhs.at
        }
        for index in order {
            let event = part.events[index]
            guard span.indices.contains(event.chord), let symbol = concert[event.chord] else {
                continue
            }
            let chord = span[event.chord]
            let isLanding = event.chord == span.count - 1
            let base = PartPitch.placedBass(symbol, tuning: tuning, home: home)
            var midi = base + event.semitones
            let folded = !range.contains(midi)
            midi = PartPitch.fold(midi, into: range)
            let outside = !isLanding && event.at >= chord.length
            let len = isLanding ? event.len : max(1, min(event.len, chord.length - event.at))
            let key = chord.key.map { $0.transposed(by: transform.concertSemitones) }
                ?? transform.concertKey
            let name = FillSpelling.spell(
                PitchClass(midi: midi),
                over: symbol,
                key: key,
                ascending: previous.map { midi >= $0 },
            )
            notes.append(ResolvedNote(
                event: index,
                tick: chord.onset + event.at,
                len: len,
                midi: midi,
                name: name.chartName,
                position: PartPitch.position(midi, pin: event.string, tuning: tuning, home: home),
                articulations: event.articulations,
                velocity: event.playedVelocity,
                folded: folded,
                outside: outside,
            ))
            if !outside {
                previous = midi
            }
        }
        return notes.sorted { $0.tick != $1.tick ? $0.tick < $1.tick : $0.event < $1.event }
    }

    /// A timed chord at concert pitch, spelled in the `{key}` in effect there.
    internal static func concert(_ chord: TimedChord, transform: DisplayTransform) -> ChordSymbol? {
        let transposer = Transposer(
            semitones: transform.concertSemitones,
            sourceKey: chord.key ?? transform.key.writtenKey,
        )
        return transposer.transpose(ChordToken(parsing: chord.token)).chord?.symbol
    }
}

/// Pitch placement shared by the resolver and `FillSpan` (the generator's placed basses).
public enum PartPitch {
    /// The playable range: the lowest open string ... the highest open string + 20 frets.
    public static func range(of tuning: Tuning) -> ClosedRange<Int> {
        let low = tuning.strings.min() ?? 28
        let high = (tuning.strings.max() ?? 43) + 20
        return low ... max(low, high)
    }

    /// A chord's bass note (the slash bass, else the root) where the bass voice plays it:
    /// `BassFretboard.suggested` around `home` (the same note `Voicing.bassNote` gives).
    public static func placedBass(_ chord: ChordSymbol, tuning: Tuning, home: Int) -> Int {
        let pitch = (chord.bass ?? chord.root).pitchClass
        if let position = BassFretboard.suggested(pitch, home: home, tuning: tuning) {
            return BassFretboard.pitch(position, tuning: tuning)
        }
        return 24 + pitch.rawValue
    }

    /// `midi` moved by octaves into `range`.
    public static func fold(_ midi: Int, into range: ClosedRange<Int>) -> Int {
        var value = midi
        while value < range.lowerBound {
            value += 12
        }
        while value > range.upperBound {
            value -= 12
        }
        return value
    }

    /// Where a note is played: on the pinned open string when the tuning has it and the
    /// fret is 0 ... 24; else the exact-pitch position in the hand's box (or open), else the
    /// one nearest `home`, ties to the lower string.
    public static func position(
        _ midi: Int,
        pin: String?,
        tuning: Tuning,
        home: Int,
    ) -> FretPosition? {
        if let pin, let open = PartEvent.stringPitch(pin),
           let string = tuning.strings.firstIndex(of: open), (0 ... 24).contains(midi - open)
        {
            return FretPosition(string: string, fret: midi - open)
        }
        let all = tuning.strings.indices.compactMap { string -> FretPosition? in
            let fret = midi - tuning.strings[string]
            return (0 ... 24).contains(fret) ? FretPosition(string: string, fret: fret) : nil
        }
        let box = BassFretboard.box(home: home)
        if let inBox = all.first(where: { $0.fret == 0 || box.contains($0.fret) }) {
            return inBox
        }
        return all.min { lhs, rhs in
            let left = abs(lhs.fret - home)
            let right = abs(rhs.fret - home)
            return left != right ? left < right : lhs.string < rhs.string
        }
    }
}
