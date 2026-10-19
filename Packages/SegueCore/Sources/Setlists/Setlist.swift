// Phase 2 frozen interface: docs/phases/2-interfaces.md. Owner: unit A (store), D (UI).

import Editing
import Foundation
import Library
import Support

/// Stable identity of a setlist (ULID).
public struct SetlistID: Sendable, Hashable, Comparable, Codable, CustomStringConvertible {
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

/// Stable identity of one slot in a setlist (and of the matching item in a show). A song
/// appears at most once in a setlist, but a show may play it again (a request), and setlists
/// saved before that rule may still repeat one. Requests and songs inserted during a show
/// get new item IDs.
public struct SetlistItemID: Sendable, Hashable, Comparable, Codable, CustomStringConvertible {
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

    /// The item ID a pre-v2 entry gets on migration: derived from the setlist ID and the
    /// entry's position, so migrating the same file twice yields the same IDs (a read-only
    /// copy and a migrated copy agree) without an ID generator.
    public static func migrated(setlist: SetlistID, position: Int) -> Self {
        var randomness = Array(setlist.ulid.bytes[6...])
        var carry = UInt16(truncatingIfNeeded: position + 1)
        for index in randomness.indices.reversed() where carry > 0 {
            let sum = UInt16(randomness[index]) + (carry & 0xFF)
            randomness[index] = UInt8(truncatingIfNeeded: sum)
            carry = (carry >> 8) + (sum >> 8)
        }
        return Self(ULID(milliseconds: setlist.ulid.milliseconds, randomness: randomness))
    }
}

/// Per-setlist key and capo for one item, without editing the song. Each field is optional:
/// nil inherits the song's own view (its sidecar `DisplayPrefs` and `{capo}`).
public struct SetlistOverrides: Sendable, Hashable, Codable {
    /// Concert transposition in semitones relative to the song as written. When set it
    /// replaces the song's saved view transpose for this setlist.
    public var transpose: Int?
    /// The capo fret to play with (0 = no capo). When set it replaces the song's `{capo}`;
    /// chords are re-spelled so the concert key stays `written key + capo + transpose`.
    public var capo: Int?

    public init(transpose: Int? = nil, capo: Int? = nil) {
        self.transpose = transpose
        self.capo = capo
    }

    /// True when nothing is overridden.
    public var isEmpty: Bool {
        transpose == nil && capo == nil
    }

    /// The render inputs for a song in this slot: the options to pass to `RenderModel` and
    /// the capo to render with (`RenderModel(document:options:userShapes:capo:)`).
    ///
    /// With song capo `c`, override capo `c2` and transpose `t`, the shapes shown are
    /// `written + t + c - c2`, so the concert key is `written + c + t` whatever capo is used.
    public func applied(to options: DisplayOptions, songCapo: Int?) -> (DisplayOptions, Int?) {
        let written = max(songCapo ?? 0, 0)
        let transpose = transpose ?? options.transpose
        guard let capo else { return (with(options, transpose: transpose), songCapo) }
        let fret = max(capo, 0)
        let shifted = with(options, transpose: transpose + written - fret)
        return (shifted, fret > 0 ? fret : nil)
    }

    private func with(_ options: DisplayOptions, transpose: Int) -> DisplayOptions {
        var options = options
        options.transpose = transpose
        return options
    }
}

/// One slot in a setlist.
public struct SetlistEntry: Sendable, Equatable, Hashable, Codable, Identifiable {
    public var itemId: SetlistItemID
    /// The song's stable ID from its sidecar (renames never break the setlist).
    public var songId: SongID
    public var overrides: SetlistOverrides
    /// A short performance note for this slot ("start soft"), shown in live mode.
    public var note: String?

    public var id: SetlistItemID {
        itemId
    }

    public init(
        itemId: SetlistItemID,
        songId: SongID,
        overrides: SetlistOverrides = SetlistOverrides(),
        note: String? = nil,
    ) {
        self.itemId = itemId
        self.songId = songId
        self.overrides = overrides
        self.note = note
    }

    private enum CodingKeys: String, CodingKey {
        case itemId
        case songId
        case overrides
        case note
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        itemId = try container.decode(SetlistItemID.self, forKey: .itemId)
        songId = try container.decode(SongID.self, forKey: .songId)
        overrides = try container.decodeIfPresent(SetlistOverrides.self, forKey: .overrides)
            ?? SetlistOverrides()
        note = try container.decodeIfPresent(String.self, forKey: .note)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(itemId, forKey: .itemId)
        try container.encode(songId, forKey: .songId)
        if !overrides.isEmpty {
            try container.encode(overrides, forKey: .overrides)
        }
        try container.encodeIfPresent(note, forKey: .note)
    }
}

/// `setlists/<slug>.setlist.json`: an ordered list of song references plus gig details.
///
/// Versioning follows the sidecar rules: older versions migrate forward on read; a newer
/// one loads with `readOnly` set and is never rewritten.
/// History: 0 = pre-versioned; 1 = phase 0 (`entries: [{songId}]`); 2 = phase 2 (entries gain
/// `itemId`, `overrides`, `note`; the setlist gains timestamps, venue, date, target length).
public struct Setlist: Sendable, Equatable, Identifiable, Codable {
    /// The schema version this build reads and writes.
    public static let currentSchemaVersion = 2

    public var id: SetlistID
    public var schemaVersion: Int
    public var name: String
    public var entries: [SetlistEntry]
    /// Nil for setlists written before phase 2 until their next save.
    public var createdAt: Date?
    public var updatedAt: Date?
    public var venue: String?
    public var date: CalendarDay?
    /// The planned set length in seconds (the builder's "target 45:00"); nil for none.
    public var targetDuration: TimeInterval?
    /// Runtime state, not persisted: non-nil when edits are blocked.
    public var readOnly: ReadOnlyReason?

    private enum CodingKeys: String, CodingKey {
        case id
        case schemaVersion
        case name
        case entries
        case createdAt
        case updatedAt
        case venue
        case date
        case targetDuration
    }

    public init(
        id: SetlistID,
        schemaVersion: Int = Self.currentSchemaVersion,
        name: String,
        entries: [SetlistEntry] = [],
        createdAt: Date? = nil,
        updatedAt: Date? = nil,
        venue: String? = nil,
        date: CalendarDay? = nil,
        targetDuration: TimeInterval? = nil,
        readOnly: ReadOnlyReason? = nil,
    ) {
        self.id = id
        self.schemaVersion = schemaVersion
        self.name = name
        self.entries = entries
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.venue = venue
        self.date = date
        self.targetDuration = targetDuration
        self.readOnly = readOnly
    }

    /// The entry with `itemId`, if present.
    public func entry(_ itemId: SetlistItemID) -> SetlistEntry? {
        entries.first { $0.itemId == itemId }
    }

    /// Whether the setlist already holds `songID`. A song appears at most once in a
    /// setlist: every `SetlistStore` path that adds songs skips one already in it.
    public func contains(_ songID: SongID) -> Bool {
        entries.contains { $0.songId == songID }
    }

    /// Entries whose song already appears earlier in the setlist. Only setlists saved before
    /// the one-song-once rule (or edited in another app) have any: they load as saved, and
    /// the builder marks these so they can be removed.
    public var repeatedEntries: Set<SetlistItemID> {
        var seen: Set<SongID> = []
        return Set(entries.filter { !seen.insert($0.songId).inserted }.map(\.itemId))
    }
}
