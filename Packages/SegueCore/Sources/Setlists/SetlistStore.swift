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
public actor SetlistStore {
    private let fileSystem: any FileSystem
    private let clock: any Clock
    private let ids: any IDGenerator

    public init(fileSystem: any FileSystem, clock: any Clock, ids: any IDGenerator) {
        self.fileSystem = fileSystem
        self.clock = clock
        self.ids = ids
    }

    /// Loads all setlists under `root`. Unreadable files are skipped and reported.
    @discardableResult
    public func load(root: LibraryRoot) throws -> [SetlistLoadIssue] {
        _ = root
        fatalError("unimplemented")
    }

    /// All loaded setlists, sorted by name (case-insensitive), then ID.
    public func all() -> [Setlist] {
        fatalError("unimplemented")
    }

    /// Creates and saves an empty setlist named `name`.
    public func create(name: String) throws -> Setlist {
        _ = name
        fatalError("unimplemented")
    }

    /// Appends `songID` to setlist `setlistID` and saves it.
    @discardableResult
    public func addSong(_ songID: SongID, to setlistID: SetlistID) throws -> Setlist {
        _ = (songID, setlistID)
        fatalError("unimplemented")
    }

    /// Moves entries like `Array.move(fromOffsets:toOffset:)` (SwiftUI `onMove`) and saves.
    @discardableResult
    public func move(
        in setlistID: SetlistID,
        fromOffsets source: IndexSet,
        toOffset destination: Int,
    ) throws -> Setlist {
        _ = (setlistID, source, destination)
        fatalError("unimplemented")
    }

    /// Removes entries at `offsets` (SwiftUI `onDelete`) and saves.
    @discardableResult
    public func remove(in setlistID: SetlistID, atOffsets offsets: IndexSet) throws -> Setlist {
        _ = (setlistID, offsets)
        fatalError("unimplemented")
    }
}
