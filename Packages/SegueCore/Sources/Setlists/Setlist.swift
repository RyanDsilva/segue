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

/// A break between parts of a setlist ("Set 2"): the rows between two breaks form a part
/// with its own total (R85). Its optional length is an intermission, counted in the whole
/// setlist's total but in no part (R105).
public struct SetlistBreak: Sendable, Hashable, Codable {
    /// "Set 2"; numbered automatically when inserted, editable.
    public var label: String
    /// The intermission in seconds; nil (or zero) for none.
    public var length: TimeInterval?

    public init(label: String, length: TimeInterval? = nil) {
        self.label = label
        self.length = length
    }

    private enum CodingKeys: String, CodingKey {
        case label
        case length
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        label = try container.decodeIfPresent(String.self, forKey: .label) ?? ""
        length = try container.decodeIfPresent(TimeInterval.self, forKey: .length)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(label, forKey: .label)
        if let length, length > 0 {
            try container.encode(length, forKey: .length)
        }
    }
}

/// What a setlist slot holds: a song, or a break between parts.
public enum SetlistEntryKind: Sendable, Hashable {
    case song(SongID)
    case `break`(SetlistBreak)
}

/// One slot in a setlist: a song (with per-setlist overrides and a note) or a break row.
public struct SetlistEntry: Sendable, Equatable, Hashable, Codable, Identifiable {
    public var itemId: SetlistItemID
    public var kind: SetlistEntryKind
    /// Song slots only: a break has none (always empty).
    public var overrides: SetlistOverrides
    /// A short performance note for this slot ("start soft"), shown in live mode. Song slots
    /// only.
    public var note: String?

    public var id: SetlistItemID {
        itemId
    }

    /// The song's stable ID from its sidecar (renames never break the setlist); nil for a
    /// break.
    public var songId: SongID? {
        if case let .song(id) = kind {
            return id
        }
        return nil
    }

    /// The break this slot holds; nil for a song.
    public var breakInfo: SetlistBreak? {
        if case let .break(info) = kind {
            return info
        }
        return nil
    }

    /// Whether this slot is a break row.
    public var isBreak: Bool {
        breakInfo != nil
    }

    /// A song slot.
    public init(
        itemId: SetlistItemID,
        songId: SongID,
        overrides: SetlistOverrides = SetlistOverrides(),
        note: String? = nil,
    ) {
        self.itemId = itemId
        kind = .song(songId)
        self.overrides = overrides
        self.note = note
    }

    /// A break row.
    public init(itemId: SetlistItemID, break info: SetlistBreak) {
        self.itemId = itemId
        kind = .break(info)
        overrides = SetlistOverrides()
        note = nil
    }

    // A song slot: `{itemId, songId, overrides?, note?}` (unchanged since v2); a break row
    // (v3): `{itemId, break: {label, length?}}`.
    private enum CodingKeys: String, CodingKey {
        case itemId
        case songId
        case `break`
        case overrides
        case note
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        itemId = try container.decode(SetlistItemID.self, forKey: .itemId)
        if let info = try container.decodeIfPresent(SetlistBreak.self, forKey: .break) {
            kind = .break(info)
            overrides = SetlistOverrides()
            note = nil
            return
        }
        kind = try .song(container.decode(SongID.self, forKey: .songId))
        overrides = try container.decodeIfPresent(SetlistOverrides.self, forKey: .overrides)
            ?? SetlistOverrides()
        note = try container.decodeIfPresent(String.self, forKey: .note)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(itemId, forKey: .itemId)
        switch kind {
        case let .song(songId):
            try container.encode(songId, forKey: .songId)
            if !overrides.isEmpty {
                try container.encode(overrides, forKey: .overrides)
            }
            try container.encodeIfPresent(note, forKey: .note)
        case let .break(info):
            try container.encode(info, forKey: .break)
        }
    }
}

/// `setlists/<slug>.setlist.json`: an ordered list of song references plus gig details.
///
/// Versioning follows the sidecar rules: older versions migrate forward on read; a newer
/// one loads with `readOnly` set and is never rewritten.
/// History: 0 = pre-versioned; 1 = phase 0 (`entries: [{songId}]`); 2 = phase 2 (entries gain
/// `itemId`, `overrides`, `note`; the setlist gains timestamps, venue, date, target length);
/// 3 = phase 3 (break rows, `changeoverSeconds`). A v2 build opens a v3 file read-only.
public struct Setlist: Sendable, Equatable, Identifiable, Codable {
    /// The schema version this build reads and writes.
    public static let currentSchemaVersion = 3

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
    /// Seconds between songs (R86), added after every song but the last of each part; nil
    /// uses the app-wide default (Settings > General).
    public var changeoverSeconds: Int?
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
        case changeoverSeconds
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
        changeoverSeconds: Int? = nil,
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
        self.changeoverSeconds = changeoverSeconds
        self.readOnly = readOnly
    }

    /// The entry with `itemId`, if present.
    public func entry(_ itemId: SetlistItemID) -> SetlistEntry? {
        entries.first { $0.itemId == itemId }
    }

    /// Whether the setlist already holds `songID`. A song appears at most once in a
    /// setlist: every `SetlistStore` path that adds songs skips one already in it. Break
    /// rows hold no song and never count.
    public func contains(_ songID: SongID) -> Bool {
        entries.contains { $0.songId == songID }
    }

    /// The song slots, in order (break rows left out).
    public var songEntries: [SetlistEntry] {
        entries.filter { !$0.isBreak }
    }

    /// How many songs the setlist holds: every "N songs" count (the sidebar, the builder)
    /// reads this, never `entries.count`, since break rows are not songs.
    public var songCount: Int {
        entries.count { !$0.isBreak }
    }

    /// The automatic label of a break row at `position`: "Set N" for the part it opens
    /// (the first part has no break row above it).
    public func breakLabel(at position: Int) -> String {
        "Set \(entries.prefix(position).count(where: \.isBreak) + 2)"
    }

    /// Renumbers break rows whose label is still automatic ("Set 3" that now opens part 2
    /// becomes "Set 2"); labels the user typed stay. Run after inserting, moving or removing.
    public mutating func renumberBreaks() {
        var part = 1
        for index in entries.indices {
            guard var info = entries[index].breakInfo else { continue }
            part += 1
            if Self.isAutomaticBreakLabel(info.label), info.label != "Set \(part)" {
                info.label = "Set \(part)"
                entries[index].kind = .break(info)
            }
        }
    }

    /// "Set 2", "Set 10": a label Segue gave and may renumber.
    static func isAutomaticBreakLabel(_ label: String) -> Bool {
        guard label.hasPrefix("Set ") else { return false }
        let number = label.dropFirst(4)
        return !number.isEmpty && number.allSatisfy(\.isASCII) && number.allSatisfy(\.isNumber)
    }

    /// Entries whose song already appears earlier in the setlist. Only setlists saved before
    /// the one-song-once rule (or edited in another app) have any: they load as saved, and
    /// the builder marks these so they can be removed.
    public var repeatedEntries: Set<SetlistItemID> {
        var seen: Set<SongID> = []
        return Set(entries.filter { entry in
            entry.songId.map { !seen.insert($0).inserted } ?? false
        }.map(\.itemId))
    }
}
