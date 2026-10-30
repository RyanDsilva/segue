// P8-6 (docs/phases/8-workstreams/P8-6-audio.md section 6.2): which MIDI notes a concert
// chord and a bass note sound as. Pure.

import Diagrams
import MusicTheory

/// Where the bass voice plays: the tuning and the song's hand position (P8-4 section 7.1).
public struct BassPlacement: Sendable, Hashable {
    public var tuning: Tuning
    /// `BassFretboard.homeFret` for the song.
    public var home: Int

    public init(tuning: Tuning, home: Int) {
        self.tuning = tuning
        self.home = home
    }

    /// The song's placement: home from the concert key's tonic, else the song's first bass
    /// note, else the open low string.
    public static func song(
        concertKey: SongKey?,
        firstBass: PitchClass?,
        tuning: Tuning,
    ) -> Self {
        let tonic = concertKey?.tonic.pitchClass ?? firstBass
        let home = tonic.map { BassFretboard.homeFret(tonic: $0, tuning: tuning) } ?? 0
        return Self(tuning: tuning, home: home)
    }
}

/// What a phrase is played with: the chord sound and style (Settings > Audio) and where
/// the bass sits.
public struct PlaybackVoices: Sendable, Hashable {
    public var sound: ChordSound
    public var style: ChordStyle
    public var placement: BassPlacement

    public init(sound: ChordSound, style: ChordStyle, placement: BassPlacement) {
        self.sound = sound
        self.style = style
        self.placement = placement
    }
}

public enum Voicing {
    /// The piano's range for chord tones: C3 ... C5.
    public static let pianoRange: ClosedRange<Int> = 48 ... 72
    /// The guitar fallback's range: E2 ... E5.
    public static let guitarRange: ClosedRange<Int> = 40 ... 76

    /// The chord voice's notes for a concert chord, low to high. The slash bass is not in
    /// the chord voice (the bass voice plays it).
    public static func chord(
        _ chord: ChordSymbol,
        sound: ChordSound,
        tuning: Tuning = .standard,
    ) -> [UInt8] {
        switch sound {
        case .piano:
            return piano(chord).map(midi)
        case .cleanGuitar:
            let tones = chord.tones
            let shape = CuratedShapes.shape(for: tones, tuning: tuning)
                ?? GuitarShapeGenerator.shapes(for: tones, tuning: tuning, limit: 1).first
            if let shape {
                return shape.pitches(in: tuning).sorted().map(midi)
            }
            return piano(chord).map { note in
                var lowered = note - 12
                while lowered < guitarRange.lowerBound {
                    lowered += 12
                }
                while lowered > guitarRange.upperBound {
                    lowered -= 12
                }
                return midi(lowered)
            }.sorted()
        }
    }

    /// The bass voice's note: the suggested position's pitch (P8-4 section 7.1).
    public static func bass(_ pitchClass: PitchClass, home: Int, tuning: Tuning) -> UInt8 {
        if let position = BassFretboard.suggested(pitchClass, home: home, tuning: tuning) {
            return midi(BassFretboard.pitch(position, tuning: tuning))
        }
        // No position at all (an empty tuning): the pitch class in the second octave.
        return midi(24 + pitchClass.rawValue)
    }

    /// `bass(_:home:tuning:)` for a placement.
    public static func bass(_ pitchClass: PitchClass, placement: BassPlacement) -> UInt8 {
        bass(pitchClass, home: placement.home, tuning: placement.tuning)
    }

    /// The chord's bass note: the slash bass, else the root.
    public static func bassNote(of chord: ChordSymbol, placement: BassPlacement) -> UInt8 {
        bass((chord.bass ?? chord.root).pitchClass, placement: placement)
    }

    /// Close position from the root's lowest place at or above C3, stacked upward inside
    /// C3 ... C5; over four tones keeps root, third, seventh and the colour tone.
    static func piano(_ chord: ChordSymbol) -> [Int] {
        let intervals = trimmed(chord.formula.intervals)
        let rootNote = pianoRange.lowerBound + chord.root.pitchClass.rawValue
        var notes: [Int] = []
        for interval in intervals {
            var note = rootNote + interval
            while note > pianoRange.upperBound {
                note -= 12
            }
            if !notes.contains(note) {
                notes.append(note)
            }
        }
        return notes.sorted()
    }

    /// At most four intervals: root, third (or the sus tone), seventh, then the highest
    /// remaining tone (the colour); fewer than five are kept as they are.
    static func trimmed(_ intervals: [Int]) -> [Int] {
        guard intervals.count > 4 else { return intervals }
        let classes = intervals.map { ($0, $0 % 12) }
        func first(_ wanted: [Int]) -> Int? {
            for target in wanted {
                if let match = classes.first(where: { $0.1 == target && $0.0 < 12 }) {
                    return match.0
                }
            }
            return nil
        }
        var kept = [0]
        if let third = first([4, 3, 5, 2]) {
            kept.append(third)
        }
        if let seventh = first([10, 11, 9]) {
            kept.append(seventh)
        }
        if let colour = intervals.reversed().first(where: { !kept.contains($0) && $0 != 7 }) {
            kept.append(colour)
        }
        return kept.sorted()
    }

    private static func midi(_ value: Int) -> UInt8 {
        UInt8(clamping: min(max(value, 0), 127))
    }
}
