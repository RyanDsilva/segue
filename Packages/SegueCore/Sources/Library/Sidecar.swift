import Foundation

/// `songs/<slug>.segue.json`: the only home of app metadata. The `.cho` stays clean ChordPro.
///
/// Versioning: older `schemaVersion`s are migrated forward on read and written back at
/// `currentSchemaVersion` on next save; a newer one opens the song read-only
/// (`ReadOnlyReason.newerSchema`) and the file is never rewritten.
/// Implementers may add fields; bump `currentSchemaVersion` and add a migration when the
/// on-disk shape changes.
public struct Sidecar: Sendable, Equatable, Codable {
    /// The schema version this build reads and writes.
    public static let currentSchemaVersion = 1

    public var schemaVersion: Int
    public var id: SongID
    public var tags: [String]
    public var proficiency: Proficiency?
    public var notes: String?
    public var displayPrefs: DisplayPrefs
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        schemaVersion: Int = Self.currentSchemaVersion,
        id: SongID,
        tags: [String] = [],
        proficiency: Proficiency? = nil,
        notes: String? = nil,
        displayPrefs: DisplayPrefs = DisplayPrefs(),
        createdAt: Date,
        updatedAt: Date,
    ) {
        self.schemaVersion = schemaVersion
        self.id = id
        self.tags = tags
        self.proficiency = proficiency
        self.notes = notes
        self.displayPrefs = displayPrefs
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

/// How well the user knows a song (decisions.md: Learning / Ready / Pro).
public enum Proficiency: String, Sendable, Equatable, Codable, CaseIterable {
    case learning
    case ready
    case pro
}

/// Per-song display preferences (font size, zoom, ...). Empty in phase 0; phase 2 adds
/// fields.
public struct DisplayPrefs: Sendable, Equatable, Codable {
    public init() {}
}
