import Foundation
import Support

public extension Setlist {
    /// Identity, name and entries are strict (an unreadable entry fails the file, which is
    /// then reported and left untouched: dropping or moving a slot would change the set);
    /// every other field is lenient, an unreadable value kept raw for the next save.
    init(from decoder: any Decoder) throws {
        var object = try LenientObject<CodingKeys>(decoder)
        id = try object.required(.id)
        schemaVersion = object.value(.schemaVersion, default: Self.currentSchemaVersion)
        // Kept only while the file is newer than this build (R196): it is written back then.
        minReaderVersion = schemaVersion > Self.currentSchemaVersion
            ? object.value(.minReaderVersion) : nil
        name = try object.required(.name)
        entries = try object.container.decodeIfPresent([SetlistEntry].self, forKey: .entries) ?? []
        createdAt = object.value(.createdAt)
        updatedAt = object.value(.updatedAt)
        venue = object.value(.venue)
        date = object.value(.date)
        targetDuration = object.value(.targetDuration)
        changeoverSeconds = object.value(.changeoverSeconds)
        readOnly = nil
        unknown = object.unknown
    }

    func encode(to encoder: any Encoder) throws {
        try unknown.encode(to: encoder)
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(schemaVersion, forKey: .schemaVersion)
        try container.encode(
            SchemaMigrator.minReaderVersion(
                writing: schemaVersion,
                kept: minReaderVersion,
                current: Self.currentSchemaVersion,
                currentMinimum: Self.currentMinReaderVersion,
            ),
            forKey: .minReaderVersion,
        )
        try container.encode(name, forKey: .name)
        try container.encode(entries, forKey: .entries)
        try container.encodeIfPresent(createdAt, forKey: .createdAt)
        try container.encodeIfPresent(updatedAt, forKey: .updatedAt)
        try container.encodeIfPresent(venue, forKey: .venue)
        try container.encodeIfPresent(date, forKey: .date)
        try container.encodeIfPresent(targetDuration, forKey: .targetDuration)
        try container.encodeIfPresent(changeoverSeconds, forKey: .changeoverSeconds)
    }

    /// The version a save writes: the current one, or a newer file's own (R196: a newer
    /// file this build may edit is never downgraded).
    mutating func stampWrittenVersion() {
        schemaVersion = max(schemaVersion, Self.currentSchemaVersion)
    }
}
