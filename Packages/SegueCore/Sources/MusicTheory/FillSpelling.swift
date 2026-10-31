// P8-7c (docs/phases/8-workstreams/P8-7-time-model-and-fills.md section 9.2, R161, R168).
// The passing scale over a chord, mode-aware (harmonic minor, Bhairav, the major pentatonic,
// docs/research/phase8-fill-corpus.md section 6 item 6), and how a fill note is spelled. The
// generator and the part resolver share it, so a fill reads the same in the editor and on
// stage. Pure.

import Tonic

/// The scale a key's passing tones come from. `major` and `minor` are the key's own; the
/// others replace it for a key of the same quality.
public enum FillMode: String, Sendable, Hashable, Codable, CaseIterable {
    case major
    case minor
    /// The raised 7th (the augmented second between b6 and 7; Bollywood minor).
    case harmonicMinor
    /// Raga Bhairav: 1 b2 3 4 5 b6 7.
    case bhairav
    /// Raga Bhoopali: 1 2 3 5 6.
    case majorPentatonic
    /// The raised 6th and 7th (the jazz melodic minor, both ways).
    case melodicMinor
    /// 1 b3 4 5 b7.
    case minorPentatonic

    /// The semitones above the tonic.
    public var degrees: [Int] {
        switch self {
        case .major: [0, 2, 4, 5, 7, 9, 11]
        case .minor: [0, 2, 3, 5, 7, 8, 10]
        case .harmonicMinor: [0, 2, 3, 5, 7, 8, 11]
        case .bhairav: [0, 1, 4, 5, 7, 8, 11]
        case .majorPentatonic: [0, 2, 4, 7, 9]
        case .melodicMinor: [0, 2, 3, 5, 7, 9, 11]
        case .minorPentatonic: [0, 3, 5, 7, 10]
        }
    }

    /// Letter steps above the tonic's letter, per degree.
    var letterSteps: [Int] {
        switch self {
        case .majorPentatonic: [0, 1, 2, 4, 5]
        case .minorPentatonic: [0, 2, 3, 4, 6]
        default: [0, 1, 2, 3, 4, 5, 6]
        }
    }

    /// The key quality this mode replaces.
    public var quality: KeyMode {
        switch self {
        case .bhairav, .major, .majorPentatonic: .major
        case .harmonicMinor, .melodicMinor, .minor, .minorPentatonic: .minor
        }
    }

    /// The mode a key uses: `mode` when it has the key's quality, else the key's own.
    public static func of(_ key: SongKey, mode: Self?) -> Self {
        if let mode, mode.quality == key.mode {
            return mode
        }
        return key.mode == .major ? .major : .minor
    }
}

public enum FillSpelling {
    /// `passScale(chord, localKey)` (R161): the key's scale in its mode, with every letter the
    /// chord alters replaced by the chord's tone (its third, fifth and seventh as spelled),
    /// plus the chord's root. No key: the chord's tones only.
    public static func passScale(
        _ chord: ChordSymbol,
        key: SongKey?,
        mode: FillMode? = nil,
    ) -> [PitchClass: NoteClass] {
        let tones = ChordToneSpelling(chord)
        let chordNotes = [chord.root, tones.third, tones.fifth, tones.seventh].compactMap(\.self)
        guard let key else {
            var notes: [PitchClass: NoteClass] = [:]
            for note in chordNotes {
                notes[note.pitchClass] = note
            }
            return notes
        }
        var byLetter: [Letter: NoteClass] = [:]
        for note in scaleNotes(key, mode: mode) {
            byLetter[note.letter] = note
        }
        for note in chordNotes {
            byLetter[note.letter] = note
        }
        // Chord tones win when two letters share a pitch class, in letter order, so the
        // spelling never depends on dictionary order.
        let chordSet = Set(chordNotes)
        var notes: [PitchClass: NoteClass] = [:]
        for note in byLetter.sorted(by: { $0.key.rawValue < $1.key.rawValue }).map(\.value)
            where notes[note.pitchClass] == nil || chordSet.contains(note)
        {
            notes[note.pitchClass] = note
        }
        return notes
    }

    /// The key's scale in `mode` (when it has the key's quality), each degree on its own
    /// letter.
    public static func scaleNotes(_ key: SongKey, mode: FillMode? = nil) -> [NoteClass] {
        let mode = FillMode.of(key, mode: mode)
        if mode == .major || mode == .minor {
            return key.scaleNotes
        }
        return zip(mode.degrees, mode.letterSteps).map { offset, steps in
            let letter = Letter(rawValue: (key.tonic.letter.rawValue + steps) % 7) ?? .C
            return ChordToneSpelling.spell(
                letter: letter,
                pitch: key.tonic.pitchClass.transposed(by: offset),
                key: key,
            )
        }
    }

    /// A fill note's name (section 9.2): a chord tone takes the chord's spelling, a passing
    /// tone the passing scale's, anything else sharp ascending and flat descending
    /// (`ascending` nil: the key's spelling).
    public static func spell(
        _ pitch: PitchClass,
        over chord: ChordSymbol,
        key: SongKey?,
        mode: FillMode? = nil,
        ascending: Bool?,
    ) -> NoteClass {
        if let bass = chord.bass, bass.pitchClass == pitch {
            return bass
        }
        if let spelled = passScale(chord, key: key, mode: mode)[pitch] {
            return spelled
        }
        let (sharp, flat) = NoteClass.spellings(of: pitch)
        if sharp == flat {
            return sharp
        }
        switch ascending {
        case true: return sharp
        case false: return flat
        case nil: return KeySpelling.spell(pitch, in: key)
        }
    }
}
