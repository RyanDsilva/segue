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
    /// ambiguous.
    ///
    /// Tuned against the fixture key-detection table (`MusicTheoryKeyDetectionTests`): the
    /// clear-cut fixtures have relative gaps of 0.125 and up (closest: a vi-IV-I-V loop and
    /// a I-vi-IV-V song ending on V), the genuinely ambiguous ones 0.04 and below (`G C`,
    /// a `Dm G` vamp). 0.08 sits in the middle of that gap.
    public static let ambiguityMargin = 0.08

    // Score = mean diatonic fit (0 ... 1, one term per chord occurrence, so frequency
    // counts) + bonuses when the first / last chord is the key's tonic chord + a bonus
    // proportional to the share of tonic-chord occurrences. Range 0 ... 1 + the three
    // weights. Tuned against `MusicTheoryKeyDetectionTests`.
    static let firstChordWeight = 0.15
    static let lastChordWeight = 0.1
    static let tonicShareWeight = 0.2
    /// Fit of a chord whose root is diatonic but whose quality is not (secondary
    /// dominants, borrowed qualities). Non-diatonic roots score 0, diatonic chords 1.
    static let rootOnlyFit = 0.25

    /// - Parameter chords: every chord occurrence in song order (repeats included; order
    ///   matters for first/last weighting). `.noChord` / `.unknown` tokens are excluded by
    ///   the caller.
    /// - Returns: `nil` when `chords` is empty.
    public static func detect(_ chords: [ChartChord]) -> KeyDetection? {
        guard !chords.isEmpty else { return nil }
        let tones = chords.map(\.tones)
        let ranking = candidates
            .map { ScoredKey(key: $0, score: score(tones, in: $0)) }
            .enumerated()
            .sorted { lhs, rhs in
                lhs.element.score != rhs.element.score
                    ? lhs.element.score > rhs.element.score
                    : lhs.offset < rhs.offset
            }
            .map(\.element)
        let top = ranking[0].score
        let gap = top > 0 ? (top - ranking[1].score) / top : 0
        return KeyDetection(
            key: ranking[0].key,
            isAmbiguous: gap < ambiguityMargin,
            ranking: ranking,
        )
    }

    /// The 24 keys in tie-break order: by tonic pitch class from C, major before minor.
    private static let candidates: [SongKey] = (0 ..< 12).flatMap { pitchClass in
        KeyMode.allCases.map { SongKey(canonical: PitchClass(pitchClass), mode: $0) }
    }

    static func score(_ chords: [ChordTones], in key: SongKey) -> Double {
        guard let first = chords.first, let last = chords.last else { return 0 }
        let count = Double(chords.count)
        let meanFit = chords.map { fit($0, in: key) }.reduce(0, +) / count
        let tonicShare = Double(chords.count { isTonicChord($0, in: key) }) / count
        var score = meanFit + tonicShareWeight * tonicShare
        if isTonicChord(first, in: key) {
            score += firstChordWeight
        }
        if isTonicChord(last, in: key) {
            score += lastChordWeight
        }
        return score
    }

    /// 1 when every chord tone is in the key (in minor, chords on the 5th and 7th degree
    /// may use the harmonic minor's raised 7th: `E7` in A minor), `rootOnlyFit` when only
    /// the root is, else 0. A slash bass is ignored.
    static func fit(_ chord: ChordTones, in key: SongKey) -> Double {
        let tonic = key.tonic.pitchClass
        let scale = scale(of: key)
        let tones = Set(chord.formula.intervals.map { chord.root.transposed(by: $0) })
        if tones.isSubset(of: scale) {
            return 1
        }
        if key.mode == .minor {
            let leadingTone = tonic.transposed(by: 11)
            var harmonic = scale
            harmonic.remove(tonic.transposed(by: 10))
            harmonic.insert(leadingTone)
            let dominantRoots = [tonic.transposed(by: 7), leadingTone]
            if dominantRoots.contains(chord.root), tones.isSubset(of: harmonic) {
                return 1
            }
        }
        return scale.contains(chord.root) ? rootOnlyFit : 0
    }

    /// The chord on the key's tonic with the key's third (or no third: power / sus).
    static func isTonicChord(_ chord: ChordTones, in key: SongKey) -> Bool {
        guard chord.root == key.tonic.pitchClass else { return false }
        let intervals = Set(chord.formula.intervals)
        let hasMajorThird = intervals.contains(4)
        let hasMinorThird = intervals.contains(3)
        switch key.mode {
        case .major: return !hasMinorThird
        case .minor: return !hasMajorThird
        }
    }

    private static func scale(of key: SongKey) -> Set<PitchClass> {
        let offsets = switch key.mode {
        case .major: [0, 2, 4, 5, 7, 9, 11]
        case .minor: [0, 2, 3, 5, 7, 8, 10]
        }
        return Set(offsets.map { key.tonic.pitchClass.transposed(by: $0) })
    }
}
