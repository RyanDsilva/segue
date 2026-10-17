// Owner: unit A (MusicTheory). Maps our interval table onto Tonic's `ChordType`.

import Tonic

enum TonicBridge {
    /// Tonic `ChordType` by exact interval content (semitones above the root, without the
    /// root), first declared case wins.
    private static let byIntervals: [[Int]: ChordType] = {
        var table: [[Int]: ChordType] = [:]
        for type in ChordType.allCases {
            let key = type.intervals.map(\.semitones).sorted()
            if table[key] == nil {
                table[key] = type
            }
        }
        return table
    }()

    /// Tonic `ChordType` by pitch-class content, for spellings whose octave placement
    /// differs from Tonic's (e.g. `add4` written as a 4th, Tonic's as an 11th).
    private static let byPitchClasses: [Set<Int>: ChordType] = {
        var table: [Set<Int>: ChordType] = [:]
        for type in ChordType.allCases {
            let key = Set(type.intervals.map { $0.semitones % 12 })
            if table[key] == nil {
                table[key] = type
            }
        }
        return table
    }()

    /// Tonic's equivalent of `formula`, or `nil` when Tonic has no such chord type.
    static func chordType(for formula: ChordFormula) -> ChordType? {
        let intervals = formula.intervals.filter { $0 != 0 }
        if let type = byIntervals[intervals] {
            return type
        }
        let pitchClasses = Set(intervals.map { $0 % 12 }).subtracting([0])
        guard pitchClasses.count == intervals.count else { return nil }
        return byPitchClasses[pitchClasses]
    }

    static func chord(root: NoteClass, formula: ChordFormula) -> Chord? {
        chordType(for: formula).map { Chord(root, type: $0) }
    }
}
