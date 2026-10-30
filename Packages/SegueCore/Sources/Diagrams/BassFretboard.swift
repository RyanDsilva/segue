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
/// suggested position in the box around it, every chord tone on a range of frets (R166) and
/// where a walk-up's notes fall.
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

    // MARK: Chord tones and the walk-up path (R166)

    /// Every chord tone of `symbol` on `frets`, low string first, then by fret: the bass note
    /// to play (the slash bass, else the root), the root when a slash bass differs, and each
    /// other tone of the formula (third, fifth, seventh, extensions), each with its degree
    /// from the root.
    public static func tones(
        of symbol: ChordSymbol,
        frets: ClosedRange<Int>,
        tuning: Tuning,
    ) -> [NeckTone] {
        let root = symbol.root.pitchClass
        let bass = (symbol.bass ?? symbol.root).pitchClass
        var degrees: [PitchClass: String] = [:]
        // Formula order: lower intervals name a pitch class first (a 9 never renames the 2).
        for interval in symbol.formula.intervals.sorted() {
            let pitch = root.transposed(by: interval)
            if degrees[pitch] == nil {
                degrees[pitch] = degree(interval)
            }
        }
        if degrees[bass] == nil {
            degrees[bass] = degree(root.semitones(to: bass))
        }
        degrees[root] = "R"
        return tuning.strings.indices.flatMap { string in
            frets.compactMap { fret -> NeckTone? in
                let position = FretPosition(string: string, fret: fret)
                let pitch = PitchClass(midi: Self.pitch(position, tuning: tuning))
                guard let name = degrees[pitch] else { return nil }
                let role: NeckTone.Role = pitch == bass ? .bass : (pitch == root ? .root : .tone)
                return NeckTone(position: position, degree: name, role: role)
            }
        }
    }

    /// The degree name of an interval above the root: "R", "b3", "3", "5", "b7", "7", and
    /// "9", "#11", "13" above the octave.
    public static func degree(_ interval: Int) -> String {
        let names = [
            0: "R", 1: "b2", 2: "2", 3: "b3", 4: "3", 5: "4", 6: "b5", 7: "5", 8: "#5", 9: "6",
            10: "b7", 11: "7", 13: "b9", 14: "9", 15: "#9", 17: "11", 18: "#11", 20: "b13",
            21: "13",
        ]
        let normalized = interval > 21 || interval < 0 ? ((interval % 12) + 12) % 12 : interval
        return names[normalized] ?? names[normalized % 12] ?? "\(normalized)"
    }

    /// Where a walk-up's notes fall when it starts from `start` (the chord's suggested
    /// position): each note at the nearest pitch in its direction from the one before (up,
    /// down, or nearest either way when `ascending` is nil), then the position on `frets`
    /// that plays that pitch closest to the previous one by fret. nil for a note with no
    /// such position on `frets`.
    public static func walkPath(
        _ notes: [PitchClass],
        ascending: Bool?,
        from start: FretPosition,
        frets: ClosedRange<Int>,
        tuning: Tuning,
    ) -> [FretPosition?] {
        guard tuning.strings.indices.contains(start.string) else {
            return notes.map { _ in nil }
        }
        var previousPitch = pitch(start, tuning: tuning)
        var previousFret = start.fret
        return notes.map { note in
            let up = PitchClass(midi: previousPitch).semitones(to: note)
            let step = switch ascending {
            case true?: up == 0 ? 12 : up
            case false?: up == 0 ? -12 : up - 12
            case nil: up <= 6 ? up : up - 12
            }
            let target = previousPitch + step
            previousPitch = target
            let found = tuning.strings.indices.compactMap { string -> FretPosition? in
                let fret = target - tuning.strings[string]
                return frets.contains(fret) ? FretPosition(string: string, fret: fret) : nil
            }.min { abs($0.fret - previousFret) < abs($1.fret - previousFret) }
            if let found {
                previousFret = found.fret
            }
            return found
        }
    }
}

/// One chord tone on the neck (R166): where, its degree from the root, and how strongly it
/// is drawn.
public struct NeckTone: Sendable, Hashable {
    public enum Role: Sendable, Hashable {
        /// The note to play: the slash bass, else the root (strongest).
        case bass
        /// The chord's root when a slash bass differs.
        case root
        /// Any other chord tone.
        case tone
    }

    public var position: FretPosition
    /// "R", "3", "b3", "5", "b7", "7", "9".
    public var degree: String
    public var role: Role

    public init(position: FretPosition, degree: String, role: Role) {
        self.position = position
        self.degree = degree
        self.role = role
    }
}
