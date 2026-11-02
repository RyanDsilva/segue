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
    /// A new entry would repeat a song the setlist already holds as a slot.
    case duplicateSong(SetlistID, SongID)
    /// A medley edit was refused (P9-3 5.6); nothing changed.
    case medley(SetlistID, MedleyRefusal)
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
/// A song is at most one plain slot, plus at most one medley member (the reprise, P9-3
/// decision 8, `Setlist.canAdd(_:as:)`). `addSong` and `insertSongs` skip songs already a
/// slot (writing nothing when none is left), `replaceEntries` refuses a new entry repeating
/// a slot's song, and `duplicate` keeps the first of any repeats. A setlist saved with
/// repeats loads as saved (not rewritten until edited), marked by `repeatedEntries`.
///
/// Versioning follows the sidecar rules: a file without `schemaVersion` (version 0) or at an
/// older version migrates forward in memory and is written at the current version on its
/// next save; a newer one loads read-only and is never rewritten; an undecodable one is
/// reported as a `SetlistLoadIssue` and left untouched.
public actor SetlistStore {
    let fileSystem: any FileSystem
    private let clock: any Clock
    let ids: any IDGenerator

    struct Stored {
        var setlist: Setlist
        var slug: String
    }

    var root: LibraryRoot?
    var setlists: [SetlistID: Stored] = [:]
    /// Each song's file name as the library last saw it (R191; `setSongFileNames`).
    var songFileNames: [SongID: String] = [:]

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
                let setlist = try Self.decode(data).fillingFileNames(songFileNames)
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

    /// Appends `songID` to setlist `setlistID` and saves it. A song already in the setlist
    /// stays where it is and nothing is written.
    @discardableResult
    public func addSong(_ songID: SongID, to setlistID: SetlistID) throws -> Setlist {
        try insertSongs([songID], into: setlistID)
    }

    /// Moves entries like `Array.move(fromOffsets:toOffset:)` (SwiftUI `onMove`) and saves.
    @discardableResult
    public func move(
        in setlistID: SetlistID,
        fromOffsets source: IndexSet,
        toOffset destination: Int,
    ) throws -> Setlist {
        try renumbered(setlistID) { entries in
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

    /// `move(in:fromOffsets:toOffset:)` and `remove(in:atOffsets:)` keep automatic break
    /// labels in part order.
    private func renumbered(_ id: SetlistID, _ change: (inout [SetlistEntry]) throws -> Void)
        throws -> Setlist
    {
        try mutateSetlist(id) { setlist in
            try change(&setlist.entries)
            setlist.renumberBreaks()
        }
    }

    /// Removes entries at `offsets` (SwiftUI `onDelete`) and saves.
    @discardableResult
    public func remove(in setlistID: SetlistID, atOffsets offsets: IndexSet) throws -> Setlist {
        try renumbered(setlistID) { entries in
            guard offsets.allSatisfy(entries.indices.contains) else {
                throw SetlistError.invalidOffsets(setlistID)
            }
            entries = entries.enumerated()
                .filter { !offsets.contains($0.offset) }
                .map(\.element)
        }
    }

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
            // A copy never repeats a song: repeats saved before the one-song-once rule
            // keep only their first slot.
            entries: original.entries
                .filter { !original.repeatedEntries.contains($0.itemId) }
                .map { entry in
                    var entry = entry
                    entry.itemId = SetlistItemID(ids.next())
                    return copiedMembers(of: entry, dropping: original.repeatedEntries)
                },
            createdAt: now,
            updatedAt: now,
            venue: original.venue,
            date: original.date,
            targetDuration: original.targetDuration,
            changeoverSeconds: original.changeoverSeconds,
        )
        let stored = Stored(setlist: copy, slug: newSlug(for: name, root: root))
        try save(stored, root: root)
        setlists[copy.id] = stored
        return copy
    }

    /// Inserts `songIDs` (new item IDs each) at `offset` (nil = append) and saves. Songs
    /// already a slot, and repeats within `songIDs`, are skipped (a medley member's song is
    /// added as its reprise); when none is left
    /// nothing is written and the setlist is returned as it is. Throws `invalidOffsets` when
    /// `offset` is outside `0 ... entries.count`.
    @discardableResult
    public func insertSongs(
        _ songIDs: [SongID],
        into id: SetlistID,
        at offset: Int? = nil,
    ) throws -> Setlist {
        try mutateSetlist(id, writesUnchanged: false) { setlist in
            let position = offset ?? setlist.entries.count
            guard (0 ... setlist.entries.count).contains(position) else {
                throw SetlistError.invalidOffsets(id)
            }
            var present = Set(setlist.entries.compactMap(\.songId))
            let inserted = songIDs
                .filter { present.insert($0).inserted }
                .map { song in SetlistEntry(itemId: SetlistItemID(ids.next()), songId: song) }
            setlist.entries.insert(contentsOf: inserted, at: position)
        }
    }

    /// Replaces venue, date, target length and changeover and saves. A blank venue is
    /// saved as none.
    @discardableResult
    public func updateDetails(_ details: SetlistDetails, of id: SetlistID) throws -> Setlist {
        try mutateSetlist(id) { setlist in
            let blankVenue = details.venue?.allSatisfy(\.isWhitespace) ?? true
            setlist.venue = blankVenue ? nil : details.venue
            setlist.date = details.date
            setlist.targetDuration = details.targetDuration
            setlist.changeoverSeconds = details.changeoverSeconds.map { max($0, 0) }
        }
    }

    /// Replaces all entries at once ("Save to setlist" in the show-end reorder sheet) and
    /// saves. Item IDs must be unique, else `invalidOffsets` is thrown; an entry that is not
    /// in the setlist now must not repeat a song of another entry, else `duplicateSong` is
    /// thrown. Either way nothing changes. (Repeats already saved in the setlist may stay.)
    @discardableResult
    public func replaceEntries(_ entries: [SetlistEntry], in id: SetlistID) throws -> Setlist {
        try mutate(id) { current in
            guard Set(entries.map(\.itemId)).count == entries.count else {
                throw SetlistError.invalidOffsets(id)
            }
            let existing = Set(current.map(\.itemId))
            var counts: [SongID: Int] = [:]
            for song in entries.compactMap(\.songId) {
                counts[song, default: 0] += 1
            }
            // Break rows hold no song: they never count as a repeat.
            for entry in entries where !existing.contains(entry.itemId) {
                if let song = entry.songId, counts[song, default: 0] > 1 {
                    throw SetlistError.duplicateSong(id, song)
                }
            }
            current = entries
        }
    }

    // MARK: - Private

    func mutate(
        _ id: SetlistID,
        _ change: (inout [SetlistEntry]) throws -> Void,
    ) throws -> Setlist {
        try mutateSetlist(id) { setlist in
            try change(&setlist.entries)
        }
    }

    /// Applies `change` to an editable setlist (file names filled, R191), stamps it and
    /// saves it atomically; nothing changes when `change` or the write throws. With
    /// `writesUnchanged` false, an unchanged setlist writes nothing (no stamp, no migration).
    func mutateSetlist(
        _ id: SetlistID,
        writesUnchanged: Bool = true,
        _ change: (inout Setlist) throws -> Void,
    ) throws -> Setlist {
        guard let root else { throw SetlistError.notLoaded }
        guard var stored = setlists[id] else { throw SetlistError.setlistNotFound(id) }
        if let reason = stored.setlist.readOnly {
            throw SetlistError.readOnly(id, reason)
        }
        let original = stored.setlist
        try change(&stored.setlist)
        if !writesUnchanged, stored.setlist == original {
            return original
        }
        stored.setlist = stored.setlist.fillingFileNames(songFileNames)
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

    static func decode(_ data: Data) throws -> Setlist {
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

    static func url(root: LibraryRoot, slug: String) -> URL {
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

/// The editable details of a setlist (the builder's Details popover).
public struct SetlistDetails: Sendable, Equatable {
    public var venue: String?
    public var date: CalendarDay?
    public var targetDuration: TimeInterval?
    /// Seconds between songs; nil uses the app-wide default (R86).
    public var changeoverSeconds: Int?

    public init(
        venue: String? = nil,
        date: CalendarDay? = nil,
        targetDuration: TimeInterval? = nil,
        changeoverSeconds: Int? = nil,
    ) {
        self.venue = venue
        self.date = date
        self.targetDuration = targetDuration
        self.changeoverSeconds = changeoverSeconds
    }

    /// The details `setlist` has now.
    public init(_ setlist: Setlist) {
        self.init(
            venue: setlist.venue,
            date: setlist.date,
            targetDuration: setlist.targetDuration,
            changeoverSeconds: setlist.changeoverSeconds,
        )
    }
}

private extension SetlistStore {
    /// Forward migrations, `steps[n]` takes version `n` to `n + 1`.
    static let migrator = SchemaMigrator(
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
            // v2 -> v3 (break rows, `changeoverSeconds`), v3 -> v4 (`locked`, R115) and
            // v4 -> v5 (`arrangement`, R122) add optional shapes: older files read unchanged.
            2: { _ in }, 3: { _ in }, 4: { _ in },
            // v5 -> v6: arrangement `steps` become `passes` (R149, `migrateV5`).
            5: { SlotArrangement.migrateV5(arrangementsIn: &$0, key: "entries") },
            // v6 -> v7: medley slots (P9-3), a new optional shape (old builds open v7 read-only).
            6: { _ in },
        ],
    )
}
