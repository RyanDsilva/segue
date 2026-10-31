// Phase 2 frozen interface (docs/phases/2-interfaces.md). Owner: unit D.
//
// Start times and the running total for the setlist builder ("library to set" layout: each
// row shows its start time; the header shows total vs target).
//
// Ruling (decisions.md, phase 2 build rulings): an unknown song length is never made up. The
// row shows `--:--` and adds nothing to the total. Everything after it is a lower bound,
// written with "≥" (start "≥13:50", total "≥38:20 + 2 unknown"); a lower bound of zero says
// nothing, so it reads `--:--` (a start) or "2 unknown" (the total).
//
// Phase 3 (R85, R86, R105): break rows split the set into parts, each with its own total
// (song lengths + changeovers + its unknown count); a changeover is added after every song
// but the last of each part; a break's optional intermission counts in the whole total only.

import Foundation
import Library

/// Where a length came from. Song lengths come only from `{duration}` (R91).
public enum SongLengthSource: Sendable, Hashable {
    /// The song's `{duration}` directive.
    case directive
    /// A break row's intermission (R105).
    case intermission
    /// An arranged slot's own length (R122): typed or timed for that slot, never derived
    /// from the song's `{duration}`.
    case slot
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

/// One part of a setlist: the songs before the first break row, or after a break row up to
/// the next one.
public struct PartTiming: Sendable, Hashable {
    /// The break row that opens this part; nil for the first part.
    public var breakItemId: SetlistItemID?
    /// The break's label ("Set 2"); nil for the first part.
    public var label: String?
    /// The song slots in this part, in order.
    public var songItemIds: [SetlistItemID]
    /// Known song lengths plus changeovers (between this part's songs only).
    public var total: TimeInterval
    /// The song slots in this part with an unknown length, in order.
    public var unknownItemIds: [SetlistItemID]

    public init(
        breakItemId: SetlistItemID? = nil,
        label: String? = nil,
        songItemIds: [SetlistItemID] = [],
        total: TimeInterval = 0,
        unknownItemIds: [SetlistItemID] = [],
    ) {
        self.breakItemId = breakItemId
        self.label = label
        self.songItemIds = songItemIds
        self.total = total
        self.unknownItemIds = unknownItemIds
    }

    public var unknownCount: Int {
        unknownItemIds.count
    }

    /// The part total in the phase 2 notation ("12:00", "≥12:00 + 1 unknown").
    public var totalText: String {
        SetlistTiming.totalText(total: total, unknown: unknownCount)
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
    /// Nil when the song's length is unknown (shown as `--:--`). For a break row: its
    /// intermission (source `.intermission`), nil when it has none.
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
    /// One per entry (songs and break rows), in setlist order.
    public var items: [ItemTiming]
    /// One per part, in order; always at least one (the part before the first break, which
    /// may be empty).
    public var parts: [PartTiming]
    /// The whole set: every part's total plus every break's intermission.
    public var total: TimeInterval
    /// How many song slots have an unknown length (not counted in `total`).
    public var unknownCount: Int
    /// The song slots with an unknown length, in set order (the missing-lengths list, R88).
    public var unknownItemIds: [SetlistItemID]
    /// The setlist's target length, if set.
    public var target: TimeInterval?
    /// The changeover the totals include, in seconds (0 for none).
    public var changeover: TimeInterval

    /// Computes timings for `entries`.
    /// - Parameters:
    ///   - lengths: known lengths by song (the `{duration}` directive); songs absent here
    ///     (or with a length of zero or less) are unknown.
    ///   - changeover: seconds between songs, added after every song but the last of each
    ///     part (R86).
    public init(
        entries: [SetlistEntry],
        lengths: [SongID: SongLength],
        target: TimeInterval?,
        changeover: TimeInterval = 0,
    ) {
        let changeover = max(changeover, 0)
        var start: TimeInterval = 0
        var items: [ItemTiming] = []
        items.reserveCapacity(entries.count)
        var parts: [PartTiming] = []
        var part = PartTiming()
        var unknown: [SetlistItemID] = []
        for entry in entries {
            switch entry.kind {
            case let .break(info):
                let pause = (info.length ?? 0) > 0 ? info.length : nil
                items.append(ItemTiming(
                    itemId: entry.itemId,
                    start: start,
                    startIsApproximate: !unknown.isEmpty,
                    length: pause.map { SongLength(seconds: $0, source: .intermission) },
                ))
                start += pause ?? 0
                parts.append(part)
                part = PartTiming(breakItemId: entry.itemId, label: info.label)
            case let .song(songID):
                if !part.songItemIds.isEmpty {
                    start += changeover
                    part.total += changeover
                }
                let length = Self.length(of: entry, song: songID, lengths: lengths)
                items.append(ItemTiming(
                    itemId: entry.itemId,
                    start: start,
                    startIsApproximate: !unknown.isEmpty,
                    length: length,
                ))
                part.songItemIds.append(entry.itemId)
                if let length {
                    start += length.seconds
                    part.total += length.seconds
                } else {
                    unknown.append(entry.itemId)
                    part.unknownItemIds.append(entry.itemId)
                }
            }
        }
        parts.append(part)
        self.items = items
        self.parts = parts
        total = start
        unknownCount = unknown.count
        unknownItemIds = unknown
        self.target = target
        self.changeover = changeover
    }

    /// A song slot's length: an arranged slot's own length (nil = unknown, whatever the
    /// song's `{duration}` says, R122), else the song's.
    static func length(
        of entry: SetlistEntry,
        song: SongID,
        lengths: [SongID: SongLength],
    ) -> SongLength? {
        if let arrangement = entry.arrangement {
            return arrangement.length.flatMap { seconds in
                seconds > 0 ? SongLength(seconds: seconds, source: .slot) : nil
            }
        }
        return lengths[song].flatMap { $0.seconds > 0 ? $0 : nil }
    }

    /// The part a break row opens, if `itemId` is one.
    public func part(openedBy itemId: SetlistItemID) -> PartTiming? {
        parts.first { $0.breakItemId == itemId }
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
        Self.totalText(total: total, unknown: unknownCount)
    }

    /// A total in the phase 2 notation: "38:20"; "≥38:20 + 2 unknown"; "2 unknown" when
    /// nothing is known.
    public static func totalText(total: TimeInterval, unknown: Int) -> String {
        guard unknown > 0 else { return format(total) }
        guard total > 0 else { return "\(unknown) unknown" }
        return "\(lowerBoundPrefix)\(format(total)) + \(unknown) unknown"
    }

    /// The totals' help text: "Includes 30 s changeovers between songs." Nil without a
    /// changeover.
    public var changeoverNote: String? {
        guard changeover > 0 else { return nil }
        return "Includes \(Self.formatChangeover(changeover)) changeovers between songs."
    }

    /// "30 s", "1:15" (a changeover as Settings and the help text show it).
    public static func formatChangeover(_ seconds: TimeInterval) -> String {
        let whole = Int(seconds.rounded())
        return whole < 60 ? "\(whole) s" : format(TimeInterval(whole))
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
