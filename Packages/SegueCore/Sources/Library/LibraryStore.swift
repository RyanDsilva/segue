import ChordPro
import Foundation
import Support

/// Errors surfaced by `LibraryStore`. Implementers may add cases.
public enum LibraryError: Error, Equatable {
    /// An operation ran before `open(root:)` succeeded.
    case notOpen
    /// No song with this ID is in the library.
    case songNotFound(SongID)
    /// The song is read-only and cannot be edited.
    case readOnly(SongID, ReadOnlyReason)
}

/// Outcome of a `refresh()` scan, for UI feedback and tests.
public struct RefreshSummary: Sendable, Equatable {
    public var added: Int
    public var updated: Int
    public var removed: Int

    public init(added: Int = 0, updated: Int = 0, removed: Int = 0) {
        self.added = added
        self.updated = updated
        self.removed = removed
    }
}

/// The song library: `.cho` files + sidecars on disk (canonical) and a rebuildable GRDB
/// index at `.segue/index.sqlite` (a projection; only this store writes to it).
///
/// All IO goes through the injected `FileSystem`; timestamps and IDs come from the injected
/// `Clock` and `IDGenerator`, so integration tests are reproducible.
/// Implementers may add methods (e.g. delete) as later phases need them.
public actor LibraryStore {
    private let fileSystem: any FileSystem
    private let clock: any Clock
    private let ids: any IDGenerator

    public init(fileSystem: any FileSystem, clock: any Clock, ids: any IDGenerator) {
        self.fileSystem = fileSystem
        self.clock = clock
        self.ids = ids
    }

    /// Opens (creating if needed) the library at `root`: ensures the folder layout, opens or
    /// rebuilds the index, then scans files like `refresh()`. Orphan `.cho` files get a
    /// sidecar.
    public func open(root: LibraryRoot) throws {
        _ = root
        fatalError("unimplemented")
    }

    /// Creates a new song from ChordPro `source`: writes `songs/<slug>.cho` and its sidecar
    /// (slug from the title, de-duplicated with `-2`, `-3`, ...) and indexes it.
    public func createSong(source: String) throws -> SongRecord {
        _ = source
        fatalError("unimplemented")
    }

    /// Replaces the `.cho` contents of song `id` and reindexes it. Throws
    /// `LibraryError.readOnly` for read-only songs. The ID and file name stay stable.
    public func updateSong(id: SongID, source: String) throws -> SongRecord {
        _ = (id, source)
        fatalError("unimplemented")
    }

    /// The song with `id`, or nil if absent.
    public func song(id: SongID) throws -> SongRecord? {
        _ = id
        fatalError("unimplemented")
    }

    /// Every song, sorted by title (case-insensitive), then ID.
    public func allSongs() throws -> [SongRecord] {
        fatalError("unimplemented")
    }

    /// Full-text search over title, artist and lyrics (FTS5), including romanized-Hindi
    /// spelling variants via the normalized index columns. Best matches first.
    public func search(query: String) throws -> [SongRecord] {
        _ = query
        fatalError("unimplemented")
    }

    /// Rescans the library folder: upserts changed files (mtime/hash), deletes missing ones.
    @discardableResult
    public func refresh() throws -> RefreshSummary {
        fatalError("unimplemented")
    }

    /// Deletes the index and re-creates it from the files on disk.
    public func rebuildIndex() throws {
        fatalError("unimplemented")
    }
}
