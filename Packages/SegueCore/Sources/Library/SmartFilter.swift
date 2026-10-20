// Phase 3 (P3-6, R71, R72): saved smart filters. A smart filter is a named predicate over
// the library, stored as `filters/<slug>.filter.json` and compiled to the in-memory
// `SongFilter` matcher. No energy (R71); lengths are `{duration}` only (R91).

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

/// One end of a "last played" condition: a calendar day, or a number of days before now
/// (so "not played in the last 90 days" stays true to its name as time passes).
public enum PlayedBound: Sendable, Hashable, Codable {
    /// The start of this day in the current time zone.
    case day(CalendarDay)
    /// This many whole days (24 h each) before the moment the filter is evaluated.
    case daysAgo(Int)

    /// The instant this bound stands for when evaluated at `now`.
    public func instant(now: Date, timeZone: TimeZone) -> Date {
        switch self {
        case let .day(day):
            day.startOfDay(in: timeZone)
        case let .daysAgo(days):
            now.addingTimeInterval(-Double(max(0, days)) * 86400)
        }
    }

    private enum CodingKeys: String, CodingKey {
        case day
        case daysAgo
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let day = try container.decodeIfPresent(CalendarDay.self, forKey: .day) {
            self = .day(day)
        } else if let days = try container.decodeIfPresent(Int.self, forKey: .daysAgo) {
            self = .daysAgo(days)
        } else {
            throw DecodingError.dataCorrupted(DecodingError.Context(
                codingPath: decoder.codingPath,
                debugDescription: "a played bound needs \"day\" or \"daysAgo\"",
            ))
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .day(day):
            try container.encode(day, forKey: .day)
        case let .daysAgo(days):
            try container.encode(days, forKey: .daysAgo)
        }
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
    /// Last played strictly before this bound; a never-played song never matches.
    public var lastPlayedBefore: PlayedBound?
    /// Last played on or after this bound; a never-played song never matches.
    public var lastPlayedAfter: PlayedBound?
    /// Never played in a finished show.
    public var neverPlayed: Bool

    public init(
        allTags: [String] = [],
        anyTags: [String] = [],
        noneTags: [String] = [],
        proficiencies: [Proficiency] = [],
        keys: [String] = [],
        tempo: SmartFilterRange? = nil,
        length: SmartFilterRange? = nil,
        lastPlayedBefore: PlayedBound? = nil,
        lastPlayedAfter: PlayedBound? = nil,
        neverPlayed: Bool = false,
    ) {
        self.allTags = allTags
        self.anyTags = anyTags
        self.noneTags = noneTags
        self.proficiencies = proficiencies
        self.keys = keys
        self.tempo = tempo
        self.length = length
        self.lastPlayedBefore = lastPlayedBefore
        self.lastPlayedAfter = lastPlayedAfter
        self.neverPlayed = neverPlayed
    }

    private enum CodingKeys: String, CodingKey {
        case allTags
        case anyTags
        case noneTags
        case proficiencies
        case keys
        case tempo
        case length
        case lastPlayedBefore
        case lastPlayedAfter
        case neverPlayed
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
        lastPlayedBefore = try container
            .decodeIfPresent(PlayedBound.self, forKey: .lastPlayedBefore)
        lastPlayedAfter = try container
            .decodeIfPresent(PlayedBound.self, forKey: .lastPlayedAfter)
        neverPlayed = try container.decodeIfPresent(Bool.self, forKey: .neverPlayed) ?? false
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
            lastPlayedBefore != nil, lastPlayedAfter != nil, neverPlayed,
        ]
    }

    /// Whether any condition refers to play history (callers then pass play stats).
    public var usesPlayHistory: Bool {
        neverPlayed || lastPlayedBefore != nil || lastPlayedAfter != nil
    }

    /// The in-memory matcher for these conditions, evaluated at `now`: relative play bounds
    /// resolve against `now`, and `playStats` is the play-history snapshot to check.
    public func compiled(
        playStats: [SongID: PlayStats] = [:],
        now: Date,
        timeZone: TimeZone = .current,
    ) -> SongFilter {
        var filter = SongFilter(
            tags: Set(allTags),
            proficiencies: Set(proficiencies),
            anyTags: Set(anyTags),
            excludedTags: Set(noneTags),
            keys: Set(keys),
        )
        if let tempo, !tempo.isOpen {
            filter.tempo = SongFilter.Bounds(lower: tempo.min, upper: tempo.max)
        }
        if let length, !length.isOpen {
            filter.length = SongFilter.Bounds(lower: length.min, upper: length.max)
        }
        if usesPlayHistory {
            filter.played = SongFilter.PlayHistory(
                lastPlayed: playStats.compactMapValues(\.lastPlayed),
                before: lastPlayedBefore?.instant(now: now, timeZone: timeZone),
                onOrAfter: lastPlayedAfter?.instant(now: now, timeZone: timeZone),
                neverPlayed: neverPlayed,
            )
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

    /// The songs of `songs` (order kept) this filter matches at `now`.
    public func songs(
        in songs: [SongRecord],
        playStats: [SongID: PlayStats] = [:],
        now: Date,
        timeZone: TimeZone = .current,
    ) -> [SongRecord] {
        let matcher = conditions.compiled(playStats: playStats, now: now, timeZone: timeZone)
        return songs.filter(matcher.matches)
    }
}

extension CalendarDay {
    /// Midnight at the start of this day in `timeZone`.
    func startOfDay(in timeZone: TimeZone) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let components = DateComponents(year: year, month: month, day: day)
        return calendar.date(from: components) ?? Date(timeIntervalSince1970: 0)
    }
}
