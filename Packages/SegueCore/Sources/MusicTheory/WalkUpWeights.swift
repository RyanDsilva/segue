// P8-4b (docs/phases/8-workstreams/P8-4-bass.md section 8.2, research section 3.4). The
// walk-up ranking weights, one static value so tuning after the by-ear check in P8-6a
// changes numbers only, never code.

/// The ranking weights [R3.4]. Every term a candidate's score sums is one of these.
public struct WalkUpWeights: Sendable, Hashable {
    /// Genre prior per kind (0-3), the research table verbatim; `unknown` is the column for
    /// `genre == nil`.
    public var prior: [WalkUpKind: [BassGenre: Double]]
    public var unknownPrior: [WalkUpKind: Double]
    /// A note a half step from chord A's fifth or seventh (not the target-side approach).
    public var clash: Double
    /// The last note a half step from the target.
    public var resolutionHalfStep: Double
    /// The last note a whole step from the target.
    public var resolutionWholeStep: Double
    /// The fifth of the target.
    public var resolutionFifth: Double
    /// Up when B's section raises the energy, down when it settles.
    public var directionEnergy: Double
    /// With no section energy known: the candidate moves the short way from A to B (the
    /// pre-research rule always did; this keeps the legacy top-1, section 8.3).
    public var directionShortest: Double
    /// Country / gospel: the walk up a fourth (I-IV, V-I).
    public var directionCountryFourth: Double
    /// Per note beyond `maxNotes`.
    public var lengthOver: Double
    /// Exactly filling the slots when the chord has 4 or more beats.
    public var lengthExact: Double
    /// Minor key, B is i, the candidate ends on the raised 7.
    public var minorTonic: Double
    /// With that: `F G#` (harmonic) in a Bollywood feel, `F# G#` (melodic) otherwise.
    public var minorTonicForm: Double
    /// `scaleWalk` and `scaleChrom` into a new section.
    public var intoSection: Double
    /// Under rule S2: the "nothing" candidate and the passing note.
    public var writtenLineHold: Double
    public var writtenLinePassing: Double
    /// Candidates below this score are not offered.
    public var floor: Double
    /// The most candidates offered.
    public var limit: Int

    public static let standard = Self(
        prior: [
            .scaleWalk: [.pop: 3, .rock: 2, .worship: 3, .country: 3, .bollywood: 3],
            .scaleChrom: [.pop: 1, .rock: 3, .worship: 0, .country: 2, .bollywood: 1],
            .diatonicNeighbour: [.pop: 2, .rock: 2, .worship: 2, .country: 2, .bollywood: 2],
            .chromBelow: [.pop: 2, .rock: 3, .worship: 1, .country: 2, .bollywood: 1],
            .chromAbove: [.pop: 0, .rock: 2, .worship: 0, .country: 2, .bollywood: 0],
            .fifth: [.pop: 2, .rock: 2, .worship: 2, .country: 1, .bollywood: 1],
            .doubleChromAbove: [.pop: 0, .rock: 1, .worship: 0, .country: 2, .bollywood: 0],
            .octavePickup: [.pop: 1, .rock: 2, .worship: 1, .country: 1, .bollywood: 1],
        ],
        unknownPrior: [
            .scaleWalk: 3, .scaleChrom: 1, .diatonicNeighbour: 2, .chromBelow: 2,
            .chromAbove: 1, .fifth: 2, .doubleChromAbove: 0, .octavePickup: 1,
        ],
        clash: -5,
        resolutionHalfStep: 2,
        resolutionWholeStep: 1,
        resolutionFifth: 1,
        directionEnergy: 1,
        directionShortest: 1.5,
        directionCountryFourth: 1,
        lengthOver: -2,
        lengthExact: 0.5,
        minorTonic: 2,
        minorTonicForm: 1,
        intoSection: 1,
        writtenLineHold: 2,
        writtenLinePassing: 1,
        floor: 3,
        limit: 4,
    )

    /// The genre prior of `kind` (0 for `hold`, which only rule S2 produces).
    public func prior(_ kind: WalkUpKind, genre: BassGenre?) -> Double {
        guard let genre else { return unknownPrior[kind] ?? 0 }
        return prior[kind]?[genre] ?? 0
    }
}
