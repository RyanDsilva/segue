// P8-4a (docs/phases/8-workstreams/P8-4-bass.md section 7.1, R158 Q12): the fretboard core
// the stage mini neck uses now and P8-4b's editor strip reuses unchanged. Pure.

import MusicTheory

/// A place on a bass neck. String 0 is the lowest; fret 0 is the open string.
public struct FretPosition: Sendable, Hashable, CustomStringConvertible {
    public var string: Int
    public var fret: Int

    public init(string: Int, fret: Int) {
        self.string = string
        self.fret = fret
    }

    public var description: String {
        "\(string):\(fret)"
    }
}

/// Where to play a note on a bass: every position, the hand position for a song, the
/// suggested position in the box around it, and root-fifth-octave around a root.
///
/// The box is the fixed window `max(0, home - 1) ... home + 3` around the song's home fret,
/// with open strings always candidates; the lowest sounding pitch wins (R158 Q12).
public enum BassFretboard {
    public static let maxFret = 12
    /// Frets the stage neck draws at once.
    public static let windowFrets = 5

    /// Every position of `pitchClass` on frets 0 ... maxFret, low string first, then by fret.
    public static func positions(of pitchClass: PitchClass, tuning: Tuning) -> [FretPosition] {
        tuning.strings.indices.flatMap { string in
            let first = PitchClass(midi: tuning.strings[string]).semitones(to: pitchClass)
            return stride(from: first, through: maxFret, by: 12).map { fret in
                FretPosition(string: string, fret: fret)
            }
        }
    }

    /// The hand position for a song: the fret of the concert key's tonic on the lowest string
    /// where it falls on frets 0 ... 7 (no key: pass the song's first bass note).
    public static func homeFret(tonic: PitchClass, tuning: Tuning) -> Int {
        for open in tuning.strings {
            let fret = PitchClass(midi: open).semitones(to: tonic)
            if fret <= 7 {
                return fret
            }
        }
        return PitchClass(midi: tuning.strings.first ?? 0).semitones(to: tonic)
    }

    /// The fretted part of the box around `home`.
    public static func box(home: Int) -> ClosedRange<Int> {
        max(0, home - 1) ... home + 3
    }

    /// The suggested position for a note within the box around `home`: the lowest sounding
    /// pitch among the box's positions and open strings, ties to the lower string. With no
    /// candidate (a non-fourths tuning), the position nearest `home` by fret, then lowest.
    public static func suggested(
        _ pitchClass: PitchClass,
        home: Int,
        tuning: Tuning,
    ) -> FretPosition? {
        let all = positions(of: pitchClass, tuning: tuning)
        let candidates = all.filter { isInBox($0, home: home) }
        let lowest: (FretPosition, FretPosition) -> Bool = { lhs, rhs in
            let left = pitch(lhs, tuning: tuning)
            let right = pitch(rhs, tuning: tuning)
            return left != right ? left < right : lhs.string < rhs.string
        }
        if let best = candidates.min(by: lowest) {
            return best
        }
        return all.min { lhs, rhs in
            let left = abs(lhs.fret - home)
            let right = abs(rhs.fret - home)
            return left != right ? left < right : lowest(lhs, rhs)
        }
    }

    /// Fifth (above and below) and octave positions around `root`, inside the box (open
    /// strings included): the exact pitches `root + fifth`, `root + fifth - 12` and
    /// `root + 12`. `fifth` is the chord's fifth in semitones (`fifthInterval(of:)`); pass
    /// nil for slash chords, which get the octave only.
    public static func shape(
        around root: FretPosition,
        fifth: Int?,
        home: Int,
        tuning: Tuning,
    ) -> [FretPosition] {
        guard tuning.strings.indices.contains(root.string) else { return [] }
        let rootPitch = pitch(root, tuning: tuning)
        var targets: [Int] = []
        if let fifth {
            targets += [rootPitch + fifth, rootPitch + fifth - 12]
        }
        targets.append(rootPitch + 12)
        return targets.flatMap { target in
            tuning.strings.indices.compactMap { string -> FretPosition? in
                let position = FretPosition(string: string, fret: target - tuning.strings[string])
                guard position.fret >= 0, position.fret <= maxFret,
                      isInBox(position, home: home)
                else { return nil }
                return position
            }
        }
    }

    /// The fifth a chord formula implies: 7 if present, else 6 (b5) or 8 (#5), else nil.
    public static func fifthInterval(of formula: ChordFormula) -> Int? {
        let classes = Set(formula.intervals.map { $0 % 12 })
        return [7, 6, 8].first(where: classes.contains)
    }

    /// The frets the stage neck draws: `windowFrets` frets from `max(0, home - 1)`, shifted
    /// so `position` (the suggested one) is inside.
    public static func window(home: Int, including position: FretPosition?) -> ClosedRange<Int> {
        var lower = max(0, home - 1)
        if let fret = position?.fret {
            if fret < lower {
                lower = fret
            } else if fret > lower + windowFrets - 1 {
                lower = fret - (windowFrets - 1)
            }
        }
        return lower ... lower + windowFrets - 1
    }

    /// The MIDI pitch a position sounds.
    public static func pitch(_ position: FretPosition, tuning: Tuning) -> Int {
        tuning.strings[position.string] + position.fret
    }

    private static func isInBox(_ position: FretPosition, home: Int) -> Bool {
        position.fret == 0 || box(home: home).contains(position.fret)
    }
}
