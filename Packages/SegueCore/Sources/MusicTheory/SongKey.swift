// Owner: unit A (MusicTheory). Frozen interface: docs/phases/1-interfaces.md.

import Tonic

/// Major or minor.
public enum KeyMode: String, Sendable, Hashable, Codable, CaseIterable {
    case major
    case minor
}

/// A song key as Segue uses it: a spelled tonic plus major/minor.
///
/// Our own type (rather than Tonic `Key`) so it is `Codable` and carries the spelling the
/// author chose (`Db` vs `C#`). Bridges to Tonic via `tonicKey`.
public struct SongKey: Sendable, Hashable, Codable {
    public var tonic: NoteClass
    public var mode: KeyMode

    public init(tonic: NoteClass, mode: KeyMode) {
        self.tonic = tonic
        self.mode = mode
    }

    /// Parses a `{key}` value: `G`, `F#m`, `Bbm`, `Ebmin`, `C minor`, `Am`. `nil` when not a
    /// key (the editor then treats the song as having no declared key).
    public init?(parsing text: String) {
        fatalError("unimplemented: unit A")
    }

    /// Display / `{key}` text: `"G"`, `"F#m"`, `"Bb"`.
    public var name: String {
        fatalError("unimplemented: unit A")
    }

    /// The relative major (`Am` -> `C`); `self` for a major key.
    public var relativeMajor: Self {
        fatalError("unimplemented: unit A")
    }

    /// Tonic's equivalent key (major or natural minor scale).
    public var tonicKey: Key {
        fatalError("unimplemented: unit A")
    }

    /// The key `semitones` away, spelled by the key-signature rules (sharp keys G D A E B
    /// F#, flat keys F Bb Eb Ab Db Gb; the enharmonic choice for 6 semitones and for minor
    /// keys is pinned by unit A's tests).
    public func transposed(by semitones: Int) -> Self {
        fatalError("unimplemented: unit A")
    }

    /// Diatonic chord symbols of the key in degree order, triads then sevenths
    /// (`G`: `G Am Bm C D Em F#dim`, then `Gmaj7 Am7 ...`). Feeds `[` autocomplete.
    public var diatonicChordSymbols: [String] {
        fatalError("unimplemented: unit A")
    }
}

/// Enharmonic spelling by key signature (phase 1 spec, "Transposition and enharmonic
/// spelling").
public enum KeySpelling {
    /// Spells `pitchClass` for display in `key`: sharp keys use sharps, flat keys flats;
    /// C / Am use sharps for raised degrees except bVII and bIII (Bb, Eb). With no key the
    /// C-major rule applies.
    public static func spell(_ pitchClass: PitchClass, in key: SongKey?) -> NoteClass {
        fatalError("unimplemented: unit A")
    }
}
