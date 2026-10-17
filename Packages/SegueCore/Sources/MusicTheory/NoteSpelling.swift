// Owner: unit A (MusicTheory). Chart-text helpers for spelled notes.

import Tonic

public extension NoteClass {
    /// Chart spelling with ASCII accidentals: `"C"`, `"F#"`, `"Bb"`, `"Cbb"`. This is what
    /// chord and key text uses (Tonic's `description` uses Unicode accidentals).
    var chartName: String {
        let accidentalText = switch accidental {
        case .doubleFlat: "bb"
        case .flat: "b"
        case .natural: ""
        case .sharp: "#"
        case .doubleSharp: "##"
        }
        return "\(letter)\(accidentalText)"
    }

    /// Parses a chart note name: an upper-case letter `A`...`G` plus at most one accidental
    /// (`#`, `b`, `♯`, `♭`). `nil` for anything else (strict on purpose: lyric words must not
    /// read as notes).
    init?(chartName text: Substring) {
        guard let (note, length) = Self.prefix(of: text), length == text.count else {
            return nil
        }
        self = note
    }

    /// The note name at the start of `text` and how many `Character`s it spans.
    internal static func prefix(of text: Substring) -> (Self, Int)? {
        guard let first = text.first, let letter = Letter(chartLetter: first) else {
            return nil
        }
        let next = text.dropFirst().first
        switch next {
        case "#", "♯": return (Self(letter, accidental: .sharp), 2)
        case "♭", "b": return (Self(letter, accidental: .flat), 2)
        default: return (Self(letter, accidental: .natural), 1)
        }
    }

    /// The two single-accidental (or natural) spellings of a pitch class, as used by
    /// `KeySpelling`: a natural for white keys, else the sharp of the letter below and the
    /// flat of the letter above.
    internal static func spellings(of pitchClass: PitchClass) -> (sharp: Self, flat: Self) {
        let naturals: [Int: Letter] = [0: .C, 2: .D, 4: .E, 5: .F, 7: .G, 9: .A, 11: .B]
        if let letter = naturals[pitchClass.rawValue] {
            let note = Self(letter)
            return (note, note)
        }
        let below = naturals[pitchClass.transposed(by: -1).rawValue] ?? .C
        let above = naturals[pitchClass.transposed(by: 1).rawValue] ?? .C
        return (Self(below, accidental: .sharp), Self(above, accidental: .flat))
    }
}

extension Letter {
    /// Upper-case `A`...`G` only.
    init?(chartLetter character: Character) {
        switch character {
        case "A": self = .A
        case "B": self = .B
        case "C": self = .C
        case "D": self = .D
        case "E": self = .E
        case "F": self = .F
        case "G": self = .G
        default: return nil
        }
    }
}
