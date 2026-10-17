// Phase 2 frozen interface (docs/phases/2-interfaces.md). Owner: unit A.

import Foundation
import Library
import Setlists
import Support

/// The play-history projection the show store feeds (`LibraryStore` conforms).
public protocol PlayHistoryIndex: Sendable {
    func replacePlays(forShow showID: ULID, with plays: [PlayRecord]) async throws
    func replaceAllPlays(_ plays: [PlayRecord]) async throws
}

extension LibraryStore: PlayHistoryIndex {}

/// A show file that could not be loaded. Reported, never deleted.
public struct ShowLoadIssue: Sendable, Equatable {
    /// Path relative to the library root.
    public var relativePath: String
    public var message: String

    public init(relativePath: String, message: String) {
        self.relativePath = relativePath
        self.message = message
    }
}

/// What to do about unfinished shows at launch.
public struct LaunchShowCheck: Sendable, Equatable {
    /// The most recent unfinished show updated less than 12 hours ago: offer "Resume show?"
    /// (default button resumes). Any older unfinished show is auto-closed instead.
    public var resumable: ShowRecord?
    /// Unfinished shows untouched for 12 hours or more, now closed into the gig log
    /// (`closure == .stale`, `endedAt` = their last update). Each ending with a diff is
    /// offered as a Save/Discard sheet, oldest first. No show data is discarded.
    public var autoClosed: [ShowEnding]

    public init(resumable: ShowRecord? = nil, autoClosed: [ShowEnding] = []) {
        self.resumable = resumable
        self.autoClosed = autoClosed
    }
}

/// Shows stored as `shows/<ulid>.show.json`, written atomically (temp file + rename). Only
/// gig shows are stored; rehearsals never reach this store.
public actor ShowStore {
    /// An unfinished show untouched this long is closed into the gig log on launch.
    public static let staleInterval: TimeInterval = 12 * 60 * 60

    private let fileSystem: any FileSystem
    private let clock: any Clock
    private let playHistory: (any PlayHistoryIndex)?

    public init(
        fileSystem: any FileSystem,
        clock: any Clock,
        playHistory: (any PlayHistoryIndex)?,
    ) {
        self.fileSystem = fileSystem
        self.clock = clock
        self.playHistory = playHistory
    }

    /// Loads every show under `root` (creating `shows/`), then rebuilds the play projection
    /// from the finished ones (`replaceAllPlays`). Unreadable files are reported.
    @discardableResult
    public func load(root: LibraryRoot) async throws -> [ShowLoadIssue] {
        fatalError("unimplemented: unit A (ShowStore.load)")
    }

    /// Writes `record` atomically. Writing a finished record also replaces its plays in the
    /// projection. Throws for read-only records.
    public func save(_ record: ShowRecord) async throws {
        fatalError("unimplemented: unit A (ShowStore.save)")
    }

    /// The show with `id`.
    public func show(id: ShowID) -> ShowRecord? {
        fatalError("unimplemented: unit A (ShowStore.show)")
    }

    /// The gig log: finished shows, newest first.
    public func gigLog() -> [GigLogEntry] {
        fatalError("unimplemented: unit A (ShowStore.gigLog)")
    }

    /// Edits a finished show's gig log fields and saves it. Ratings outside
    /// `GigDetails.ratingRange` are refused.
    @discardableResult
    public func updateGigDetails(_ details: GigDetails, of id: ShowID) async throws -> ShowRecord {
        fatalError("unimplemented: unit A (ShowStore.updateGigDetails)")
    }

    /// Deletes a show's file and its plays from the projection.
    public func delete(_ id: ShowID) async throws {
        fatalError("unimplemented: unit A (ShowStore.delete)")
    }

    /// Run once after `load` at launch: auto-closes stale unfinished shows (written back,
    /// projected) and returns the resumable one, if any.
    public func launchCheck() async throws -> LaunchShowCheck {
        fatalError("unimplemented: unit A (ShowStore.launchCheck)")
    }
}
