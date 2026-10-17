// Owner: unit B (Diagrams). Frozen interface: docs/phases/1-interfaces.md.

/// A barre: one finger across several strings at one fret.
public struct Barre: Sendable, Hashable, Codable {
    /// Fret relative to `GuitarShape.baseFret` (1 = the base fret), like `frets`.
    public var fret: Int
    /// String indices covered, 0 = lowest string, inclusive.
    public var strings: ClosedRange<Int>
    /// Finger number 1 ... 4 when known.
    public var finger: Int?

    public init(fret: Int, strings: ClosedRange<Int>, finger: Int? = nil) {
        self.fret = fret
        self.strings = strings
        self.finger = finger
    }
}

/// A guitar chord fingering, in ChordPro `{define}` terms.
public struct GuitarShape: Sendable, Hashable, Codable {
    /// One entry per string, lowest string first: `nil` = muted, `0` = open, `n >= 1` =
    /// the n-th fret counting from `baseFret` (so with `baseFret` 3, `1` is the 3rd fret).
    public var frets: [Int?]
    /// One entry per string: finger 1 ... 4, `nil` when unspecified or not fretted.
    public var fingers: [Int?]
    /// Absolute fret shown at the top of the diagram, >= 1.
    public var baseFret: Int
    public var barres: [Barre]

    public init(frets: [Int?], fingers: [Int?] = [], baseFret: Int = 1, barres: [Barre] = []) {
        self.frets = frets
        self.fingers = fingers
        self.baseFret = baseFret
        self.barres = barres
    }

    /// Absolute fret per string (`nil` muted, 0 open), i.e. `baseFret - 1 + fret` for
    /// fretted strings.
    public var absoluteFrets: [Int?] {
        frets.map { fret in
            guard let fret else { return nil }
            return fret == 0 ? 0 : baseFret - 1 + fret
        }
    }

    /// Sounding MIDI pitches low to high for `tuning` (muted strings omitted). A capo is
    /// not included: shapes are always relative to the capo.
    public func pitches(in tuning: Tuning) -> [Int] {
        zip(tuning.strings, absoluteFrets).compactMap { open, fret in
            fret.map { open + $0 }
        }
    }
}

/// Where a displayed guitar shape came from (lookup order, first wins).
public enum ShapeSource: String, Sendable, Hashable, Codable {
    /// A `{define}` in the song.
    case songDefine
    /// The user's shape library (app support JSON).
    case userLibrary
    /// Our hand-checked overrides (standard tuning only).
    case curated
    /// The algorithmic generator for the current tuning.
    case generated
}

/// A shape plus its provenance.
public struct ResolvedGuitarShape: Sendable, Hashable {
    public var shape: GuitarShape
    public var source: ShapeSource

    public init(shape: GuitarShape, source: ShapeSource) {
        self.shape = shape
        self.source = source
    }
}
