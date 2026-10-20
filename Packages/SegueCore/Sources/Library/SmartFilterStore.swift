// Phase 3 (P3-6, R72, R15): smart filters as library files. The set assistant (P3-7) and
// the set builder's Pick mode (P3-12) read filters through this store.

import Foundation
import Support

/// Errors surfaced by `SmartFilterStore`.
public enum SmartFilterError: Error, Equatable {
    /// An operation ran before `load(root:)` succeeded.
    case notLoaded
    /// No smart filter with this ID.
    case filterNotFound(SmartFilterID)
    /// The filter is from a newer Segue and cannot be edited.
    case readOnly(SmartFilterID, ReadOnlyReason)
}

/// A filter file that could not be loaded (e.g. corrupted JSON). Reported, never deleted.
public struct SmartFilterLoadIssue: Sendable, Equatable {
    /// Path relative to the library root.
    public var relativePath: String
    public var message: String

    public init(relativePath: String, message: String) {
        self.relativePath = relativePath
        self.message = message
    }
}

/// Smart filters stored as `filters/<slug>.filter.json` (R72). Every mutation is written to
/// disk atomically before it returns; the file keeps its slug when the filter is renamed
/// (like setlists). Deleting moves the file to the Trash (R15).
///
/// Versioning follows the sidecar and setlist rules: an older file migrates forward in memory
/// and is written at the current version on its next save; a newer one loads read-only (the
/// conditions this build understands still apply) and is never rewritten; an undecodable one
/// is reported as a `SmartFilterLoadIssue` and left untouched.
public actor SmartFilterStore {
    let fileSystem: any FileSystem
    private let clock: any Clock
    private let ids: any IDGenerator

    struct Stored {
        var filter: SmartFilter
        var slug: String
    }

    private var root: LibraryRoot?
    private var filters: [SmartFilterID: Stored] = [:]

    /// Forward migrations, `steps[n]` takes version `n` to `n + 1`.
    private static let migrator = SchemaMigrator(
        currentVersion: SmartFilter.currentSchemaVersion,
        steps: [
            // v0: a file without `schemaVersion` (hand-written); `conditions` may be missing.
            0: { object in
                object["conditions"] = object["conditions"] ?? [String: Any]()
            },
        ],
    )

    public init(fileSystem: any FileSystem, clock: any Clock, ids: any IDGenerator) {
        self.fileSystem = fileSystem
        self.clock = clock
        self.ids = ids
    }

    /// Loads every filter under `root` (creating `filters/` if needed). Unreadable files are
    /// skipped and reported.
    @discardableResult
    public func load(root: LibraryRoot) throws -> [SmartFilterLoadIssue] {
        try fileSystem.createDirectory(at: root.filtersDirectory)
        var loaded: [SmartFilterID: Stored] = [:]
        var issues: [SmartFilterLoadIssue] = []
        let suffix = LibraryRoot.filterSuffix
        let names = try fileSystem.contentsOfDirectory(at: root.filtersDirectory)
            .map(\.lastPathComponent)
            .filter { $0.hasSuffix(suffix) && $0.count > suffix.count }
            .sorted()
        for name in names {
            let slug = String(name.dropLast(suffix.count))
            let relativePath = Self.relativePath(slug: slug)
            do {
                let data = try fileSystem.readData(at: Self.url(root: root, slug: slug))
                let filter = try Self.decode(data)
                if let existing = loaded[filter.id] {
                    let other = Self.relativePath(slug: existing.slug)
                    issues.append(SmartFilterLoadIssue(
                        relativePath: relativePath,
                        message: "duplicate filter id \(filter.id) (also in \(other))",
                    ))
                    continue
                }
                loaded[filter.id] = Stored(filter: filter, slug: slug)
            } catch {
                issues.append(SmartFilterLoadIssue(
                    relativePath: relativePath,
                    message: Self.describe(error),
                ))
            }
        }
        self.root = root
        filters = loaded
        return issues
    }

    /// Loads every filter file again (picking up edits made in other apps); like `load`.
    @discardableResult
    public func reloadFromDisk() throws -> [SmartFilterLoadIssue] {
        guard let root else { throw SmartFilterError.notLoaded }
        return try load(root: root)
    }

    /// All loaded filters, sorted by name (case-insensitive), then ID.
    public func all() -> [SmartFilter] {
        filters.values.map(\.filter).sorted { lhs, rhs in
            switch lhs.name.localizedStandardCompare(rhs.name) {
            case .orderedAscending: true
            case .orderedDescending: false
            case .orderedSame: lhs.id < rhs.id
            }
        }
    }

    /// The filter with `id`, or nil if absent.
    public func filter(id: SmartFilterID) -> SmartFilter? {
        filters[id]?.filter
    }

    /// The file of filter `id`, or nil when it is not loaded. The file itself may be gone.
    public func fileURL(for id: SmartFilterID) -> URL? {
        guard let root, let stored = filters[id] else { return nil }
        return Self.url(root: root, slug: stored.slug)
    }

    /// Creates and saves a filter named `name` as `filters/<slug>.filter.json` (slug from the
    /// name, de-duplicated with `-2`, `-3`, ... against loaded filters and files on disk).
    @discardableResult
    public func create(
        name: String,
        conditions: SmartFilterConditions = SmartFilterConditions(),
    ) throws -> SmartFilter {
        guard let root else { throw SmartFilterError.notLoaded }
        let now = SegueJSON.stamp(clock.now())
        let filter = SmartFilter(
            id: SmartFilterID(ids.next()),
            name: name,
            conditions: conditions,
            createdAt: now,
            updatedAt: now,
        )
        let stored = Stored(filter: filter, slug: newSlug(for: name, root: root))
        try save(stored, root: root)
        filters[filter.id] = stored
        return filter
    }

    /// Renames filter `id` (the file keeps its slug) and saves it.
    @discardableResult
    public func rename(_ id: SmartFilterID, to name: String) throws -> SmartFilter {
        try mutate(id) { $0.name = name }
    }

    /// Replaces the conditions of filter `id` and saves it.
    @discardableResult
    public func update(
        _ id: SmartFilterID,
        conditions: SmartFilterConditions,
    ) throws -> SmartFilter {
        try mutate(id) { $0.conditions = conditions }
    }

    /// Writes `filter` back whole (an undo snapshot of name and conditions) into its file.
    @discardableResult
    public func replace(_ filter: SmartFilter) throws -> SmartFilter {
        try mutate(filter.id) { current in
            current.name = filter.name
            current.conditions = filter.conditions
        }
    }

    /// Moves the filter's file to the Trash (R15) and forgets the filter. A file already gone
    /// from disk is simply forgotten (empty receipt).
    @discardableResult
    public func delete(_ id: SmartFilterID) throws -> TrashReceipt {
        guard let root else { throw SmartFilterError.notLoaded }
        guard let stored = filters[id] else { throw SmartFilterError.filterNotFound(id) }
        let url = Self.url(root: root, slug: stored.slug)
        var receipt = TrashReceipt()
        if fileSystem.fileExists(at: url) {
            try receipt.items.append(TrashedItem(
                original: url,
                trashed: fileSystem.trashItem(at: url),
            ))
        }
        filters[id] = nil
        return receipt
    }

    /// Puts a filter deleted with `delete` back from `receipt` (Edit > Undo); under the next
    /// free slug when its file name was taken meanwhile. Nil when the file holds no loadable
    /// filter or one whose ID is already loaded. Throws `TrashRestoreError` when the file is
    /// no longer in the Trash.
    @discardableResult
    public func restore(_ receipt: TrashReceipt) throws -> SmartFilter? {
        guard let root else { throw SmartFilterError.notLoaded }
        let suffix = LibraryRoot.filterSuffix
        guard let item = receipt.items
            .first(where: { $0.original.lastPathComponent.hasSuffix(suffix) })
        else { return nil }
        let oldSlug = String(item.original.lastPathComponent.dropLast(suffix.count))
        let used = Set(filters.values.map(\.slug))
        let slug = Slug.unique(oldSlug) { candidate in
            used.contains(candidate)
                || fileSystem.fileExists(at: Self.url(root: root, slug: candidate))
        }
        let url = Self.url(root: root, slug: slug)
        try TrashReceipt(items: [item]).restore(using: fileSystem) { _ in url }
        guard let filter = try? Self.decode(fileSystem.readData(at: url)),
              filters[filter.id] == nil
        else { return nil }
        filters[filter.id] = Stored(filter: filter, slug: slug)
        return filter
    }

    /// The songs of `songs` (order kept) that filter `id` matches; nil when no such filter
    /// is loaded. Pass `playStats` (`LibraryStore.playStats()`) when the filter uses "never
    /// played".
    public func songs(
        matching id: SmartFilterID,
        in songs: [SongRecord],
        playStats: [SongID: PlayStats] = [:],
    ) -> [SongRecord]? {
        filters[id]?.filter.songs(in: songs, playStats: playStats)
    }

    /// Follows a library tag rename or merge (`LibraryStore.mergeTags`): every editable
    /// filter naming a tag of `sources` (case-insensitive) in its all / any / none lists
    /// names `target` instead, duplicates dropped. Returns the changed filters as they were
    /// before, for undo through `replace`.
    @discardableResult
    public func rewriteTags(_ sources: [String], to target: String) throws -> [SmartFilter] {
        let keys = Set(SongMetadata.normalizedTags(sources).map(SongMetadata.tagKey))
        guard let target = SongMetadata.normalizedTags([target]).first, !keys.isEmpty else {
            return []
        }
        let rewrite: ([String]) -> [String] = { tags in
            SongMetadata
                .normalizedTags(tags.map { keys.contains(SongMetadata.tagKey($0)) ? target : $0 })
        }
        var previous: [SmartFilter] = []
        for stored in filters.values.sorted(by: { $0.filter.id < $1.filter.id })
            where stored.filter.readOnly == nil
        {
            var conditions = stored.filter.conditions
            conditions.allTags = rewrite(conditions.allTags)
            conditions.anyTags = rewrite(conditions.anyTags)
            conditions.noneTags = rewrite(conditions.noneTags)
            guard conditions != stored.filter.conditions else { continue }
            previous.append(stored.filter)
            try update(stored.filter.id, conditions: conditions)
        }
        return previous
    }

    // MARK: - Private

    private func mutate(
        _ id: SmartFilterID,
        _ change: (inout SmartFilter) throws -> Void,
    ) throws -> SmartFilter {
        guard let root else { throw SmartFilterError.notLoaded }
        guard var stored = filters[id] else { throw SmartFilterError.filterNotFound(id) }
        if let reason = stored.filter.readOnly {
            throw SmartFilterError.readOnly(id, reason)
        }
        try change(&stored.filter)
        stored.filter.schemaVersion = SmartFilter.currentSchemaVersion
        stored.filter.updatedAt = SegueJSON.stamp(clock.now())
        try save(stored, root: root)
        filters[id] = stored
        return stored.filter
    }

    private func newSlug(for name: String, root: LibraryRoot) -> String {
        let used = Set(filters.values.map(\.slug))
        return Slug.unique(Slug.make(from: name)) { candidate in
            used.contains(candidate)
                || fileSystem.fileExists(at: Self.url(root: root, slug: candidate))
        }
    }

    private func save(_ stored: Stored, root: LibraryRoot) throws {
        try fileSystem.createDirectory(at: root.filtersDirectory)
        let data = try SegueJSON.encode(stored.filter)
        try fileSystem.writeAtomically(data, to: Self.url(root: root, slug: stored.slug))
    }

    static func decode(_ data: Data) throws -> SmartFilter {
        switch try migrator.migrate(data) {
        case let .current(json), let .migrated(json, _):
            return try SegueJSON.decode(SmartFilter.self, from: json)
        case let .newer(found):
            let partial = try SegueJSON.decode(PartialSmartFilter.self, from: data)
            return SmartFilter(
                id: partial.id,
                schemaVersion: found,
                name: partial.name ?? "",
                conditions: partial.conditions ?? SmartFilterConditions(),
                readOnly: .newerSchema(found: found, supported: SmartFilter.currentSchemaVersion),
            )
        }
    }

    static func url(root: LibraryRoot, slug: String) -> URL {
        root.filtersDirectory.appending(path: slug + LibraryRoot.filterSuffix)
    }

    private static func relativePath(slug: String) -> String {
        "filters/\(slug)\(LibraryRoot.filterSuffix)"
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

/// A filter written by a newer Segue: only `id` is required; the rest is best-effort.
private struct PartialSmartFilter: Decodable {
    var id: SmartFilterID
    var name: String?
    var conditions: SmartFilterConditions?

    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case conditions
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(SmartFilterID.self, forKey: .id)
        name = try? container.decodeIfPresent(String.self, forKey: .name)
        conditions = try? container.decodeIfPresent(SmartFilterConditions.self, forKey: .conditions)
    }
}
