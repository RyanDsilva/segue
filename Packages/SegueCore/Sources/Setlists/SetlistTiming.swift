// Phase 2 frozen interface (docs/phases/2-interfaces.md). Owner: unit D.
//
// Start times and the running total for the setlist builder ("library to set" layout: each
// row shows its start time; the header shows total vs target).
//
// Ruling (decisions.md, phase 2 build rulings): an unknown song length is never made up. The
// row shows `--:--` and adds nothing to the total. Everything after it is a lower bound,
// written with "≥" (start "≥13:50", total "≥38:20 + 2 unknown"); a lower bound of zero says
// nothing, so it reads `--:--` (a start) or "2 unknown" (the total).

import Foundation
import Library

/// Where a song's length came from.
public enum SongLengthSource: Sendable, Hashable {
    /// The song's `{duration}` directive.
    case directive
    /// Learned from timed shows and rehearsals (phase 3 fills this in).
    case learned
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
    /// Offset from the start of the set, in seconds, counting known lengths only.
    public var start: TimeInterval
    /// True when an earlier row has an unknown length, so `start` is a lower bound
    /// (shown as "≥12:40", see `startText`).
    public var startIsApproximate: Bool
    /// Nil when the song's length is unknown (shown as `--:--`).
    public var length: SongLength?

    public init(
        itemId: SetlistItemID,
        start: TimeInterval,
        startIsApproximate: Bool = false,
        length: SongLength?,
    ) {
        self.itemId = itemId
        self.start = start
        self.startIsApproximate = startIsApproximate
        self.length = length
    }

    /// The start as the builder shows it: "12:40"; "≥12:40" after an unknown length; `--:--`
    /// when every earlier length is unknown (a lower bound of 0:00 says nothing).
    public var startText: String {
        guard startIsApproximate else { return SetlistTiming.format(start) }
        guard start > 0 else { return SetlistTiming.unknownText }
        return SetlistTiming.lowerBoundPrefix + SetlistTiming.format(start)
    }
}

/// Start times and totals for a setlist. Pure; recomputed on every change.
public struct SetlistTiming: Sendable, Hashable {
    /// One per entry, in setlist order.
    public var items: [ItemTiming]
    /// Sum of the known lengths (plus changeovers).
    public var total: TimeInterval
    /// How many rows have an unknown length (not counted in `total`).
    public var unknownCount: Int
    /// The setlist's target length, if set.
    public var target: TimeInterval?

    /// Computes timings for `entries`.
    /// - Parameters:
    ///   - lengths: known lengths by song (directive now, learned in phase 3); songs absent
    ///     here (or with a length of zero or less) are unknown.
    ///   - changeover: seconds between songs, added after every song but the last (0 in
    ///     phase 2).
    public init(
        entries: [SetlistEntry],
        lengths: [SongID: SongLength],
        target: TimeInterval?,
        changeover: TimeInterval = 0,
    ) {
        var start: TimeInterval = 0
        var items: [ItemTiming] = []
        items.reserveCapacity(entries.count)
        var unknown = 0
        for (offset, entry) in entries.enumerated() {
            let length = lengths[entry.songId].flatMap { $0.seconds > 0 ? $0 : nil }
            items.append(ItemTiming(
                itemId: entry.itemId,
                start: start,
                startIsApproximate: unknown > 0,
                length: length,
            ))
            if let length {
                start += length.seconds
            } else {
                unknown += 1
            }
            if offset < entries.count - 1 {
                start += changeover
            }
        }
        self.items = items
        total = start
        unknownCount = unknown
        self.target = target
    }

    /// Whether the total is a lower bound because some lengths are unknown.
    public var isApproximate: Bool {
        unknownCount > 0
    }

    /// `total / target` (may exceed 1), or nil without a target.
    public var progress: Double? {
        guard let target, target > 0 else { return nil }
        return total / target
    }

    /// The running total as the builder header shows it: "38:20"; "≥38:20 + 2 unknown" when
    /// some lengths are unknown; "2 unknown" when none is known.
    public var totalText: String {
        guard isApproximate else { return Self.format(total) }
        guard total > 0 else { return "\(unknownCount) unknown" }
        return "\(Self.lowerBoundPrefix)\(Self.format(total)) + \(unknownCount) unknown"
    }

    /// Marks a time as a lower bound ("≥13:50"): later than shown by the unknown lengths.
    public static let lowerBoundPrefix = "≥"

    /// The length a song declares through `{duration}`, if any.
    public static func directiveLength(of song: SongRecord) -> SongLength? {
        song.document.metadata.duration.map { SongLength(seconds: $0, source: .directive) }
    }

    /// Text for an unknown length.
    public static let unknownText = "--:--"

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

    /// A row's length ("3:40") or `--:--` when unknown.
    public static func format(_ length: SongLength?) -> String {
        length.map { format($0.seconds) } ?? unknownText
    }
}
