import Foundation

// Walk-up analytics (P8-4b section 8.12): row 25 of the closed vocabulary. Enums only, no
// song data. The kinds and feels mirror `WalkUpKind` and `BassGenre` (Services does not
// import MusicTheory); `WalkUpTests` keeps them in step.

/// Row 25: `Segue.Bass.walkUpPicked`, one per choice in the walk-up picker, daily per kind,
/// rank and feel. It answers which kinds musicians reject (research section 7.5).
public struct WalkUpPickSummary: Sendable, Hashable {
    public var kind: WalkUpPickKind
    public var rank: WalkUpRank
    public var genre: WalkUpFeel

    public init(kind: WalkUpPickKind, rank: WalkUpRank, genre: WalkUpFeel) {
        self.kind = kind
        self.rank = rank
        self.genre = genre
    }
}

/// The kind of the chosen candidate (`WalkUpKind`'s raw values).
public enum WalkUpPickKind: String, Sendable, CaseIterable {
    case hold
    case scaleWalk
    case scaleChrom
    case diatonicNeighbour
    case chromBelow
    case chromAbove
    case fifth
    case doubleChromAbove
    case octavePickup
}

/// Where the choice sat: the suggestion, another option, "Nothing here", or a reset back to
/// the suggestion.
public enum WalkUpRank: String, Sendable, CaseIterable {
    case top
    case alternate
    case nothing
    case reset
}

/// The song's feel when choosing (`BassGenre`'s raw values).
public enum WalkUpFeel: String, Sendable, CaseIterable {
    case pop
    case rock
    case worship
    case country
    case bollywood
}
