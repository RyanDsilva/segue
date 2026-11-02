import Foundation

/// A library folder's identity (P9-6 5.1): `<root>/.segue/library.json`,
/// `{"schema": 1, "minReaderVersion": 1, "id": "<ULID>", "createdAt": "<ISO8601>"}`.
///
/// A file from a newer Segue that this build may not read (its `schema` is newer and its
/// `minReaderVersion`, absent meaning the schema itself, is too) refuses to open the library
/// and is never replaced: the ID is never re-minted for it (R196).
///
/// The ID is minted once, from the injected `IDGenerator`, on the first open of a folder
/// that lacks the file, and never derived from the path: moving or renaming the folder keeps
/// it, and an archive restored into a new folder (the archive leaves `.segue/` out) gets a
/// fresh one. It keys the folder's state outside the library (`LibraryStateDirectory`) and,
/// later, its iCloud zone.
public struct LibraryIdentity: Sendable, Hashable, Codable {
    /// The file's current schema.
    public static let currentSchema = 1

    public let schema: Int
    /// The oldest `schema` whose readers may use this file (R196); written equal to `schema`.
    public let minReaderVersion: Int?
    public let id: ULID
    public let createdAt: Date

    public init(id: ULID, createdAt: Date, schema: Int = Self.currentSchema) {
        self.schema = schema
        minReaderVersion = schema
        self.id = id
        self.createdAt = createdAt
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(ULID.self, forKey: .id)
        schema = try container.decodeIfPresent(Int.self, forKey: .schema) ?? Self.currentSchema
        minReaderVersion = try? container.decodeIfPresent(Int.self, forKey: .minReaderVersion)
        createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt)
            ?? id.timestamp
    }

    /// `<root>/.segue/library.json`.
    public static func fileURL(_ root: LibraryRoot) -> URL {
        root.appDirectory.appending(path: "library.json", directoryHint: .notDirectory)
    }

    /// What `<root>/.segue/library.json` holds.
    public enum Stored: Sendable, Equatable {
        /// No file.
        case missing
        /// A file that is not a readable identity (bad JSON, no ID).
        case unreadable
        /// Written by a newer Segue this build may not read (R196): never replaced.
        case newer(found: Int)
        case valid(LibraryIdentity)
    }

    /// Reads the identity file. A newer schema still reads when it carries an ID, so a
    /// newer build's file is never replaced.
    public static func read(root: LibraryRoot, fileSystem: any FileSystem) -> Stored {
        let url = fileURL(root)
        guard fileSystem.fileExists(at: url) else { return .missing }
        guard let data = try? fileSystem.readData(at: url) else { return .unreadable }
        if let found = newerSchema(in: data) {
            return .newer(found: found)
        }
        guard let identity = try? SegueJSON.decode(Self.self, from: data)
        else { return .unreadable }
        return .valid(identity)
    }

    /// The `schema` of a file this build may not read, if it is one.
    private static func newerSchema(in data: Data) -> Int? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let found = (object["schema"] as? NSNumber)?.intValue,
              found > currentSchema
        else { return nil }
        let minimum = (object[SchemaMigrator.minReaderKey] as? NSNumber)?.intValue ?? found
        return minimum > currentSchema ? found : nil
    }

    /// The folder's identity, minting and writing one when the file is missing or
    /// unreadable (an unreadable file goes to the Trash first, never deleted).
    public static func resolve(
        root: LibraryRoot,
        fileSystem: any FileSystem,
        clock: any Clock,
        ids: any IDGenerator,
    ) throws -> Self {
        switch read(root: root, fileSystem: fileSystem) {
        case let .valid(identity):
            return identity
        case let .newer(found):
            throw LibraryIdentityError.newerSchema(found: found, supported: currentSchema)
        case .unreadable:
            _ = try fileSystem.trashItem(at: fileURL(root))
            return try mint(root: root, fileSystem: fileSystem, clock: clock, ids: ids)
        case .missing:
            return try mint(root: root, fileSystem: fileSystem, clock: clock, ids: ids)
        }
    }

    /// Gives the folder a new identity: the old file goes to the Trash, a new one is written
    /// (a Finder copy of another library, 5.2).
    public static func rekey(
        root: LibraryRoot,
        fileSystem: any FileSystem,
        clock: any Clock,
        ids: any IDGenerator,
    ) throws -> Self {
        if fileSystem.fileExists(at: fileURL(root)) {
            _ = try fileSystem.trashItem(at: fileURL(root))
        }
        return try mint(root: root, fileSystem: fileSystem, clock: clock, ids: ids)
    }

    private static func mint(
        root: LibraryRoot,
        fileSystem: any FileSystem,
        clock: any Clock,
        ids: any IDGenerator,
    ) throws -> Self {
        let identity = Self(id: ids.next(), createdAt: SegueJSON.stamp(clock.now()))
        try fileSystem.createDirectory(at: root.appDirectory)
        try fileSystem.writeAtomically(SegueJSON.encode(identity), to: fileURL(root))
        return identity
    }
}

/// Why a library's identity cannot be used.
public enum LibraryIdentityError: Error, Equatable, LocalizedError {
    /// `.segue/library.json` was written by a newer Segue this build may not read (R196).
    case newerSchema(found: Int, supported: Int)

    public var errorDescription: String? {
        switch self {
        case .newerSchema:
            "This library was set up by a newer version of Segue. Update Segue to open it."
        }
    }
}
