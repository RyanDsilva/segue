// Owner: unit A (MusicTheory). Frozen interface: docs/phases/1-interfaces.md.

/// Nashville number rendering (phase 1 spec, "Nashville rendering").
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
