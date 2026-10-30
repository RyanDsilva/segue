// Owner: unit A (MusicTheory). Frozen interface: docs/phases/1-interfaces.md.

import Foundation
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
        let trimmed = Substring(text.trimmingCharacters(in: .whitespacesAndNewlines))
        guard let (tonic, length) = NoteClass.prefix(of: trimmed) else { return nil }
        let rest = trimmed.dropFirst(length).trimmingCharacters(in: .whitespaces)
        let lowered = rest.lowercased()
        if rest == "M" || ["", "maj", "major"].contains(lowered) {
            self.init(tonic: tonic, mode: .major)
        } else if rest == "m" || ["min", "minor", "mi", "-"].contains(lowered) {
            self.init(tonic: tonic, mode: .minor)
        } else {
            return nil
        }
    }

    /// The conventional spelling of the key on `pitchClass` in `mode`: majors
    /// `C Db D Eb E F F# G Ab A Bb B`, minors their relatives
    /// `Cm C#m Dm D#m Em Fm F#m Gm G#m Am Bbm Bm`.
    public init(canonical pitchClass: PitchClass, mode: KeyMode) {
        let (sharp, flat) = NoteClass.spellings(of: pitchClass)
        let flatMajors: Set = [1, 3, 8, 10]
        let flatMinors: Set = [10]
        let usesFlat = switch mode {
        case .major: flatMajors.contains(pitchClass.rawValue)
        case .minor: flatMinors.contains(pitchClass.rawValue)
        }
        self.init(tonic: usesFlat ? flat : sharp, mode: mode)
    }

    /// Display / `{key}` text: `"G"`, `"F#m"`, `"Bb"`.
    public var name: String {
        tonic.chartName + (mode == .minor ? "m" : "")
    }

    /// The relative major (`Am` -> `C`); `self` for a major key.
    public var relativeMajor: Self {
        guard mode == .minor else { return self }
        let target = tonic.pitchClass.transposed(by: 3)
        let letter = Letter(rawValue: (tonic.letter.rawValue + 2) % 7) ?? .C
        let natural = NoteClass(letter).pitchClass
        let offset = natural.semitones(to: target)
        let accidental: Accidental? = switch offset {
        case 0: .natural
        case 1: .sharp
        case 11: .flat
        default: nil
        }
        // Keep the letter a third up (Ebm -> Gb, D#m -> F#) unless that needs a double
        // accidental or a white-key enharmonic (Abm -> B, not Cb).
        guard let accidental, accidental == .natural || !NoteClass(letter).isWhiteKeyNeighbour(
            accidental,
        ) else {
            return Self(canonical: target, mode: .major)
        }
        return Self(tonic: NoteClass(letter, accidental: accidental), mode: .major)
    }

    /// Tonic's equivalent key (major or natural minor scale).
    public var tonicKey: Key {
        Key(root: tonic, scale: mode == .major ? .major : .minor)
    }

    /// The key `semitones` away, spelled by the key-signature rules (sharp keys G D A E B
    /// F#, flat keys F Bb Eb Ab Db Gb; the enharmonic choice for 6 semitones and for minor
    /// keys is pinned by unit A's tests).
    public func transposed(by semitones: Int) -> Self {
        guard PitchClass(semitones).rawValue != 0 else { return self }
        return Self(canonical: tonic.pitchClass.transposed(by: semitones), mode: mode)
    }

    /// Diatonic chord symbols of the key in degree order, triads then sevenths
    /// (`G`: `G Am Bm C D Em F#dim`, then `Gmaj7 Am7 ...`). Feeds `[` autocomplete.
    ///
    /// Minor keys use the natural minor, then add the harmonic-minor dominant (`E`, `E7`
    /// in A minor) at the end because charts use it constantly.
    public var diatonicChordSymbols: [String] {
        let degrees = mode == .major ? DiatonicDegree.major : DiatonicDegree.minor
        let roots = degrees.map { degree in
            KeySpelling.spell(tonic.pitchClass.transposed(by: degree.offset), in: self).chartName
        }
        var symbols = zip(roots, degrees).map { $0 + $1.triad }
        symbols += zip(roots, degrees).map { $0 + $1.seventh }
        if mode == .minor {
            let dominant = KeySpelling.spell(tonic.pitchClass.transposed(by: 7), in: self)
            symbols += [dominant.chartName, dominant.chartName + "7"]
        }
        return symbols
    }

    /// Whether `pitchClass` belongs to the key: the major scale, or the natural minor plus
    /// its leading tone (harmonic minor's raised 7th, which charts use constantly).
    public func scaleContains(_ pitchClass: PitchClass) -> Bool {
        let degree = tonic.pitchClass.semitones(to: pitchClass)
        let degrees: Set = switch mode {
        case .major: [0, 2, 4, 5, 7, 9, 11]
        case .minor: [0, 2, 3, 5, 7, 8, 10, 11]
        }
        return degrees.contains(degree)
    }

    /// How the key's signature spells black keys.
    var flavour: KeyFlavour {
        switch (tonic.accidental, mode, tonic.letter) {
        case (.doubleFlat, _, _), (.flat, _, _): .flat
        case (.doubleSharp, _, _), (.sharp, _, _): .sharp
        case (.natural, .major, .C), (.natural, .minor, .A): .natural
        case (.natural, .major, .F), (.natural, .minor, .C), (.natural, .minor, .D),
             (.natural, .minor, .F), (.natural, .minor, .G): .flat
        case (.natural, _, _): .sharp
        }
    }
}

/// Enharmonic spelling by key signature (phase 1 spec, "Transposition and enharmonic
/// spelling").
public enum KeySpelling {
    /// Spells `pitchClass` for display in `key`: sharp keys use sharps, flat keys flats;
    /// C / Am use sharps for raised degrees except bVII and bIII (Bb, Eb). With no key the
    /// C-major rule applies.
    ///
    /// The full rule set, pinned by `MusicTheoryTranspositionTests`:
    /// - White keys are always naturals (`B`, never `Cb`; `F`, never `E#`), as charts do.
    /// - The minor-key leading tone is always a sharp (`C#` in D minor, `F#` in G minor).
    /// - Flat keys (F, Bb, Eb, Ab, Db, Gb and their relative minors) spell black keys flat.
    /// - Sharp keys and C / Am spell black keys sharp, except the flat 3rd and flat 7th of the
    ///   (relative) major, which are flats: `Eb Bb` in C and A minor, `Bb` in G and E minor.
    public static func spell(_ pitchClass: PitchClass, in key: SongKey?) -> NoteClass {
    /// The key's scale from the tonic, seven notes: the major scale, or the natural minor,
    /// each spelled by `KeySpelling.spell` so its letters match the chart's (white keys stay
    /// natural: F# major reads `F# G# A# B C# D# F`).
    public var scaleNotes: [NoteClass] {
        let degrees = mode == .major ? [0, 2, 4, 5, 7, 9, 11] : [0, 2, 3, 5, 7, 8, 10]
        return degrees.map { offset in
            offset == 0 ? tonic : KeySpelling.spell(
                tonic.pitchClass.transposed(by: offset),
                in: self,
            )
        }
    }

        let (sharp, flat) = NoteClass.spellings(of: pitchClass)
        guard sharp != flat else { return sharp }
        let key = key ?? SongKey(tonic: NoteClass(.C), mode: .major)
        let tonic = key.tonic.pitchClass
        if key.mode == .minor, pitchClass == tonic.transposed(by: 11) {
            return sharp
        }
        if key.flavour == .flat {
            return flat
        }
        let majorTonic = key.mode == .major ? tonic : tonic.transposed(by: 3)
        let degree = majorTonic.semitones(to: pitchClass)
        return degree == 3 || degree == 10 ? flat : sharp
    }
}

/// One scale degree's chords: semitones above the tonic, triad and seventh suffixes.
private struct DiatonicDegree {
    var offset: Int
    var triad: String
    var seventh: String

    init(_ offset: Int, _ triad: String, _ seventh: String) {
        self.offset = offset
        self.triad = triad
        self.seventh = seventh
    }

    static let major = [
        Self(0, "", "maj7"), Self(2, "m", "m7"), Self(4, "m", "m7"), Self(5, "", "maj7"),
        Self(7, "", "7"), Self(9, "m", "m7"), Self(11, "dim", "m7b5"),
    ]

    /// Natural minor.
    static let minor = [
        Self(0, "m", "m7"), Self(2, "dim", "m7b5"), Self(3, "", "maj7"), Self(5, "m", "m7"),
        Self(7, "m", "m7"), Self(8, "", "maj7"), Self(10, "", "7"),
    ]
}

/// The accidental family a key signature uses.
enum KeyFlavour {
    /// C major / A minor: no signature.
    case natural
    case sharp
    case flat
}

extension NoteClass {
    /// Whether `accidental` on this natural lands on another white key (`Cb`, `Fb`, `E#`,
    /// `B#`).
    func isWhiteKeyNeighbour(_ accidental: Accidental) -> Bool {
        switch (letter, accidental) {
        case (.B, .sharp), (.C, .flat), (.E, .sharp), (.F, .flat): true
        default: false
        }
    }
}
