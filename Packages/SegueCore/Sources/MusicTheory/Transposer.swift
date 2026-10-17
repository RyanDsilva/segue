// Owner: unit A (MusicTheory). Frozen interface: docs/phases/1-interfaces.md.

/// Transposes chord tokens by a number of semitones, spelling results by the target key.
///
/// Both the view transform (preview, live view) and "Apply transposition to source" use
/// this; neither re-implements spelling.
public struct Transposer: Sendable, Hashable {
    /// Net shift, any integer (normalised internally; 12 is a no-op).
    public let semitones: Int
    /// Key of the chords before transposition (declared or inferred); `nil` when unknown.
    public let sourceKey: SongKey?
    /// Key of the chords after transposition; spelling follows it. `nil` when `sourceKey` is.
    public let targetKey: SongKey?

    /// Target key derived as `sourceKey?.transposed(by: semitones)`.
    public init(semitones: Int, sourceKey: SongKey?) {
        self.semitones = semitones
        self.sourceKey = sourceKey
        targetKey = sourceKey?.transposed(by: semitones)
    }

    /// Explicit target key (e.g. to restore an original spelling); `semitones` is the
    /// distance between the two tonics.
    public init(from sourceKey: SongKey, to targetKey: SongKey) {
        self.sourceKey = sourceKey
        self.targetKey = targetKey
        semitones = sourceKey.tonic.pitchClass.semitones(to: targetKey.tonic.pitchClass)
    }

    /// Whether this transposer changes nothing (`semitones % 12 == 0`).
    public var isIdentity: Bool {
        PitchClass(semitones).rawValue == 0
    }

    /// The transposed token. `.noChord` and `.unknown` come back unchanged; an identity
    /// transposition returns the token unchanged (keeping `original`). A transposed chord's
    /// `original` is its canonical `symbol.text` (root and bass re-spelled, suffix kept).
    public func transpose(_ token: ChordToken) -> ChordToken {
        fatalError("unimplemented: unit A")
    }

    /// `transpose(.chord(chord))` for a parsed chord.
    public func transpose(_ chord: ChartChord) -> ChartChord {
        fatalError("unimplemented: unit A")
    }
}
