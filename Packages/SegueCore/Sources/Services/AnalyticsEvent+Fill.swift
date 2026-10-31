import Foundation

// Fill analytics (P8-7 section 15): row 26 of the closed vocabulary. Enums, buckets and
// flags only, no song data. The families, ranks and feels mirror `FillFamily`,
// `CandidateRank` and `BassGenre` (Services does not import MusicTheory); `FillEditorTests`
// keeps them in step.

/// Row 26: `Segue.Bass.fillSaved`, one per fill saved in the fill editor, daily per family,
/// rank and edited. It answers whether people keep the generated fills, which families win
/// per feel, whether the piano roll is used and whether key-change fills matter.
public struct FillSavedSummary: Sendable, Hashable {
    public var family: FillSavedFamily
    public var rank: FillSavedRank
    /// Changed from the candidate (or the saved fill) it started from.
    public var edited: Bool
    /// Where it was edited.
    public var view: FillSavedView
    /// The span's chords, landing included.
    public var chords: SmallBucket
    /// The span crosses a key change.
    public var keyChange: Bool
    public var genre: WalkUpFeel
    public var shows: FillSavedShows
    /// Saved over estimated chord lengths (the song's rule): whether the lane is used first.
    public var estimated: Bool

    public init(
        family: FillSavedFamily,
        rank: FillSavedRank,
        edited: Bool,
        view: FillSavedView,
        chords: SmallBucket,
        keyChange: Bool,
        genre: WalkUpFeel,
        shows: FillSavedShows,
        estimated: Bool,
    ) {
        self.family = family
        self.rank = rank
        self.edited = edited
        self.view = view
        self.chords = chords
        self.keyChange = keyChange
        self.genre = genre
        self.shows = shows
        self.estimated = estimated
    }

    var params: [String: String] {
        [
            "segue.family": family.rawValue,
            "segue.rank": rank.rawValue,
            "segue.edited": String(edited),
            "segue.view": view.rawValue,
            "segue.chords": chords.rawValue,
            "segue.keyChange": String(keyChange),
            "segue.genre": genre.rawValue,
            "segue.shows": shows.rawValue,
            "segue.estimated": String(estimated),
        ]
    }
}

/// The saved fill's rhythm family (`FillFamily`'s raw values), or written from scratch.
public enum FillSavedFamily: String, Sendable, CaseIterable {
    case walk
    case pickup
    case run
    case triplet
    case octave
    case push
    case scratch
}

/// Which candidate it started from (`CandidateRank`'s raw values).
public enum FillSavedRank: String, Sendable, CaseIterable {
    // The option letters (as `CandidateRank`).
    // swiftlint:disable identifier_name
    case a
    case b
    case c
    case d
    // swiftlint:enable identifier_name
    case more
    case scratch
}

/// Where the fill was edited before saving.
public enum FillSavedView: String, Sendable, CaseIterable {
    case fretboard
    case pianoRoll
    case both
    /// Saved as generated.
    case unedited = "none"
}

/// "Shows on": every time, only some plays, or the last.
public enum FillSavedShows: String, Sendable, CaseIterable {
    case all
    case only
    case last
}
