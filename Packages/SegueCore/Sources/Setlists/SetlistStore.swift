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
            // v1 -> v2: every entry gains a stable `itemId` (derived from the setlist ID and
            // position, see `SetlistItemID.migrated`). The other v2 fields are optional.
            1: { object in
                guard let idString = object["id"] as? String,
                      let ulid = ULID(string: idString)
                else {
                    return // decoding reports the missing/invalid id
                }
                let setlist = SetlistID(ulid)
                let entries = object["entries"] as? [Any] ?? []
                object["entries"] = entries.enumerated().map { offset, raw -> Any in
                    guard var entry = raw as? [String: Any] else { return raw }
                    if entry["itemId"] == nil {
                        entry["itemId"] = SetlistItemID
                            .migrated(setlist: setlist, position: offset).description
                    }
                    return entry
                }
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
        let slug = newSlug(for: name, root: root)
        let now = SegueJSON.stamp(clock.now())
        let setlist = Setlist(
            id: SetlistID(ids.next()),
            name: name,
            createdAt: now,
            updatedAt: now,
        )
        let stored = Stored(setlist: setlist, slug: slug)
        try save(stored, root: root)
        setlists[setlist.id] = stored
        return setlist
    }

    /// Appends `songID` to setlist `setlistID` and saves it.
    @discardableResult
    public func addSong(_ songID: SongID, to setlistID: SetlistID) throws -> Setlist {
        try mutate(setlistID) { entries in
            entries.append(SetlistEntry(itemId: SetlistItemID(ids.next()), songId: songID))
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

    // MARK: - Phase 2 (unit A; frozen in docs/phases/2-interfaces.md)

    /// Renames setlist `id` (the file keeps its slug, like songs) and saves it.
    @discardableResult
    public func rename(_ id: SetlistID, to name: String) throws -> Setlist {
        try mutateSetlist(id) { setlist in
            setlist.name = name
        }
    }

    /// Saves a copy of setlist `id` as a new setlist named `name` (default "<name> copy"):
    /// a new setlist ID and new item IDs, same songs, overrides, notes and details. A
    /// read-only (newer-schema) setlist can be duplicated: the copy holds what this build
    /// can read and is editable.
    public func duplicate(_ id: SetlistID, name: String? = nil) throws -> Setlist {
        guard let root else { throw SetlistError.notLoaded }
        guard let original = setlists[id]?.setlist else { throw SetlistError.setlistNotFound(id) }
        let name = name ?? "\(original.name) copy"
        let now = SegueJSON.stamp(clock.now())
        let copy = Setlist(
            id: SetlistID(ids.next()),
            name: name,
            entries: original.entries.map { entry in
                var entry = entry
                entry.itemId = SetlistItemID(ids.next())
                return entry
            },
            createdAt: now,
            updatedAt: now,
            venue: original.venue,
            date: original.date,
            targetDuration: original.targetDuration,
        )
        let stored = Stored(setlist: copy, slug: newSlug(for: name, root: root))
        try save(stored, root: root)
        setlists[copy.id] = stored
        return copy
    }

    /// Deletes the setlist's file. Shows that ran it keep their own snapshot. A file already
    /// gone from disk is simply forgotten.
    public func delete(_ id: SetlistID) throws {
        guard let root else { throw SetlistError.notLoaded }
        guard let stored = setlists[id] else { throw SetlistError.setlistNotFound(id) }
        let url = Self.url(root: root, slug: stored.slug)
        if fileSystem.fileExists(at: url) {
            try fileSystem.removeItem(at: url)
        }
        setlists[id] = nil
    }

    /// Inserts `songIDs` (new item IDs each) at `offset` (nil = append) and saves. Throws
    /// `invalidOffsets` when `offset` is outside `0 ... entries.count`.
    @discardableResult
    public func insertSongs(
        _ songIDs: [SongID],
        into id: SetlistID,
        at offset: Int? = nil,
    ) throws -> Setlist {
        try mutate(id) { entries in
            let position = offset ?? entries.count
            guard (0 ... entries.count).contains(position) else {
                throw SetlistError.invalidOffsets(id)
            }
            let inserted = songIDs.map { song in
                SetlistEntry(itemId: SetlistItemID(ids.next()), songId: song)
            }
            entries.insert(contentsOf: inserted, at: position)
        }
    }

    /// Replaces the overrides and note of the entry with `entry.itemId` (its song stays) and
    /// saves. Throws `invalidOffsets` when no entry has that item ID.
    @discardableResult
    public func updateEntry(_ entry: SetlistEntry, in id: SetlistID) throws -> Setlist {
        try mutate(id) { entries in
            guard let index = entries.firstIndex(where: { $0.itemId == entry.itemId }) else {
                throw SetlistError.invalidOffsets(id)
            }
            entries[index].overrides = entry.overrides
            entries[index].note = entry.note
        }
    }

    /// Replaces venue, date and target length and saves. A blank venue is saved as none.
    @discardableResult
    public func updateDetails(_ details: SetlistDetails, of id: SetlistID) throws -> Setlist {
        try mutateSetlist(id) { setlist in
            let blankVenue = details.venue?.allSatisfy(\.isWhitespace) ?? true
            setlist.venue = blankVenue ? nil : details.venue
            setlist.date = details.date
            setlist.targetDuration = details.targetDuration
        }
    }

    /// Replaces all entries at once ("Save to setlist" in the show-end reorder sheet) and
    /// saves. Item IDs must be unique, else `invalidOffsets` is thrown and nothing changes.
    @discardableResult
    public func replaceEntries(_ entries: [SetlistEntry], in id: SetlistID) throws -> Setlist {
        try mutate(id) { current in
            guard Set(entries.map(\.itemId)).count == entries.count else {
                throw SetlistError.invalidOffsets(id)
            }
            current = entries
        }
    }

    // MARK: - Private

    private func mutate(
        _ id: SetlistID,
        _ change: (inout [SetlistEntry]) throws -> Void,
    ) throws -> Setlist {
        try mutateSetlist(id) { setlist in
            try change(&setlist.entries)
        }
    }

    /// Applies `change` to an editable setlist, stamps it and saves it atomically; nothing
    /// changes (in memory or on disk) when `change` or the write throws.
    private func mutateSetlist(
        _ id: SetlistID,
        _ change: (inout Setlist) throws -> Void,
    ) throws -> Setlist {
        guard let root else { throw SetlistError.notLoaded }
        guard var stored = setlists[id] else { throw SetlistError.setlistNotFound(id) }
        if let reason = stored.setlist.readOnly {
            throw SetlistError.readOnly(id, reason)
        }
        try change(&stored.setlist)
        stored.setlist.schemaVersion = Setlist.currentSchemaVersion
        stored.setlist.updatedAt = SegueJSON.stamp(clock.now())
        try save(stored, root: root)
        setlists[id] = stored
        return stored.setlist
    }

    /// A slug for a new setlist file: from `name`, de-duplicated against loaded setlists and
    /// files on disk (`-2`, `-3`, ...).
    private func newSlug(for name: String, root: LibraryRoot) -> String {
        let used = Set(setlists.values.map(\.slug))
        return Slug.unique(Slug.make(from: name)) { candidate in
            used.contains(candidate)
                || fileSystem.fileExists(at: Self.url(root: root, slug: candidate))
        }
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
        var songId: SongID?

        private enum CodingKeys: String, CodingKey {
            case songId
        }

        init(from decoder: any Decoder) throws {
            entry = try? SetlistEntry(from: decoder)
            songId = try? decoder.container(keyedBy: CodingKeys.self)
                .decodeIfPresent(SongID.self, forKey: .songId)
        }
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(SetlistID.self, forKey: .id)
        name = try? container.decodeIfPresent(String.self, forKey: .name)
        let lenient = (try? container.decodeIfPresent([LenientEntry].self, forKey: .entries))
            ?? []
        // An entry without a readable `itemId` still shows its song (derived ID).
        entries = lenient.enumerated().compactMap { [id] offset, raw in
            raw.entry ?? raw.songId.map { song in
                SetlistEntry(
                    itemId: SetlistItemID.migrated(setlist: id, position: offset),
                    songId: song,
                )
            }
        }
    }
}

/// The editable gig details of a setlist (builder header).
public struct SetlistDetails: Sendable, Equatable {
    public var venue: String?
    public var date: CalendarDay?
    public var targetDuration: TimeInterval?

    public init(
        venue: String? = nil,
        date: CalendarDay? = nil,
        targetDuration: TimeInterval? = nil,
    ) {
        self.venue = venue
        self.date = date
        self.targetDuration = targetDuration
    }
}

public extension SetlistStore {
    /// Why `replaceEntries(_:in:)` should not write setlist `id` now, checked against the
    /// file on disk: it was deleted (in Segue or from the folder) or became read-only (saved
    /// by a newer Segue) since it was loaded. Nil when it can be saved. The show-end review
    /// disables Save with this reason (2-interfaces.md, open question 17).
    func saveBlocker(for id: SetlistID) -> SetlistError? {
        guard let root else { return .notLoaded }
        guard let stored = setlists[id] else { return .setlistNotFound(id) }
        if let reason = stored.setlist.readOnly {
            return .readOnly(id, reason)
        }
        let url = Self.url(root: root, slug: stored.slug)
        guard fileSystem.fileExists(at: url) else { return .setlistNotFound(id) }
        if let data = try? fileSystem.readData(at: url),
           let onDisk = try? Self.decode(data)
        {
            if onDisk.id != id {
                return .setlistNotFound(id)
            }
            if let reason = onDisk.readOnly {
                return .readOnly(id, reason)
            }
        }
        return nil
    }
}
