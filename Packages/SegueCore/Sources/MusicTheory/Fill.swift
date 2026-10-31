// P8-7c (docs/phases/8-workstreams/P8-7-time-model-and-fills.md section 11, R166-R168).
// Bass fills over a span of chords: the closed vocabularies a saved part's provenance uses.
// Pure.

/// A fill's rhythm family (section 11.3). Closed: widening it is a spec change (R168 Q10).
/// Declaration order is the ranking's tie-break.
public enum FillFamily: String, Sendable, Hashable, Codable, CaseIterable {
    /// One note per pulse, a walking line.
    case walk
    /// Eighth pickups into the landing.
    case pickup
    /// Sixteenth runs.
    case run
    /// Eighth or sixteenth triplets.
    case triplet
    /// Root, fifth and octave figures.
    case octave
    /// Anticipations, stops and rest-then-approach.
    case push

    /// The candidate row's name in the fill editor.
    public var title: String {
        switch self {
        case .walk: "Walk"
        case .pickup: "Pickup"
        case .run: "Sixteenth run"
        case .triplet: "Triplets"
        case .octave: "Octaves"
        case .push: "Push"
        }
    }
}

/// Where a saved fill came from in the candidate list: A-D, "More" (the fifth), or written
/// from scratch.
public enum CandidateRank: String, Sendable, Hashable, Codable, CaseIterable {
    // The option letters the sheet shows (section 9.5 stores them as "a" ... "d").
    // swiftlint:disable identifier_name
    case a
    case b
    case c
    case d
    // swiftlint:enable identifier_name
    case more
    case scratch

    /// The rank of the candidate at `index` (0-based) in `Fill.candidates`.
    public init(index: Int) {
        self = switch index {
        case 0: .a
        case 1: .b
        case 2: .c
        case 3: .d
        default: .more
        }
    }
}
