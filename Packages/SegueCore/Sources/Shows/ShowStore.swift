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

/// Shows stored as `shows/<ulid>.show.json`, written atomically (temp file + rename).
/// Rehearsal runs are stored too, so they get the same crash resume (decisions.md, phase 2
/// build rulings), but they never appear in the gig log or the play projection.
public actor ShowStore {
    /// An unfinished show untouched this long is closed into the gig log on launch.
    public static let staleInterval: TimeInterval = 12 * 60 * 60

    private let fileSystem: any FileSystem
    private let clock: any Clock
    private let playHistory: (any PlayHistoryIndex)?

    private var root: LibraryRoot?
    private var shows: [ShowID: ShowRecord] = [:]

    private static let migrator = SchemaMigrator(
        currentVersion: ShowRecord.currentSchemaVersion,
        steps: [:],
    )

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
        try fileSystem.createDirectory(at: root.showsDirectory)
        let suffix = LibraryRoot.showSuffix
        let urls = try fileSystem.contentsOfDirectory(at: root.showsDirectory)
            .filter { $0.lastPathComponent.hasSuffix(suffix) }
        var loaded: [ShowID: ShowRecord] = [:]
        var issues: [ShowLoadIssue] = []
        for url in urls {
            let relativePath = "shows/\(url.lastPathComponent)"
            do {
                let record = try Self.decode(fileSystem.readData(at: url))
                if loaded[record.id] != nil || url.lastPathComponent != Self.fileName(record.id) {
                    issues.append(ShowLoadIssue(
                        relativePath: relativePath,
                        message: "file name does not match show id \(record.id)",
                    ))
                    continue
                }
                loaded[record.id] = record
            } catch {
                issues.append(ShowLoadIssue(
                    relativePath: relativePath,
                    message: Self.describe(error),
                ))
            }
        }
        self.root = root
        shows = loaded
        try await playHistory?.replaceAllPlays(
            loaded.values.sorted { $0.id < $1.id }.filter(\.isFinished).flatMap(\.playRecords),
        )
        return issues
    }

    /// Writes `record` atomically. Writing a finished record also replaces its plays in the
    /// projection. Throws for read-only records.
    public func save(_ record: ShowRecord) async throws {
        guard let root else { throw ShowError.notLoaded }
        if let reason = record.readOnly {
            throw ShowError.readOnly(record.id, reason)
        }
        try fileSystem.writeAtomically(
            SegueJSON.encode(record),
            to: root.showsDirectory.appending(path: Self.fileName(record.id)),
        )
        shows[record.id] = record
        if record.isFinished {
            try await playHistory?.replacePlays(forShow: record.id.ulid, with: record.playRecords)
        }
    }

    /// The show with `id`.
    public func show(id: ShowID) -> ShowRecord? {
        shows[id]
    }

    /// The show with `id` re-read from its file (another run may have written it since it
    /// was loaded); nil when the file is gone or unreadable. Refreshes the cached copy.
    public func reloaded(_ id: ShowID) -> ShowRecord? {
        guard let root else { return nil }
        let url = root.showsDirectory.appending(path: Self.fileName(id))
        guard fileSystem.fileExists(at: url),
              let record = try? Self.decode(fileSystem.readData(at: url)),
              record.id == id
        else { return nil }
        shows[id] = record
        return record
    }

    // MARK: - Claims

    /// Claims show `id` for this run (see `ShowClaim`). Throws
    /// `ShowError.claimedElsewhere` when another window or process holds it.
    public func claim(_ id: ShowID) throws -> ShowClaim {
        guard let root else { throw ShowError.notLoaded }
        guard let claim = try ShowClaim.acquire(at: Self.claimURL(id, root: root)) else {
            throw ShowError.claimedElsewhere(id)
        }
        return claim
    }

    /// Whether another run holds show `id` right now.
    public func isClaimedElsewhere(_ id: ShowID) -> Bool {
        guard let root else { return false }
        guard let claim = try? ShowClaim.acquire(at: Self.claimURL(id, root: root)) else {
            return true
        }
        claim.release()
        return false
    }

    static func claimURL(_ id: ShowID, root: LibraryRoot) -> URL {
        root.showsDirectory.appending(path: id.description + claimSuffix)
    }

    /// The lock file next to `<ulid>.show.json`.
    static let claimSuffix = ".show.lock"

    // MARK: - Reorder reviews

    /// Finished gig shows whose reorder review is still unanswered, oldest first, with
    /// their diffs (the main window offers them until each is saved or discarded).
    public func pendingReviews() -> [ReorderDiff] {
        all().filter { $0.reorderReview == .pending && $0.readOnly == nil }
            .compactMap(ReorderDiff.compute)
    }

    /// Records the answer to show `id`'s reorder review, so it is not offered again.
    public func resolveReview(of id: ShowID, saved: Bool) async throws {
        guard var record = shows[id] else { throw ShowError.showNotFound(id) }
        guard record.reorderReview == .pending else { return }
        record.reorderReview = saved ? .saved : .discarded
        try await save(record)
    }

    /// Every stored show, oldest first.
    public func all() -> [ShowRecord] {
        shows.values.sorted { ($0.startedAt, $0.id) < ($1.startedAt, $1.id) }
    }

    /// The gig log: finished gig shows, newest first (rehearsals are never listed).
    public func gigLog() -> [GigLogEntry] {
        all().reversed().compactMap(GigLogEntry.init)
    }

    /// Edits a finished show's gig log fields and saves it. Ratings outside
    /// `GigDetails.ratingRange` are refused. Blank venue and notes are stored as nil.
    @discardableResult
    public func updateGigDetails(_ details: GigDetails, of id: ShowID) async throws -> ShowRecord {
        guard var record = shows[id] else { throw ShowError.showNotFound(id) }
        guard record.isFinished else { throw ShowError.notFinished(id) }
        if let rating = details.rating, !GigDetails.ratingRange.contains(rating) {
            throw ShowError.invalidRating(rating)
        }
        record.gig = GigDetails(
            venue: ShowRecord.trimmed(details.venue),
            date: details.date,
            notes: ShowRecord.trimmed(details.notes),
            rating: details.rating,
        )
        record.updatedAt = SegueJSON.stamp(clock.now())
        try await save(record)
        return record
    }

    /// Deletes a show's file and its plays from the projection.
    public func delete(_ id: ShowID) async throws {
        guard let root else { throw ShowError.notLoaded }
        guard let record = shows[id] else { throw ShowError.showNotFound(id) }
        if let reason = record.readOnly {
            throw ShowError.readOnly(id, reason)
        }
        let url = root.showsDirectory.appending(path: Self.fileName(id))
        if fileSystem.fileExists(at: url) {
            try fileSystem.removeItem(at: url)
        }
        shows[id] = nil
        try await playHistory?.replacePlays(forShow: id.ulid, with: [])
    }

    /// Run once after `load` at launch: auto-closes stale unfinished shows (written back,
    /// projected) and returns the resumable one, if any.
    ///
    /// Only the most recently updated fresh run (gig or rehearsal) is resumable; any other
    /// unfinished run (stale, or an older fresh one left behind) is closed with
    /// `closure = .stale` and `endedAt` = its last update. A closed rehearsal's ending has no
    /// diff and no gig log entry. Read-only shows are left untouched.
    ///
    /// A show updated in the future (the clock moved back, or another Mac with a skewed
    /// clock wrote it) is treated as stale: its age cannot be trusted. Shows claimed by
    /// another run (performing in another Segue right now) are neither offered nor closed.
    public func launchCheck() async throws -> LaunchShowCheck {
        let now = clock.now()
        let unfinished = all()
            .filter { !$0.isFinished && $0.readOnly == nil && !isClaimedElsewhere($0.id) }
            .sorted { ($0.updatedAt, $0.id) < ($1.updatedAt, $1.id) }
        let resumable = unfinished.last { record in
            let age = now.timeIntervalSince(record.updatedAt)
            return age >= 0 && age < Self.staleInterval
        }
        var closed: [ShowEnding] = []
        for var record in unfinished where record.id != resumable?.id {
            _ = record.finish(at: min(record.updatedAt, now), closure: .stale)
            try await save(record)
            closed.append(ShowEnding(
                record: record,
                diff: record.kind == .gig ? ReorderDiff.compute(record) : nil,
                gigLogEntry: GigLogEntry(record),
            ))
        }
        return LaunchShowCheck(resumable: resumable, autoClosed: closed)
    }

    // MARK: - Files

    static func fileName(_ id: ShowID) -> String {
        id.description + LibraryRoot.showSuffix
    }

    private static func decode(_ data: Data) throws -> ShowRecord {
        switch try migrator.migrate(data) {
        case let .current(json), let .migrated(json, _):
            return try SegueJSON.decode(ShowRecord.self, from: json)
        case let .newer(found):
            // Best effort: a newer file that still decodes is shown (gig log) but never
            // rewritten or resumed.
            var record = try SegueJSON.decode(ShowRecord.self, from: data)
            record.schemaVersion = found
            record.readOnly = .newerSchema(found: found, supported: ShowRecord.currentSchemaVersion)
            return record
        }
    }

    static func describe(_ error: any Error) -> String {
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
