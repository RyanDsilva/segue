// Phase 2 frozen interface (docs/phases/2-interfaces.md). Owner: unit D.
//
// Start times and the running total for the setlist builder ("library to set" layout: each
// row shows its start time; the header shows total vs target).
//
// Ruling (decisions.md, phase 2 build rulings, R172): an unknown time is never made up. The
// row shows `--:--` and adds nothing to the total. Everything after it is a lower bound,
// written with "≥" (start "≥13:50", total "≥38:20 + 2 unknown"); a lower bound of zero says
// nothing, so it reads `--:--` (a start) or "2 unknown" (the total). A slot's time is its
// song's tempo times the bars of the passes it plays (`SlotTimes`, P8-8 section 5.3); a total
// that includes a time resting on default chord lengths reads "~" (R173).
//
// Phase 3 (R85, R86, R105): break rows split the set into parts, each with its own total
// (slot times + changeovers + its unknown count); a changeover is added after every song
// but the last of each part; a break's optional intermission counts in the whole total only.

import Foundation
import Library

/// Where a row's time came from.
public enum ItemTimeSource: Sendable, Hashable {
    /// The full song's timeline.
    case song
    /// An arranged slot's played passes (R122, R149).
    case arrangement
    /// A break row's intermission (R105).
    case intermission
    /// A medley slot: its members' known times summed (P9-3 7).
    case medley
}

/// A known row time.
public struct ItemTime: Sendable, Hashable {
    public var seconds: TimeInterval
    public var source: ItemTimeSource
    /// Rests on default chord lengths ("~3:40", R173).
    public var estimated: Bool

    public init(seconds: TimeInterval, source: ItemTimeSource, estimated: Bool = false) {
        self.seconds = seconds
        self.source = source
        self.estimated = estimated
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
    /// Known slot times plus changeovers (between this part's songs only).
    public var total: TimeInterval
    /// The song slots in this part with an unknown time, in order.
    public var unknownItemIds: [SetlistItemID]
    /// Some known time in this part rests on default chord lengths.
    public var isEstimated: Bool

    public init(
        breakItemId: SetlistItemID? = nil,
        label: String? = nil,
        songItemIds: [SetlistItemID] = [],
        total: TimeInterval = 0,
        unknownItemIds: [SetlistItemID] = [],
        isEstimated: Bool = false,
    ) {
        self.breakItemId = breakItemId
        self.label = label
        self.songItemIds = songItemIds
        self.total = total
        self.unknownItemIds = unknownItemIds
        self.isEstimated = isEstimated
    }

    public var unknownCount: Int {
        unknownItemIds.count
    }

    /// A medley joins the part: its known time counts and each member without a time is
    /// unknown (P9-3 7: the unknown counts count songs, not slots).
    mutating func add(medley item: SetlistItemID, time: ItemTime?, unknown: [SetlistItemID]) {
        songItemIds.append(item)
        if let time {
            total += time.seconds
            isEstimated = isEstimated || time.estimated
        }
        unknownItemIds.append(contentsOf: unknown)
    }

    /// A song slot joins the part: its known time counts, else it is unknown.
    mutating func add(_ item: SetlistItemID, time: ItemTime?) {
        songItemIds.append(item)
        if let time {
            total += time.seconds
            isEstimated = isEstimated || time.estimated
        } else {
            unknownItemIds.append(item)
        }
    }

    /// The part total in the phase 2 notation ("12:00", "≥12:00 + 1 unknown", "~12:00").
    public var totalText: String {
        SetlistTiming.totalText(total: total, unknown: unknownCount, estimated: isEstimated)
    }
}

/// One row's timing.
public struct ItemTiming: Sendable, Hashable {
    public var itemId: SetlistItemID
    /// Offset from the start of the set, in seconds, counting known times only.
    public var start: TimeInterval
    /// True when an earlier row has an unknown time, so `start` is a lower bound
    /// (shown as "≥12:40", see `startText`).
    public var startIsApproximate: Bool
    /// Nil when the slot's time is unknown (shown as `--:--`). For a break row: its
    /// intermission (source `.intermission`), nil when it has none.
    public var time: ItemTime?
    /// A song slot's time as computed (its help text); nil for a break row or a medley.
    public var slot: SlotTime?
    /// A medley slot's time as computed, with each member's start (P9-3 7); nil otherwise.
    public var medley: MedleyTiming?

    public init(
        itemId: SetlistItemID,
        start: TimeInterval,
        startIsApproximate: Bool = false,
        time: ItemTime?,
        slot: SlotTime? = nil,
        medley: MedleyTiming? = nil,
    ) {
        self.itemId = itemId
        self.start = start
        self.startIsApproximate = startIsApproximate
        self.time = time
        self.slot = slot
        self.medley = medley
    }

    /// Why a song slot has no time; nil when known or a break row.
    public var unknown: UnknownTime? {
        slot?.unknown
    }

    /// The row's Time cell: "3:40", "~3:40" when estimated, `--:--` when unknown; a medley
    /// "≥5:30" when a member has no time ("~≥5:30" when also estimated).
    public var timeText: String {
        if let medley {
            return medley.time.clock
        }
        guard let time else { return SetlistTiming.unknownText }
        return (time.estimated ? SetlistTiming.estimatedPrefix : "") + SetlistTiming
            .format(time.seconds)
    }

    /// The start as the builder shows it: "12:40"; "≥12:40" after an unknown time; `--:--`
    /// when every earlier time is unknown (a lower bound of 0:00 says nothing).
    public var startText: String {
        guard startIsApproximate else { return SetlistTiming.format(start) }
        guard start > 0 else { return SetlistTiming.unknownText }
        return SetlistTiming.lowerBoundPrefix + SetlistTiming.format(start)
    }
}

/// A medley row's timing (P9-3 7): the medley's time and each member's start and time, for
/// the nested member rows.
public struct MedleyTiming: Sendable, Hashable {
    /// The medley's member times.
    public var time: MedleyTime
    /// One per member, in order: the member's item ID, start and time.
    public var members: [ItemTiming]

    public init(time: MedleyTime, members: [ItemTiming]) {
        self.time = time
        self.members = members
    }

    /// The members without a time (item IDs, in order).
    public var unknownMembers: [SetlistItemID] {
        time.unknownMembers.compactMap { index in
            members.indices.contains(index) ? members[index].itemId : nil
        }
    }

    /// Whether any known member rests on default chord lengths.
    public var estimated: Bool {
        time.estimated
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
    /// How many songs have an unknown time (not counted in `total`): song slots and
    /// medley members (P9-3 7).
    public var unknownCount: Int
    /// The song slots and medley members with an unknown time, in set order (the no-time
    /// list, P8-8 5.5).
    public var unknownItemIds: [SetlistItemID]
    /// Some known slot time rests on default chord lengths ("~", R173).
    public var isEstimated: Bool
    /// The setlist's target length, if set.
    public var target: TimeInterval?
    /// The changeover the totals include, in seconds (0 for none).
    public var changeover: TimeInterval

    /// Computes timings for `entries`.
    /// - Parameters:
    ///   - times: each song slot's time (`SlotTimes.slot`); slots absent here are unknown.
    ///   - medleyTimes: each medley slot's time (`SlotTimes.medley`); a medley absent here
    ///     has every member unknown.
    ///   - changeover: seconds between slots, added after every slot but the last of each
    ///     part (R86); never between a medley's members.
    public init(
        entries: [SetlistEntry],
        times: [SetlistItemID: SlotTime],
        medleyTimes: [SetlistItemID: MedleyTime] = [:],
        target: TimeInterval?,
        changeover: TimeInterval = 0,
    ) {
        let changeover = max(changeover, 0)
        var tally = Tally(changeover: changeover)
        for entry in entries {
            switch entry.kind {
            case let .break(info):
                tally.addBreak(entry.itemId, info)
            case .song:
                tally.addSong(entry, slot: times[entry.itemId] ?? .unknown(.noTempo))
            case let .medley(medley):
                tally.addMedley(entry.itemId, medley, time: medleyTimes[entry.itemId])
            }
        }
        tally.parts.append(tally.part)
        items = tally.items
        parts = tally.parts
        total = tally.start
        unknownCount = tally.unknown.count
        unknownItemIds = tally.unknown
        isEstimated = parts.contains(where: \.isEstimated)
        self.target = target
        self.changeover = changeover
    }

    /// The running state while timing the entries in order.
    private struct Tally {
        let changeover: TimeInterval
        var start: TimeInterval = 0
        var items: [ItemTiming] = []
        var parts: [PartTiming] = []
        var part = PartTiming()
        var unknown: [SetlistItemID] = []

        init(changeover: TimeInterval) {
            self.changeover = changeover
        }

        mutating func addBreak(_ itemId: SetlistItemID, _ info: SetlistBreak) {
            let pause = (info.length ?? 0) > 0 ? info.length : nil
            items.append(ItemTiming(
                itemId: itemId,
                start: start,
                startIsApproximate: !unknown.isEmpty,
                time: pause.map { ItemTime(seconds: $0, source: .intermission) },
            ))
            start += pause ?? 0
            parts.append(part)
            part = PartTiming(breakItemId: itemId, label: info.label)
        }

        /// A changeover before every slot but the first of its part.
        private mutating func changeoverBefore() {
            if !part.songItemIds.isEmpty {
                start += changeover
                part.total += changeover
            }
        }

        mutating func addSong(_ entry: SetlistEntry, slot: SlotTime) {
            changeoverBefore()
            let time = SetlistTiming.time(of: entry, slot: slot)
            items.append(ItemTiming(
                itemId: entry.itemId,
                start: start,
                startIsApproximate: !unknown.isEmpty,
                time: time,
                slot: slot,
            ))
            part.add(entry.itemId, time: time)
            start += time?.seconds ?? 0
            if time == nil {
                unknown.append(entry.itemId)
            }
        }

        /// A medley: one changeover before it, none between its members; each member
        /// without a time is unknown. An empty medley is left out (P9-3 5.3).
        mutating func addMedley(
            _ itemId: SetlistItemID,
            _ medley: SetlistMedley,
            time medleyTime: MedleyTime?,
        ) {
            guard !medley.members.isEmpty else {
                items.append(ItemTiming(
                    itemId: itemId,
                    start: start,
                    startIsApproximate: !unknown.isEmpty,
                    time: nil,
                ))
                return
            }
            changeoverBefore()
            let medleyTime = medleyTime
                ?? MedleyTime(members: medley.members.map { _ in .unknown(.noTempo) })
            let timing = SetlistTiming.medleyTiming(
                medley,
                time: medleyTime,
                start: start,
                approximate: !unknown.isEmpty,
            )
            let time: ItemTime? = medleyTime.hasKnown
                ? ItemTime(
                    seconds: medleyTime.known,
                    source: .medley,
                    estimated: medleyTime.estimated,
                )
                : nil
            items.append(ItemTiming(
                itemId: itemId,
                start: start,
                startIsApproximate: !unknown.isEmpty,
                time: time,
                medley: timing,
            ))
            part.add(medley: itemId, time: time, unknown: timing.unknownMembers)
            start += time?.seconds ?? 0
            unknown.append(contentsOf: timing.unknownMembers)
        }
    }

    /// Each member's start (the known times before it in the medley) and time.
    static func medleyTiming(
        _ medley: SetlistMedley,
        time: MedleyTime,
        start: TimeInterval,
        approximate: Bool,
    ) -> MedleyTiming {
        var offset = start
        var lowerBound = approximate
        var members: [ItemTiming] = []
        for (index, member) in medley.members.enumerated() {
            let slot = time.members.indices.contains(index) ? time.members[index]
                : .unknown(.noTempo)
            let known = slot.seconds.flatMap { $0 > 0 ? $0 : nil }
            members.append(ItemTiming(
                itemId: member.itemId,
                start: offset,
                startIsApproximate: lowerBound,
                time: known.map {
                    ItemTime(
                        seconds: $0,
                        source: member.arrangement == nil ? .song : .arrangement,
                        estimated: slot.isEstimated,
                    )
                },
                slot: slot,
            ))
            offset += known ?? 0
            lowerBound = lowerBound || known == nil
        }
        return MedleyTiming(time: time, members: members)
    }

    /// The timing of a medley member, if `itemId` is one.
    public func member(_ itemId: SetlistItemID) -> ItemTiming? {
        for item in items {
            if let member = item.medley?.members.first(where: { $0.itemId == itemId }) {
                return member
            }
        }
        return nil
    }

    /// A song slot's known time, nil when unknown.
    static func time(of entry: SetlistEntry, slot: SlotTime) -> ItemTime? {
        guard let seconds = slot.seconds, seconds > 0 else { return nil }
        return ItemTime(
            seconds: seconds,
            source: entry.arrangement == nil ? .song : .arrangement,
            estimated: slot.isEstimated,
        )
    }

    /// The part a break row opens, if `itemId` is one.
    public func part(openedBy itemId: SetlistItemID) -> PartTiming? {
        parts.first { $0.breakItemId == itemId }
    }

    /// Whether the total is a lower bound because some times are unknown.
    public var isApproximate: Bool {
        unknownCount > 0
    }

    /// `total / target` (may exceed 1), or nil without a target.
    public var progress: Double? {
        guard let target, target > 0 else { return nil }
        return total / target
    }

    /// The running total as the builder header shows it: "38:20"; "≥38:20 + 2 unknown" when
    /// some times are unknown; "2 unknown" when none is known; "~38:20" when a known time
    /// rests on default chord lengths.
    public var totalText: String {
        Self.totalText(total: total, unknown: unknownCount, estimated: isEstimated)
    }

    /// A total in the phase 2 notation: "38:20"; "≥38:20 + 2 unknown"; "2 unknown" when
    /// nothing is known; "~" first when `estimated` ("~≥38:20 + 2 unknown").
    public static func totalText(total: TimeInterval, unknown: Int, estimated: Bool = false)
        -> String
    {
        let known = (estimated && total > 0 ? estimatedPrefix : "") + format(total)
        guard unknown > 0 else { return known }
        guard total > 0 else { return "\(unknown) unknown" }
        let prefix = (estimated ? estimatedPrefix : "") + lowerBoundPrefix
        return "\(prefix)\(format(total)) + \(unknown) unknown"
    }

    /// VoiceOver for a total: "38 minutes 20 seconds", "38 minutes 20 seconds so far,
    /// incomplete: 2 songs have no time".
    public static func spokenTotal(total: TimeInterval, unknown: Int, estimated: Bool = false)
        -> String
    {
        let known = (estimated ? "About " : "") + SlotTime.spoken(total)
        guard unknown > 0 else { return known }
        let songs = unknown == 1 ? "1 song has no time" : "\(unknown) songs have no time"
        guard total > 0 else { return "Incomplete: \(songs)" }
        return "\(known) so far, incomplete: \(songs)"
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

    /// Marks a time as a lower bound ("≥13:50"): later than shown by the unknown times.
    public static let lowerBoundPrefix = "≥"

    /// Marks a time that rests on default chord lengths ("~3:40", R173).
    public static let estimatedPrefix = "~"

    /// Text for an unknown time.
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
}
