// Owner: unit A (MusicTheory). Frozen interface: docs/phases/1-interfaces.md.

import Tonic

/// A chord symbol as an author wrote it, parsed: `F#m7b5`, `Bbmaj9`, `G/B`, `C7(#9)`, `C-7`,
/// `C6/9`, `Cadd9`, `G13sus4`.
public struct ChordSymbol: Sendable, Hashable {
    /// Root as spelled (`F#`, `Bb`). Tonic `NoteClass` keeps letter + accidental.
    public var root: NoteClass
    /// Everything between the root and the slash bass, verbatim (`"m7b5"`, `"-7"`,
    /// `"7(#9)"`, `"6/9"`; `""` for a major triad). Rendering keeps it as written, so a
    /// transposed chord changes only its root and bass spelling.
    public var suffix: String
    /// Interval content of `suffix` (from `ChordFormula.parse(suffix:)`).
    public var formula: ChordFormula
    /// Slash bass as spelled (`G/B` -> B); `nil` when there is none. `C6/9` has no bass:
    /// `/9` is part of the suffix.
    public var bass: NoteClass?

    public init(root: NoteClass, suffix: String, formula: ChordFormula, bass: NoteClass? = nil) {
        self.root = root
        self.suffix = suffix
        self.formula = formula
        self.bass = bass
    }

    /// Canonical text: root + suffix + (`/` + bass). Used only for chords that were
    /// transformed (transposed); untouched chords render their `original` text.
    public var text: String {
        fatalError("unimplemented: unit A")
    }

    /// Pitch content (root, bass, formula) for diagram generators and key scoring.
    public var tones: ChordTones {
        let rootClass = root.pitchClass
        let bassClass = bass?.pitchClass
        return ChordTones(
            root: rootClass,
            bass: bassClass == rootClass ? nil : bassClass,
            formula: formula,
        )
    }
}

/// A chord the parser understood.
public struct ChartChord: Sendable, Hashable {
    /// Tonic's model of the chord (root + `ChordType`), used for transposition helpers and
    /// key scoring; `nil` when Tonic has no matching `ChordType` (e.g. `7(#9)`, `6/9`,
    /// `13sus4`). Such chords still transpose and get diagrams via `symbol.formula`.
    public var tonic: Chord?
    public var symbol: ChordSymbol
    /// The verbatim token (without brackets) for byte-identical round trips.
    public var original: String

    public init(tonic: Chord?, symbol: ChordSymbol, original: String) {
        self.tonic = tonic
        self.symbol = symbol
        self.original = original
    }

    /// Shorthand for `symbol.tones`.
    public var tones: ChordTones {
        symbol.tones
    }
}

/// A token that is not a chord symbol we understand. Displayed verbatim, never transposed,
/// flagged in the editor.
public struct UnknownChord: Sendable, Hashable {
    public var original: String

    public init(original: String) {
        self.original = original
    }
}

/// Anything that can stand between `[` and `]` in a lyric line.
public enum ChordToken: Sendable, Hashable {
    case chord(ChartChord)
    /// `N.C.` / `NC` / `N.C`: an explicit no-chord. Displayed verbatim, never transposed,
    /// never flagged.
    case noChord(original: String)
    case unknown(UnknownChord)

    /// Parses chord text as written between brackets. Never fails: anything not understood
    /// becomes `.unknown`. Surrounding whitespace is kept in `original` but ignored when
    /// parsing.
    public init(parsing text: String) {
        fatalError("unimplemented: unit A")
    }

    /// The verbatim token text.
    public var original: String {
        switch self {
        case let .chord(chord): chord.original
        case let .noChord(original): original
        case let .unknown(unknown): unknown.original
        }
    }

    /// The parsed chord, if any.
    public var chord: ChartChord? {
        if case let .chord(chord) = self {
            return chord
        }
        return nil
    }
}
