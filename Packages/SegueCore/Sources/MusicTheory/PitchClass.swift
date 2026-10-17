// Owner: unit A (MusicTheory). Frozen interface: docs/phases/1-interfaces.md.

import Tonic

/// A pitch class without spelling: 0 = C, 1 = C#/Db, ... 11 = B.
///
/// Used wherever spelling does not matter (chord tones, diagram generators, key scoring).
/// Spelled notes are Tonic `NoteClass` values, produced by `KeySpelling`.
public struct PitchClass: Sendable, Hashable, Codable, Comparable, CustomStringConvertible {
    /// 0 ... 11.
    public let rawValue: Int

    /// Wraps any integer into 0 ... 11 (`PitchClass(-1) == PitchClass(11)`).
    public init(_ value: Int) {
        rawValue = ((value % 12) + 12) % 12
    }

    /// The pitch class `semitones` above this one (negative goes down).
    public func transposed(by semitones: Int) -> Self {
        Self(rawValue + semitones)
    }

    /// Upward distance in semitones from `self` to `other`, 0 ... 11.
    public func semitones(to other: Self) -> Int {
        Self(other.rawValue - rawValue).rawValue
    }

    /// Pitch class of a MIDI note number (60 = middle C).
    public init(midi: Int) {
        self.init(midi)
    }

    public static func < (lhs: Self, rhs: Self) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    public var description: String {
        String(rawValue)
    }
}

public extension NoteClass {
    /// The unspelled pitch class (`Db` and `C#` are both 1). Tonic's `intValue` is a
    /// spelling index, not a pitch class; use this instead.
    var pitchClass: PitchClass {
        let base = [0, 2, 4, 5, 7, 9, 11][letter.rawValue]
        return PitchClass(base + Int(accidental.rawValue))
    }
}
