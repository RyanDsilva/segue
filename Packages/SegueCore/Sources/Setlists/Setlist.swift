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

/// One slot in a setlist. Phase 2 adds per-entry fields (notes, played state, ...).
public struct SetlistEntry: Sendable, Equatable, Hashable, Codable {
    public var songId: SongID

    public init(songId: SongID) {
        self.songId = songId
    }
}

/// `setlists/<slug>.setlist.json`: an ordered list of song references.
///
/// Versioning follows the sidecar rules: older versions migrate forward on read; a newer
/// one loads with `readOnly` set and is never rewritten.
public struct Setlist: Sendable, Equatable, Identifiable, Codable {
    /// The schema version this build reads and writes.
    public static let currentSchemaVersion = 1

    public var id: SetlistID
    public var schemaVersion: Int
    public var name: String
    public var entries: [SetlistEntry]
    /// Runtime state, not persisted: non-nil when edits are blocked.
    public var readOnly: ReadOnlyReason?

    private enum CodingKeys: String, CodingKey {
        case id
        case schemaVersion
        case name
        case entries
    }

    public init(
        id: SetlistID,
        schemaVersion: Int = Self.currentSchemaVersion,
        name: String,
        entries: [SetlistEntry] = [],
        readOnly: ReadOnlyReason? = nil,
    ) {
        self.id = id
        self.schemaVersion = schemaVersion
        self.name = name
        self.entries = entries
        self.readOnly = readOnly
    }
}
