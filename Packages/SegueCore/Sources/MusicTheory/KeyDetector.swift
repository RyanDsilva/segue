// Owner: unit A (MusicTheory). Frozen interface: docs/phases/1-interfaces.md.

/// One candidate key and its score.
public struct ScoredKey: Sendable, Hashable {
    public var key: SongKey
    /// Higher is better; scale is unit A's (documented with the scorer).
    public var score: Double

    public init(key: SongKey, score: Double) {
        self.key = key
        self.score = score
    }
}

/// Outcome of deterministic key detection for a song without `{key}`.
public struct KeyDetection: Sendable, Hashable {
    /// The winner (shown as "inferred" until the user confirms it).
    public var key: SongKey
    /// True when the top two scores are within `KeyDetector.ambiguityMargin`; phase 3's AI
    /// cleanup may resolve only these.
    public var isAmbiguous: Bool
    /// All 24 major/minor keys, best first (ties broken deterministically).
    public var ranking: [ScoredKey]

    public init(key: SongKey, isAmbiguous: Bool, ranking: [ScoredKey]) {
        self.key = key
        self.isAmbiguous = isAmbiguous
        self.ranking = ranking
    }
}

/// Scores every major/minor key against a song's chords (diatonic fit, weighted by first
/// and last chord and by frequency). Pure and deterministic.
public enum KeyDetector {
    /// Score gap (top minus runner-up, relative to the top score) below which the result is
    /// ambiguous. Placeholder value: unit A tunes it against the fixture key-detection table.
    public static let ambiguityMargin = 0.1

    /// - Parameter chords: every chord occurrence in song order (repeats included; order
    ///   matters for first/last weighting). `.noChord` / `.unknown` tokens are excluded by
    ///   the caller.
    /// - Returns: `nil` when `chords` is empty.
    public static func detect(_ chords: [ChartChord]) -> KeyDetection? {
        fatalError("unimplemented: unit A")
    }
}
