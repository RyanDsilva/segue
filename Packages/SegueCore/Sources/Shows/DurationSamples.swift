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
/// (`{"schemaVersion": 1, "runId": ..., "setlistId": ..., "samples": [...]}`), rewritten
/// atomically after each sample.
public actor RehearsalTimingStore: DurationSampleSink {
    public init(fileSystem: any FileSystem, root: LibraryRoot, runId: ULID, setlistName: String) {
        fatalError("unimplemented: unit A (RehearsalTimingStore.init)")
    }

    public func record(_ sample: DurationSample) async throws {
        fatalError("unimplemented: unit A (RehearsalTimingStore.record)")
    }

    /// Every rehearsal sample under `root` (phase 3 reads these with the show-derived ones).
    public static func loadAll(root: LibraryRoot, fileSystem: any FileSystem) throws
        -> [DurationSample]
    {
        fatalError("unimplemented: unit A (RehearsalTimingStore.loadAll)")
    }
}
