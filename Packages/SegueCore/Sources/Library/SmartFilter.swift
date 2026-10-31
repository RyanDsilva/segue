// Phase 3 (P3-6, R71, R72): saved smart filters. A smart filter is a named predicate over
// the library, stored as `filters/<slug>.filter.json` and compiled to the in-memory
// `SongFilter` matcher. Lengths come from `{duration}` (R91); the play-history condition
// is "never played".

import Foundation
import Support

/// Stable identity of a smart filter (ULID), unchanged by renames.
public struct SmartFilterID: Sendable, Hashable, Comparable, Codable, CustomStringConvertible {
    public let ulid: ULID

    public init(_ ulid: ULID) {
        self.ulid = ulid
    }

    public var description: String {
        ulid.description
    }

    public static func < (lhs: Self, rhs: Self) -> Bool {
        lhs.ulid < rhs.ulid
    }

    public init(from decoder: any Decoder) throws {
        ulid = try ULID(from: decoder)
    }

    public func encode(to encoder: any Encoder) throws {
        try ulid.encode(to: encoder)
    }
}

/// Inclusive numeric bounds of a smart filter condition; a nil side is open.
public struct SmartFilterRange: Sendable, Hashable, Codable {
    public var min: Double?
    public var max: Double?

    public init(min: Double? = nil, max: Double? = nil) {
        self.min = min
        self.max = max
    }

    /// Whether neither side is set (the condition is off).
    public var isOpen: Bool {
        min == nil && max == nil
    }
}

/// What a smart filter asks of a song. Every condition that is set must hold (AND); an
/// empty or nil condition constrains nothing. Lists keep the user's order on disk.
public struct SmartFilterConditions: Sendable, Hashable, Codable {
    /// Every one of these tags (case-insensitive).
    public var allTags: [String]
    /// At least one of these tags.
    public var anyTags: [String]
    /// None of these tags.
    public var noneTags: [String]
    /// Any of these proficiency levels; a song without one never matches.
    public var proficiencies: [Proficiency]
    /// Any of these keys, compared like the phase 2 key filter (written or detected key,
    /// enharmonics match).
    public var keys: [String]
    /// `{tempo}` in BPM; a song without a tempo never matches.
    public var tempo: SmartFilterRange?
    /// `{duration}` in seconds; a song without a length never matches (R91).
    public var length: SmartFilterRange?
    /// Never played in a finished show.
    public var neverPlayed: Bool
    /// "Artist is any of" (P8-8 section 3.5): names as written; a song matches when any of
    /// its artists (split, `ArtistNames.forms`) meets any of these.
    public var artists: [String]
    /// "Movie / Album is any of" (P8-8 section 4.4): whole names, compared normalized.
    public var albums: [String]

    public init(
        allTags: [String] = [],
        anyTags: [String] = [],
        noneTags: [String] = [],
        proficiencies: [Proficiency] = [],
        keys: [String] = [],
        tempo: SmartFilterRange? = nil,
        length: SmartFilterRange? = nil,
        neverPlayed: Bool = false,
        artists: [String] = [],
        albums: [String] = [],
    ) {
        self.allTags = allTags
        self.anyTags = anyTags
        self.noneTags = noneTags
        self.proficiencies = proficiencies
        self.keys = keys
        self.tempo = tempo
        self.length = length
        self.neverPlayed = neverPlayed
        self.artists = artists
        self.albums = albums
    }

    private enum CodingKeys: String, CodingKey {
        case allTags
        case anyTags
        case noneTags
        case proficiencies
        case keys
        case tempo
        case length
        case neverPlayed
        case artists
        case albums
    }

    /// Missing keys take their empty value, so a hand-written file may list only what it
    /// uses.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        allTags = try container.decodeIfPresent([String].self, forKey: .allTags) ?? []
        anyTags = try container.decodeIfPresent([String].self, forKey: .anyTags) ?? []
        noneTags = try container.decodeIfPresent([String].self, forKey: .noneTags) ?? []
        proficiencies = try container
            .decodeIfPresent([Proficiency].self, forKey: .proficiencies) ?? []
        keys = try container.decodeIfPresent([String].self, forKey: .keys) ?? []
        tempo = try container.decodeIfPresent(SmartFilterRange.self, forKey: .tempo)
        length = try container.decodeIfPresent(SmartFilterRange.self, forKey: .length)
        neverPlayed = try container.decodeIfPresent(Bool.self, forKey: .neverPlayed) ?? false
        artists = try container.decodeIfPresent([String].self, forKey: .artists) ?? []
        albums = try container.decodeIfPresent([String].self, forKey: .albums) ?? []
    }

    /// How many conditions are set (analytics' conditions bucket, the sidebar's summary).
    public var count: Int {
        setFlags.count(where: \.self)
    }

    /// Whether no condition is set (the filter matches every song).
    public var isEmpty: Bool {
        !setFlags.contains(true)
    }

    /// One flag per condition kind: whether it is set.
    private var setFlags: [Bool] {
        [
            !allTags.isEmpty, !anyTags.isEmpty, !noneTags.isEmpty, !proficiencies.isEmpty,
            !keys.isEmpty, tempo.map { !$0.isOpen } ?? false, length.map { !$0.isOpen } ?? false,
            neverPlayed, !artists.isEmpty, !albums.isEmpty,
        ]
    }

    /// Whether any condition refers to play history (callers then pass play stats).
    public var usesPlayHistory: Bool {
        neverPlayed
    }

    /// The in-memory matcher for these conditions; `playStats` is the play-history
    /// snapshot "never played" is checked against.
    public func compiled(playStats: [SongID: PlayStats] = [:]) -> SongFilter {
        var filter = SongFilter(
            tags: Set(allTags),
            proficiencies: Set(proficiencies),
            anyTags: Set(anyTags),
            excludedTags: Set(noneTags),
            keys: Set(keys),
            artists: SongFilter.artistForms(artists),
            albums: SongFilter.albumForms(albums),
        )
        if let tempo, !tempo.isOpen {
            filter.tempo = SongFilter.Bounds(lower: tempo.min, upper: tempo.max)
        }
        if let length, !length.isOpen {
            filter.length = SongFilter.Bounds(lower: length.min, upper: length.max)
        }
        if neverPlayed {
            filter.playedSongs = Set(playStats.filter { $0.value.timesPlayed > 0 }.keys)
        }
        return filter
    }
}

/// A saved smart filter, as stored in `filters/<slug>.filter.json`.
public struct SmartFilter: Sendable, Equatable, Identifiable, Codable {
    /// Version written by this build. Version 1 is the first.
    public static let currentSchemaVersion = 1

    public var id: SmartFilterID
    public var schemaVersion: Int
    public var name: String
    public var conditions: SmartFilterConditions
    public var createdAt: Date
    public var updatedAt: Date
    /// Non-nil when the file is from a newer Segue: listed and usable with the conditions
    /// this build understands, never rewritten. Not stored.
    public var readOnly: ReadOnlyReason?

    public init(
        id: SmartFilterID,
        schemaVersion: Int = Self.currentSchemaVersion,
        name: String,
        conditions: SmartFilterConditions = SmartFilterConditions(),
        createdAt: Date = Date(timeIntervalSince1970: 0),
        updatedAt: Date = Date(timeIntervalSince1970: 0),
        readOnly: ReadOnlyReason? = nil,
    ) {
        self.id = id
        self.schemaVersion = schemaVersion
        self.name = name
        self.conditions = conditions
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.readOnly = readOnly
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case schemaVersion
        case name
        case conditions
        case createdAt
        case updatedAt
    }

    /// The songs of `songs` (order kept) this filter matches.
    public func songs(
        in songs: [SongRecord],
        playStats: [SongID: PlayStats] = [:],
    ) -> [SongRecord] {
        let matcher = conditions.compiled(playStats: playStats)
        return songs.filter(matcher.matches)
    }
}
