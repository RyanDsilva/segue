import Library
import MusicTheory
import Services

/// Row 25's summary (P8-4b 8.12) for a choice in the walk-up picker: the chosen kind, where
/// it ranked, and the song's feel. No song data.
extension WalkUpPickSummary {
    /// `candidate` chosen on `change` (nil: "Nothing here").
    static func choosing(
        _ candidate: WalkUpCandidate?,
        on change: ChordChange,
        feel: BassGenre,
    ) -> Self {
        let rank: WalkUpRank = if let candidate {
            change.candidates.first.map {
                $0.kind == candidate.kind && $0.offsets == candidate.offsets
            } == true ? .top : .alternate
        } else {
            .nothing
        }
        return Self(
            kind: WalkUpPickKind(rawValue: (candidate?.kind ?? .hold).rawValue) ?? .hold,
            rank: rank,
            genre: WalkUpFeel(rawValue: feel.rawValue) ?? .pop,
        )
    }

    /// The pick on `change` reset to the suggestion (its kind is the suggestion's).
    static func resetting(_ change: ChordChange, feel: BassGenre) -> Self {
        Self(
            kind: WalkUpPickKind(rawValue: (change.candidates.first?.kind ?? .hold).rawValue)
                ?? .hold,
            rank: .reset,
            genre: WalkUpFeel(rawValue: feel.rawValue) ?? .pop,
        )
    }
}
