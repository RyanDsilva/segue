// Owner: unit B (Diagrams). Frozen interface: docs/phases/1-interfaces.md.

import MusicTheory

/// Default piano voicings (phase 1 spec, "Diagram components").
///
/// The right hand plays the chord's pitch classes as a close voicing (all within an
/// octave) inside C3 ... C5. Without a previous chord it is root position, placed as near
/// middle C as fits; after one, it is the inversion and octave that moves the hand least.
/// The left hand plays `tones.lowest` (slash bass or root) in the octave below the hand.
public enum PianoVoicingGenerator {
    /// Lowest and highest right-hand notes: C3 ... C5.
    public static let rightHandRange = 48 ... 72
    /// The right hand's preferred centre (middle C) when nothing else decides.
    public static let preferredCentre = 60
    /// Right-hand notes at most; extra non-essential tones (the 5th first) are dropped.
    public static let maxRightHandNotes = 5

    /// Root-position close voicing within C3 ... C5 (MIDI 48 ... 72) with the slash bass
    /// (or root) in the left hand; when `previous` is given, the inversion that moves the
    /// least from it.
    public static func voicing(for tones: ChordTones, after previous: PianoVoicing?)
        -> PianoVoicing
    {
        let stack = closeStack(for: tones)
        let candidates = placements(of: stack)
        let rootPosition = candidates.filter { $0.first.map(PitchClass.init(midi:)) == tones.root }
        let chosen: [Int] = if let previous, !previous.notes.isEmpty {
            candidates.min { lhs, rhs in
                rank(lhs, after: previous.notes, root: tones.root)
                    .lexicographicallyPrecedes(rank(rhs, after: previous.notes, root: tones.root))
            } ?? stack
        } else {
            rootPosition.min { centreDistance($0) < centreDistance($1) } ?? stack
        }
        return PianoVoicing(
            notes: chosen,
            bass: bassNote(tones.lowest, below: chosen.first ?? preferredCentre),
            root: tones.root,
        )
    }

    /// Voicings for a chord sequence in song order, each voice-led from the one before.
    public static func voicings(for sequence: [ChordTones]) -> [PianoVoicing] {
        var previous: PianoVoicing?
        return sequence.map { tones in
            let next = voicing(for: tones, after: previous)
            previous = next
            return next
        }
    }

    /// The left-hand note for `pitchClass`: the highest one strictly below `note` (the
    /// right hand's lowest note).
    static func bassNote(_ pitchClass: PitchClass, below note: Int) -> Int {
        var bass = note - 1
        while PitchClass(midi: bass) != pitchClass {
            bass -= 1
        }
        return bass
    }

    // MARK: - Internals

    /// Pitch classes of the right hand, root first then ascending by interval, as offsets
    /// above the root (0 ... 11).
    static func closeStack(for tones: ChordTones) -> [Int] {
        let essential = Set(tones.formula.essential.map { (($0 % 12) + 12) % 12 })
        var offsets: [Int] = []
        for interval in tones.formula.intervals.map({ (($0 % 12) + 12) % 12 }).sorted()
            where !offsets.contains(interval)
        {
            offsets.append(interval)
        }
        if offsets.isEmpty {
            offsets = [0]
        }
        // Drop optional tones, the 5th first, until the hand fits.
        let dropOrder = [7] + offsets.filter { $0 != 7 }.reversed()
        for offset in dropOrder where offsets.count > maxRightHandNotes {
            if offset != 0, !essential.contains(offset) {
                offsets.removeAll { $0 == offset }
            }
        }
        return offsets.map { tones.root.rawValue + $0 }
    }

    /// Every inversion of `stack` in every octave that fits `rightHandRange`, each a close
    /// voicing (ascending, spanning less than an octave).
    static func placements(of stack: [Int]) -> [[Int]] {
        var results: [[Int]] = []
        for inversion in stack.indices {
            var notes = Array(stack[inversion...] + stack[..<inversion].map { $0 + 12 })
            // Normalise to the lowest octave, then walk up through the range.
            while let first = notes.first, first >= 12 {
                notes = notes.map { $0 - 12 }
            }
            while let first = notes.first, first < rightHandRange.lowerBound {
                notes = notes.map { $0 + 12 }
            }
            while let last = notes.last, last <= rightHandRange.upperBound {
                results.append(notes)
                notes = notes.map { $0 + 12 }
            }
        }
        return results
    }

    /// Ordering for voice leading: total movement first, then root position, then nearness
    /// to middle C, then lower.
    private static func rank(_ notes: [Int], after previous: [Int], root: PitchClass)
        -> [Int]
    {
        let isRootPosition = notes.first.map(PitchClass.init(midi:)) == root
        return [
            movement(from: previous, to: notes),
            isRootPosition ? 0 : 1,
            centreDistance(notes),
            notes.first ?? 0,
        ]
    }

    /// Semitones the hand moves: each note travels to the nearest note of the other chord,
    /// summed in both directions so added and dropped voices count too.
    static func movement(from previous: [Int], to next: [Int]) -> Int {
        func nearest(_ note: Int, in other: [Int]) -> Int {
            other.map { abs($0 - note) }.min() ?? 0
        }
        return previous.reduce(0) { $0 + nearest($1, in: next) }
            + next.reduce(0) { $0 + nearest($1, in: previous) }
    }

    /// Twice the distance of the voicing's midpoint from middle C (integer, no rounding).
    private static func centreDistance(_ notes: [Int]) -> Int {
        guard let low = notes.first, let high = notes.last else { return 0 }
        return abs(low + high - 2 * preferredCentre)
    }
}
