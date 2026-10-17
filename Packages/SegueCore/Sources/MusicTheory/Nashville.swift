// Owner: unit A (MusicTheory). Frozen interface: docs/phases/1-interfaces.md.

import Foundation
import Tonic

/// Nashville number rendering (phase 1 spec, "Nashville rendering") and number entry.
public enum Nashville {
    /// The Nashville form of `token` relative to `key`: `1 4 5 6m`, accidentals `b7` /
    /// `#4`, quality suffix kept (`2m7`, `57/7`), slash bass as a degree (`1/3`). Minor
    /// keys are numbered from the relative major (`Am` in A minor is `6m`).
    /// `.noChord` / `.unknown` come back verbatim. Transposition-invariant: transposing
    /// the token and the key by the same amount yields the same string.
    ///
    /// A suffix that starts with a digit is parenthesised so it cannot run into the degree:
    /// `E7` in A minor reads `3(7)`, `C6/9` in C reads `1(6/9)`, `G7/B` in C reads `5(7)/7`.
    public static func number(for token: ChordToken, in key: SongKey) -> String {
        guard case let .chord(chord) = token else { return token.original }
        let tonic = key.relativeMajor.tonic.pitchClass
        let symbol = chord.symbol
        var text = degree(of: symbol.root.pitchClass, from: tonic)
        if let first = symbol.suffix.first, first.isNumber {
            text += "(\(symbol.suffix))"
        } else {
            text += symbol.suffix
        }
        if let bass = symbol.bass {
            text += "/" + degree(of: bass.pitchClass, from: tonic)
        }
        return text
    }

    /// The chord a Nashville number names in `key` (the inverse of `number(for:in:)`), for
    /// number entry in Nashville view: `1`, `4`, `6m`, `b7`, `#4`, `2m7`, `5/7`, `3(7)`,
    /// `1(6/9)`, `5(7)/7`. Degrees are numbered from the relative major in a minor key;
    /// letters follow `key` (`KeySpelling.preferred`) unless a `b`/`#` was typed. `nil`
    /// when `text` is not a number (letter chords, lyrics, malformed input) or the suffix
    /// is not a chord suffix.
    public static func chord(parsing text: String, in key: SongKey) -> ChordToken? {
        var rest = Substring(text.trimmingCharacters(in: .whitespaces))
        guard let root = parseDegree(&rest), let suffix = parseSuffix(&rest) else { return nil }
        var bass: Degree?
        if rest.first == "/" {
            rest = rest.dropFirst()
            guard let degree = parseDegree(&rest), rest.isEmpty else { return nil }
            bass = degree
        }
        guard rest.isEmpty || bass != nil else { return nil }
        var letters = spell(root, in: key) + suffix
        if let bass {
            letters += "/" + spell(bass, in: key)
        }
        let token = ChordToken(parsing: letters)
        guard case .chord = token else { return nil }
        return token
    }

    /// A degree as typed: semitones above the major tonic, and the accidental typed
    /// (-1, 0, 1).
    private typealias Degree = (offset: Int, accidental: Int)

    /// The quality after the degree: `(…)` for a suffix starting with a digit (`3(7)`),
    /// else up to a `/`. Leaves `text` at the `/` (or the end). `nil` when malformed.
    private static func parseSuffix(_ text: inout Substring) -> Substring? {
        if text.first == "(" {
            guard let close = matchingParenthesis(in: text) else { return nil }
            let suffix = text[text.index(after: text.startIndex) ..< close]
            text = text[text.index(after: close)...]
            return suffix.isEmpty ? nil : suffix
        }
        let slash = text.firstIndex(of: "/") ?? text.endIndex
        let suffix = text[..<slash]
        text = text[slash...]
        // A digit straight after the degree would read as another degree: `57` is `5(7)`.
        return suffix.first?.isNumber == true ? nil : suffix
    }

    /// A typed `b` or `#` is the accidental family the user wants (`b6` in C is `Ab`, `#5`
    /// is `G#`); a plain degree follows the key.
    private static func spell(_ degree: Degree, in key: SongKey) -> String {
        let pitch = key.relativeMajor.tonic.pitchClass.transposed(by: degree.offset)
        let (sharp, flat) = NoteClass.spellings(of: pitch)
        return switch degree.accidental {
        case -1: flat.chartName
        case 1: sharp.chartName
        default: KeySpelling.preferred(pitch, in: key).chartName
        }
    }

    /// Whether `text` starts like a Nashville number (a degree digit, or `b`/`#` and one),
    /// as opposed to a letter chord.
    public static func looksLikeNumber(_ text: String) -> Bool {
        var rest = Substring(text.trimmingCharacters(in: .whitespaces))
        if let first = rest.first, "b#\u{266D}\u{266F}".contains(first) {
            rest = rest.dropFirst()
        }
        return rest.first.map { ("1" ... "7").contains($0) } ?? false
    }

    /// The `)` closing the `(` that `text` starts with (suffixes nest: `5(7(#9))`).
    private static func matchingParenthesis(in text: Substring) -> Substring.Index? {
        var depth = 0
        for index in text.indices {
            switch text[index] {
            case "(": depth += 1
            case ")":
                depth -= 1
                if depth == 0 {
                    return index
                }
            default: continue
            }
        }
        return nil
    }

    /// Reads `b`/`#` plus a degree `1`...`7` off the front of `text`: semitones above the
    /// major tonic, and the accidental typed (-1, 0, 1).
    private static func parseDegree(_ text: inout Substring) -> Degree? {
        var accidental = 0
        if let first = text.first {
            switch first {
            case "\u{266D}", "b": accidental = -1
            case "\u{266F}", "#": accidental = 1
            default: break
            }
        }
        var rest = accidental == 0 ? text : text.dropFirst()
        guard let digit = rest.first?.wholeNumberValue, (1 ... 7).contains(digit) else {
            return nil
        }
        rest = rest.dropFirst()
        text = rest
        let major = [0, 2, 4, 5, 7, 9, 11]
        return ((major[digit - 1] + accidental + 12) % 12, accidental)
    }

    /// Degree names by semitones above the major tonic.
    private static let degreeNames = [
        "1",
        "b2",
        "2",
        "b3",
        "3",
        "4",
        "#4",
        "5",
        "b6",
        "6",
        "b7",
        "7",
    ]

    private static func degree(of pitchClass: PitchClass, from tonic: PitchClass) -> String {
        degreeNames[tonic.semitones(to: pitchClass)]
    }

    /// Key header for Nashville view: `"C"` for a major key, `"Am (rel. C)"` for a minor key.
    public static func header(for key: SongKey) -> String {
        switch key.mode {
        case .major: key.name
        case .minor: "\(key.name) (rel. \(key.relativeMajor.name))"
        }
    }
}
