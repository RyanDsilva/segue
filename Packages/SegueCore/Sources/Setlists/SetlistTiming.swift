// Phase 2 frozen interface (docs/phases/2-interfaces.md). Owner: unit D.
//
// Start times and the running total for the setlist builder ("library to set" layout: each
// row shows its start time; the header shows total vs target).

import Foundation
import Library

/// Where a song's length came from.
public enum SongLengthSource: Sendable, Hashable {
    /// The song's `{duration}` directive.
    case directive
    /// Learned from timed shows and rehearsals (phase 3 fills this in).
    case learned
    /// Unknown: `SetlistTiming.fallbackLength` was used. Shown as an estimate ("~3:30").
    case fallback
}

/// A known song length.
public struct SongLength: Sendable, Hashable {
    public var seconds: TimeInterval
    public var source: SongLengthSource

    public init(seconds: TimeInterval, source: SongLengthSource) {
        self.seconds = seconds
        self.source = source
    }
}

/// One row's timing.
public struct ItemTiming: Sendable, Hashable {
    public var itemId: SetlistItemID
    /// Offset from the start of the set, in seconds.
    public var start: TimeInterval
    public var length: SongLength

    public init(itemId: SetlistItemID, start: TimeInterval, length: SongLength) {
        self.itemId = itemId
        self.start = start
        self.length = length
    }
}

/// Start times and totals for a setlist. Pure; recomputed on every change.
public struct SetlistTiming: Sendable, Hashable {
    /// The length assumed for a song with no known length (3:30).
    public static let fallbackLength: TimeInterval = 210

    /// One per entry, in setlist order.
    public var items: [ItemTiming]
    /// Sum of all lengths (estimates included).
    public var total: TimeInterval
    /// How many rows used `fallbackLength`.
    public var estimatedCount: Int
    /// The setlist's target length, if set.
    public var target: TimeInterval?

    /// Computes timings for `entries`.
    /// - Parameters:
    ///   - lengths: known lengths by song (directive now, learned in phase 3); songs absent
    ///     here use `fallback`.
    ///   - changeover: seconds between songs, added after every song but the last (0 in
    ///     phase 2).
    public init(
        entries: [SetlistEntry],
        lengths: [SongID: SongLength],
        target: TimeInterval?,
        fallback: TimeInterval = Self.fallbackLength,
        changeover: TimeInterval = 0,
    ) {
        fatalError("unimplemented: unit D (SetlistTiming.init)")
    }

    /// `total / target` (may exceed 1), or nil without a target.
    public var progress: Double? {
        guard let target, target > 0 else { return nil }
        return total / target
    }

    /// The length a song declares through `{duration}`, if any.
    public static func directiveLength(of song: SongRecord) -> SongLength? {
        song.document.metadata.duration.map { SongLength(seconds: $0, source: .directive) }
    }

    /// "3:40", "1:02:05" (hours only when needed).
    public static func format(_ seconds: TimeInterval) -> String {
        let whole = Int(seconds.rounded())
        let hours = whole / 3600
        let minutes = (whole % 3600) / 60
        let rest = whole % 60
        return hours > 0
            ? String(format: "%d:%02d:%02d", hours, minutes, rest)
            : String(format: "%d:%02d", minutes, rest)
    }
}
