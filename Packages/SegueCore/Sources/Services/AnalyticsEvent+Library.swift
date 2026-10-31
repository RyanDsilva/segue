// Row 3 parameters, in their own file so AnalyticsEvent.swift stays within the file
// length limit.

/// Row 3 parameters.
public struct LibrarySnapshot: Sendable, Hashable {
    public var songs: SongBucket
    public var setlists: SmallBucket
    public var gigs: SmallBucket
    public var welcomeSongsLeft: WelcomeSongsLeft
    public var customShapes: Bool
    /// P8-8 section 8: songs without a `{tempo}` (they have no time in a set).
    public var noTempo: SongBucket

    public init(
        songs: SongBucket,
        setlists: SmallBucket,
        gigs: SmallBucket,
        welcomeSongsLeft: WelcomeSongsLeft,
        customShapes: Bool,
        noTempo: SongBucket = .zero,
    ) {
        self.songs = songs
        self.setlists = setlists
        self.gigs = gigs
        self.welcomeSongsLeft = welcomeSongsLeft
        self.customShapes = customShapes
        self.noTempo = noTempo
    }
}
