// Owner: unit A (MusicTheory). Frozen interface: docs/phases/1-interfaces.md.

import Foundation
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
        let bassText = bass.map { "/\($0.chartName)" } ?? ""
        return root.chartName + suffix + bassText
    }

    /// Parses chord text such as `F#m7b5`, `G/B` or `C6/9` (no surrounding whitespace).
    /// Strict: an upper-case root letter, at most one accidental, a suffix our interval table
    /// understands, and an optional `/` + note bass. `nil` otherwise (including `N.C.`).
    public init?(parsing text: String) {
        let body = Substring(text)
        guard let (root, rootLength) = NoteClass.prefix(of: body) else { return nil }
        var suffix = body.dropFirst(rootLength)
        var bass: NoteClass?
        if let slash = suffix.lastIndex(of: "/"),
           let note = NoteClass(chartName: suffix[suffix.index(after: slash)...])
        {
            bass = note
            suffix = suffix[..<slash]
        }
        guard let formula = ChordFormula.parse(suffix: String(suffix)) else { return nil }
        self.init(root: root, suffix: String(suffix), formula: formula, bass: bass)
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
    /// key scoring; `nil` when Tonic has no `ChordType` with the same pitch content (e.g.
    /// `5`, `7alt`). Such chords still transpose and get diagrams via `symbol.formula`.
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
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if Self.noChordSpellings.contains(trimmed.uppercased()) {
            self = .noChord(original: text)
        } else if let symbol = ChordSymbol(parsing: trimmed) {
            let tonic = TonicBridge.chord(root: symbol.root, formula: symbol.formula)
            self = .chord(ChartChord(tonic: tonic, symbol: symbol, original: text))
        } else {
            self = .unknown(UnknownChord(original: text))
        }
    }

    /// Accepted no-chord spellings (compared upper-cased).
    private static let noChordSpellings: Set = ["N.C.", "N.C", "NC", "N/C"]

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
