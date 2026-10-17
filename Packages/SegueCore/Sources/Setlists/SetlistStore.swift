import Foundation
import Library
import Support

/// Errors surfaced by `SetlistStore`. Implementers may add cases.
public enum SetlistError: Error, Equatable {
    /// An operation ran before `load(root:)` succeeded.
    case notLoaded
    /// No setlist with this ID.
    case setlistNotFound(SetlistID)
    /// The setlist is read-only and cannot be edited.
    case readOnly(SetlistID, ReadOnlyReason)
    /// A move/remove offset is outside the setlist's entries.
    case invalidOffsets(SetlistID)
}

/// A setlist file that could not be loaded (e.g. corrupted JSON). Reported, never deleted.
public struct SetlistLoadIssue: Sendable, Equatable {
    /// Path relative to the library root.
    public var relativePath: String
    public var message: String

    public init(relativePath: String, message: String) {
        self.relativePath = relativePath
        self.message = message
    }
}

/// Setlists stored as `setlists/<slug>.setlist.json`. Every mutation is written to disk
/// atomically before it returns. Implementers may add methods (rename, delete, ...).
///
/// Versioning follows the sidecar rules: a file without `schemaVersion` (version 0) or at an
/// older version migrates forward in memory and is written at the current version on its
/// next save; a newer one loads read-only and is never rewritten; an undecodable one is
/// reported as a `SetlistLoadIssue` and left untouched.
public actor SetlistStore {
    private let fileSystem: any FileSystem
    private let clock: any Clock
    private let ids: any IDGenerator

    private struct Stored {
        var setlist: Setlist
        var slug: String
    }

    private var root: LibraryRoot?
    private var setlists: [SetlistID: Stored] = [:]

    /// Forward migrations, `steps[n]` takes version `n` to `n + 1`.
    private static let migrator = SchemaMigrator(
        currentVersion: Setlist.currentSchemaVersion,
        steps: [
            // v0: pre-versioned file; `entries` may be missing.
            0: { object in
                object["entries"] = object["entries"] ?? [Any]()
            },
        ],
    )

    public init(fileSystem: any FileSystem, clock: any Clock, ids: any IDGenerator) {
        self.fileSystem = fileSystem
        self.clock = clock
        self.ids = ids
    }

    /// Loads all setlists under `root`. Unreadable files are skipped and reported.
    @discardableResult
    public func load(root: LibraryRoot) throws -> [SetlistLoadIssue] {
        try fileSystem.createDirectory(at: root.setlistsDirectory)
        var loaded: [SetlistID: Stored] = [:]
        var issues: [SetlistLoadIssue] = []
        let suffix = LibraryRoot.setlistSuffix
        let names = try fileSystem.contentsOfDirectory(at: root.setlistsDirectory)
            .map(\.lastPathComponent)
            .filter { $0.hasSuffix(suffix) && $0.count > suffix.count }
        for name in names {
            let slug = String(name.dropLast(suffix.count))
            let relativePath = Self.relativePath(slug: slug)
            do {
                let data = try fileSystem.readData(at: Self.url(root: root, slug: slug))
                let setlist = try Self.decode(data)
                if let existing = loaded[setlist.id] {
                    let other = Self.relativePath(slug: existing.slug)
                    issues.append(SetlistLoadIssue(
                        relativePath: relativePath,
                        message: "duplicate setlist id \(setlist.id) (also in \(other))",
                    ))
                    continue
                }
                loaded[setlist.id] = Stored(setlist: setlist, slug: slug)
            } catch {
                issues.append(SetlistLoadIssue(
                    relativePath: relativePath,
                    message: Self.describe(error),
                ))
            }
        }
        self.root = root
        setlists = loaded
        return issues
    }

    /// All loaded setlists, sorted by name (case-insensitive), then ID.
    public func all() -> [Setlist] {
        setlists.values.map(\.setlist).sorted { lhs, rhs in
            switch lhs.name.caseInsensitiveCompare(rhs.name) {
            case .orderedAscending: true
            case .orderedDescending: false
            case .orderedSame: lhs.id < rhs.id
            }
        }
    }

    /// The setlist with `id`, or nil if absent.
    public func setlist(id: SetlistID) -> Setlist? {
        setlists[id]?.setlist
    }

    /// Creates and saves an empty setlist named `name`.
    public func create(name: String) throws -> Setlist {
        guard let root else { throw SetlistError.notLoaded }
        let used = Set(setlists.values.map(\.slug))
        let slug = Slug.unique(Slug.make(from: name)) { candidate in
            used.contains(candidate) || fileSystem.fileExists(at: Self.url(
                root: root,
                slug: candidate,
            ))
        }
        let setlist = Setlist(id: SetlistID(ids.next()), name: name)
        let stored = Stored(setlist: setlist, slug: slug)
        try save(stored, root: root)
        setlists[setlist.id] = stored
        return setlist
    }

    /// Appends `songID` to setlist `setlistID` and saves it.
    @discardableResult
    public func addSong(_ songID: SongID, to setlistID: SetlistID) throws -> Setlist {
        try mutate(setlistID) { entries in
            entries.append(SetlistEntry(songId: songID))
        }
    }

    /// Moves entries like `Array.move(fromOffsets:toOffset:)` (SwiftUI `onMove`) and saves.
    @discardableResult
    public func move(
        in setlistID: SetlistID,
        fromOffsets source: IndexSet,
        toOffset destination: Int,
    ) throws -> Setlist {
        try mutate(setlistID) { entries in
            guard source.allSatisfy(entries.indices.contains),
                  (0 ... entries.count).contains(destination)
            else {
                throw SetlistError.invalidOffsets(setlistID)
            }
            let moving = source.map { entries[$0] }
            let insertion = destination - source.count(in: 0 ..< destination)
            var remaining = entries.enumerated()
                .filter { !source.contains($0.offset) }
                .map(\.element)
            remaining.insert(contentsOf: moving, at: insertion)
            entries = remaining
        }
    }

    /// Removes entries at `offsets` (SwiftUI `onDelete`) and saves.
    @discardableResult
    public func remove(in setlistID: SetlistID, atOffsets offsets: IndexSet) throws -> Setlist {
        try mutate(setlistID) { entries in
            guard offsets.allSatisfy(entries.indices.contains) else {
                throw SetlistError.invalidOffsets(setlistID)
            }
            entries = entries.enumerated()
                .filter { !offsets.contains($0.offset) }
                .map(\.element)
        }
    }

    // MARK: - Private

    private func mutate(
        _ id: SetlistID,
        _ change: (inout [SetlistEntry]) throws -> Void,
    ) throws -> Setlist {
        guard let root else { throw SetlistError.notLoaded }
        guard var stored = setlists[id] else { throw SetlistError.setlistNotFound(id) }
        if let reason = stored.setlist.readOnly {
            throw SetlistError.readOnly(id, reason)
        }
        try change(&stored.setlist.entries)
        stored.setlist.schemaVersion = Setlist.currentSchemaVersion
        try save(stored, root: root)
        setlists[id] = stored
        return stored.setlist
    }

    private func save(_ stored: Stored, root: LibraryRoot) throws {
        let data = try SegueJSON.encode(stored.setlist)
        try fileSystem.writeAtomically(data, to: Self.url(root: root, slug: stored.slug))
    }

    private static func decode(_ data: Data) throws -> Setlist {
        switch try migrator.migrate(data) {
        case let .current(json), let .migrated(json, _):
            return try SegueJSON.decode(Setlist.self, from: json)
        case let .newer(found):
            let partial = try SegueJSON.decode(PartialSetlist.self, from: data)
            return Setlist(
                id: partial.id,
                schemaVersion: found,
                name: partial.name ?? "",
                entries: partial.entries,
                readOnly: .newerSchema(found: found, supported: Setlist.currentSchemaVersion),
            )
        }
    }

    private static func url(root: LibraryRoot, slug: String) -> URL {
        root.setlistsDirectory.appending(path: slug + LibraryRoot.setlistSuffix)
    }

    private static func relativePath(slug: String) -> String {
        "setlists/\(slug)\(LibraryRoot.setlistSuffix)"
    }

    private static func describe(_ error: any Error) -> String {
        switch error {
        case let error as SchemaMigrationError:
            error.description
        case let DecodingError.dataCorrupted(context),
             let DecodingError.keyNotFound(_, context),
             let DecodingError.typeMismatch(_, context),
             let DecodingError.valueNotFound(_, context):
            context.debugDescription
        default:
            "invalid JSON: \(error.localizedDescription)"
        }
    }
}

/// A setlist written by a newer Segue: only `id` is required; other fields are best-effort
/// so unknown shapes do not hide the songs it lists.
private struct PartialSetlist: Decodable {
    var id: SetlistID
    var name: String?
    var entries: [SetlistEntry]

    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case entries
    }

    private struct LenientEntry: Decodable {
        var entry: SetlistEntry?

        init(from decoder: any Decoder) throws {
            entry = try? SetlistEntry(from: decoder)
        }
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(SetlistID.self, forKey: .id)
        name = try? container.decodeIfPresent(String.self, forKey: .name)
        entries = (try? container.decodeIfPresent([LenientEntry].self, forKey: .entries))?
            .compactMap(\.entry) ?? []
    }
}
