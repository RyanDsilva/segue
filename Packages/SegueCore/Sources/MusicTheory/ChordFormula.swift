// Owner: unit A (MusicTheory). Frozen interface: docs/phases/1-interfaces.md.
// `ChordTones` is the contract between A (producer) and B (diagram generators, consumer).

/// The interval content of a chord quality, independent of its root: what a suffix such as
/// `m7b5`, `7(#9)`, `6/9` or `13sus4` means.
///
/// Built from our own interval table (decisions.md, phase 1 round 2), so chords Tonic cannot
/// model still have pitch content.
public struct ChordFormula: Sendable, Hashable, Codable {
    /// Semitones above the root, ascending and unique, starting with 0. Values may exceed 11
    /// for extensions (a 9th is 14, a #9 is 15) so a voicing generator can tell a 9th from a
    /// 2nd; reduce `% 12` for pitch classes.
    public var intervals: [Int]
    /// The subset of `intervals` a voicing must contain: the root, the 3rd (or the sus
    /// tone), the 7th when present, and any altered tone. Everything else (typically the
    /// 5th, the 11th under a 13th) may be omitted by a generator.
    public var essential: [Int]

    public init(intervals: [Int], essential: [Int]) {
        self.intervals = intervals
        self.essential = essential
    }

    /// The formula for a chord suffix as written after the root, e.g. `""` (major), `"m"`,
    /// `"-7"`, `"maj9"`, `"7(#9)"`, `"6/9"`, `"add9"`, `"13sus4"`, `"m7b5"`, `"5"`.
    /// `nil` when the suffix is not understood (the token is then an `UnknownChord`).
    public static func parse(suffix: String) -> Self? {
        ChordFormulaParser.parse(suffix)
    }
}

/// Concrete pitch content of one chord: root, optional slash bass and formula. This is what
/// the guitar and piano generators (unit B) consume; they never parse chord text.
public struct ChordTones: Sendable, Hashable, Codable {
    public var root: PitchClass
    /// The slash bass when it differs from the root (`G/B` -> B); `nil` otherwise. A
    /// generator must make this the lowest sounding note, else the root.
    public var bass: PitchClass?
    public var formula: ChordFormula

    public init(root: PitchClass, bass: PitchClass? = nil, formula: ChordFormula) {
        self.root = root
        self.bass = bass
        self.formula = formula
    }

    /// The note that must sound lowest: `bass ?? root`.
    public var lowest: PitchClass {
        bass ?? root
    }

    /// Every pitch class of the chord (formula tones plus the bass), unique, sorted.
    public var pitchClasses: [PitchClass] {
        var set = Set(formula.intervals.map { root.transposed(by: $0) })
        if let bass {
            set.insert(bass)
        }
        return set.sorted()
    }

    /// The pitch classes a voicing must contain (essential intervals plus the bass).
    public var essentialPitchClasses: [PitchClass] {
        var set = Set(formula.essential.map { root.transposed(by: $0) })
        if let bass {
            set.insert(bass)
        }
        return set.sorted()
    }
}
