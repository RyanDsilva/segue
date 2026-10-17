// Phase 2 frozen interface (docs/phases/2-interfaces.md). Owner: unit A.
//
// Learned-duration capture hooks for phase 3: every completed song yields a sample. Gig
// samples can always be re-derived from show files (`ShowRecord.playedSongs`); rehearsal
// samples exist only in `timings/<run ulid>.rehearsal.json`.

import Foundation
import Library
import Support

/// One timed performance of a song.
public struct DurationSample: Sendable, Hashable, Codable {
    public enum Source: String, Sendable, Hashable, Codable {
        case show
        case rehearsal
        /// Phase 3's per-song Start/Stop timer.
        case timer
    }

    public var songId: SongID
    public var seconds: TimeInterval
    public var source: Source
    /// The show ID or rehearsal run ID it came from.
    public var runId: ULID
    public var recordedAt: Date

    public init(
        songId: SongID,
        seconds: TimeInterval,
        source: Source,
        runId: ULID,
        recordedAt: Date,
    ) {
        self.songId = songId
        self.seconds = seconds
        self.source = source
        self.runId = runId
        self.recordedAt = recordedAt
    }
}

/// Receives samples as songs complete.
public protocol DurationSampleSink: Sendable {
    func record(_ sample: DurationSample) async throws
}

/// Rehearse-setlist timings: one file per run, `timings/<run ulid>.rehearsal.json`
/// (`{"schemaVersion": 1, "runId": ..., "setlistName": ..., "samples": [...]}`), rewritten
/// atomically after each sample.
///
/// Each sample is filed under its own `runId`, which `ShowController` sets to the rehearsal
/// run's show ID. A run's existing file is read before the first append, so a rehearsal
/// resumed after a crash (a new store, same run) keeps the samples taken before it.
public actor RehearsalTimingStore: DurationSampleSink {
    /// The schema version this build reads and writes.
    public static let currentSchemaVersion = 1

    private let fileSystem: any FileSystem
    private let root: LibraryRoot
    private let runId: ULID
    private let setlistName: String
    private var files: [ULID: RehearsalTimingFile] = [:]

    /// - Parameter runId: the run this store was opened for (`samples` lists its file).
    public init(fileSystem: any FileSystem, root: LibraryRoot, runId: ULID, setlistName: String) {
        self.fileSystem = fileSystem
        self.root = root
        self.runId = runId
        self.setlistName = setlistName
    }

    /// The samples recorded for `runId` so far (including ones already on disk).
    public var samples: [DurationSample] {
        get throws {
            try file(for: runId).samples
        }
    }

    public func record(_ sample: DurationSample) async throws {
        var next = try file(for: sample.runId)
        next.samples.append(sample)
        try fileSystem.createDirectory(at: root.timingsDirectory)
        try fileSystem.writeAtomically(
            SegueJSON.encode(next),
            to: Self.url(root: root, runId: sample.runId),
        )
        files[sample.runId] = next
    }

    /// The run's file: cached, else read from disk, else new. A file from a newer Segue or
    /// one that cannot be read is never overwritten.
    private func file(for run: ULID) throws -> RehearsalTimingFile {
        if let cached = files[run] {
            return cached
        }
        let url = Self.url(root: root, runId: run)
        guard fileSystem.fileExists(at: url) else {
            return RehearsalTimingFile(
                schemaVersion: Self.currentSchemaVersion,
                runId: run,
                setlistName: setlistName,
                samples: [],
            )
        }
        switch try Self.migrator.migrate(fileSystem.readData(at: url)) {
        case let .current(json), let .migrated(json, _):
            let file = try SegueJSON.decode(RehearsalTimingFile.self, from: json)
            files[run] = file
            return file
        case let .newer(found):
            throw RehearsalTimingError.newerSchema(found: found)
        }
    }

    /// Every rehearsal sample under `root` (phase 3 reads these with the show-derived ones).
    /// Unreadable files and files from a newer Segue are skipped; `loadReport` names them.
    public static func loadAll(root: LibraryRoot, fileSystem: any FileSystem) throws
        -> [DurationSample]
    {
        try loadReport(root: root, fileSystem: fileSystem).samples
    }

    /// Every readable rehearsal sample under `root` (oldest run first), plus the files that
    /// could not be read (reported, never deleted).
    public static func loadReport(
        root: LibraryRoot,
        fileSystem: any FileSystem,
    ) throws -> (samples: [DurationSample], issues: [ShowLoadIssue]) {
        guard fileSystem.directoryExists(at: root.timingsDirectory) else { return ([], []) }
        let suffix = LibraryRoot.rehearsalSuffix
        let urls = try fileSystem.contentsOfDirectory(at: root.timingsDirectory)
            .filter { $0.lastPathComponent.hasSuffix(suffix) }
        var samples: [DurationSample] = []
        var issues: [ShowLoadIssue] = []
        for url in urls {
            let relativePath = "timings/\(url.lastPathComponent)"
            do {
                let data = try fileSystem.readData(at: url)
                switch try migrator.migrate(data) {
                case let .current(json), let .migrated(json, _):
                    samples += try SegueJSON.decode(RehearsalTimingFile.self, from: json).samples
                case let .newer(found):
                    issues.append(ShowLoadIssue(
                        relativePath: relativePath,
                        message: "created by a newer Segue (schema \(found))",
                    ))
                }
            } catch {
                issues.append(ShowLoadIssue(
                    relativePath: relativePath,
                    message: ShowStore.describe(error),
                ))
            }
        }
        return (samples, issues)
    }

    private static let migrator = SchemaMigrator(
        currentVersion: currentSchemaVersion,
        steps: [:],
    )

    private static func url(root: LibraryRoot, runId: ULID) -> URL {
        root.timingsDirectory.appending(path: runId.description + LibraryRoot.rehearsalSuffix)
    }
}

/// Errors from `RehearsalTimingStore`.
public enum RehearsalTimingError: Error, Equatable {
    /// The run's file was written by a newer Segue; it is never rewritten.
    case newerSchema(found: Int)
}

/// The on-disk form of one rehearsal run.
private struct RehearsalTimingFile: Codable {
    var schemaVersion: Int
    var runId: ULID
    var setlistName: String
    var samples: [DurationSample]
}
