import Foundation

// Song metadata analytics (P8-8 section 8): rows 29 and 30 of the closed vocabulary. Enums and
// buckets only: never a name, a title, an album or typed text.

/// Row 29: `Segue.Song.artistSplit`, one per accepted song whose artist the paste or import
/// split, daily per (source, separator, outcome).
public struct ArtistSplitSummary: Sendable, Hashable {
    public var source: ArtistSplitSource
    /// Artists the split made.
    public var parts: SmallBucket
    public var separator: ArtistSplitSeparator
    public var outcome: ArtistSplitOutcome

    public init(
        source: ArtistSplitSource,
        parts: SmallBucket,
        separator: ArtistSplitSeparator,
        outcome: ArtistSplitOutcome,
    ) {
        self.source = source
        self.parts = parts
        self.separator = separator
        self.outcome = outcome
    }

    var params: [String: String] {
        [
            "segue.source": source.rawValue,
            "segue.parts": parts.rawValue,
            "segue.separator": separator.rawValue,
            "segue.outcome": outcome.rawValue,
        ]
    }
}

/// Where the split came from: a paste, or a file import that needed conversion.
public enum ArtistSplitSource: String, Sendable, CaseIterable {
    case paste
    case `import`
}

/// Which separator split it (`ArtistSeparator`'s raw values); `mixed` for more than one.
public enum ArtistSplitSeparator: String, Sendable, CaseIterable {
    case comma
    case ampersand
    case feat
    case mixed

    /// From the raw values of the separators that split a value; nil for none.
    public init?(separators: Set<String>) {
        guard let only = separators.first else { return nil }
        if separators.count > 1 {
            self = .mixed
        } else if let value = Self(rawValue: only), value != .mixed {
            self = value
        } else {
            return nil
        }
    }
}

/// What the user did with the split before Accept: kept it, merged it back with Keep as
/// one, or edited the artists by hand.
public enum ArtistSplitOutcome: String, Sendable, CaseIterable {
    case kept
    case merged
    case edited
}

/// Row 30: `Segue.Setlist.timed`, when the builder leaves a setlist with 1+ songs, daily per
/// target: does timeline time cover real sets, how many songs lack a tempo, do arranged slots
/// matter.
public struct SetlistTimedSummary: Sendable, Hashable {
    public var songs: SmallBucket
    public var noTempo: SmallBucket
    public var noChords: SmallBucket
    public var arranged: SmallBucket
    /// Every known slot rests on default chord lengths.
    public var estimatedOnly: Bool
    public var target: SetlistTimedTarget

    public init(
        songs: SmallBucket,
        noTempo: SmallBucket,
        noChords: SmallBucket,
        arranged: SmallBucket,
        estimatedOnly: Bool,
        target: SetlistTimedTarget,
    ) {
        self.songs = songs
        self.noTempo = noTempo
        self.noChords = noChords
        self.arranged = arranged
        self.estimatedOnly = estimatedOnly
        self.target = target
    }

    var params: [String: String] {
        [
            "segue.songs": songs.rawValue,
            "segue.noTempo": noTempo.rawValue,
            "segue.noChords": noChords.rawValue,
            "segue.arranged": arranged.rawValue,
            "segue.estimatedOnly": String(estimatedOnly),
            "segue.target": target.rawValue,
        ]
    }
}

/// The set's known total against its target: none set, under, within the assistant's
/// tolerance, or over.
public enum SetlistTimedTarget: String, Sendable, CaseIterable {
    case noTarget = "none"
    case under
    case within
    case over
}
