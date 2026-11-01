// P8-8c (docs/phases/8-workstreams/P8-8-artists-movie-and-slot-time.md section 5.2, R172,
// R173). A song's or a slot's time: the song's tempo times the bars of the passes played,
// read from the one `SongTimeline`. No tempo or no chords is unknown, never a guess. Pure.

import ChordPro
import Editing
import Foundation

/// Why a slot has no time.
public enum UnknownTime: String, Sendable, Hashable, CaseIterable {
    /// The song has no readable `{tempo}`.
    case noTempo
    /// Nothing to time: no chords in the played passes.
    case noChords
    /// A medley member whose song is missing from the library (P9-3 7): "no chords" or "no
    /// tempo" would be false.
    case missingSong
}

/// How long a song or slot plays.
public enum SlotTime: Sendable, Hashable {
    /// `seconds` at the tempo map; `bars` from the timeline's bar grid; `tempo` the BPM in
    /// effect at the first played chord; `estimated` when any played chord's length came from
    /// the song's rule (`TimingSource.rule`), shown as "~3:40" (R173).
    case known(seconds: TimeInterval, bars: Int, tempo: Double, estimated: Bool)
    case unknown(UnknownTime)

    /// The seconds when known.
    public var seconds: TimeInterval? {
        if case let .known(seconds, _, _, _) = self {
            return seconds
        }
        return nil
    }

    /// Why it is unknown, when it is.
    public var unknown: UnknownTime? {
        if case let .unknown(reason) = self {
            return reason
        }
        return nil
    }

    /// Whether the known time rests on any default chord length.
    public var isEstimated: Bool {
        if case let .known(_, _, _, estimated) = self {
            return estimated
        }
        return false
    }
}

public enum SlotTimes {
    /// The whole song in written order (`{chorus}` stubs written out): a new slot, the
    /// assistant's candidates, the composer's ghost.
    public static func song(_ record: SongRecord) -> SlotTime {
        time(of: timeline(record, order: nil))
    }

    /// A setlist slot: its arrangement's played passes when it resolves `.applied`, else the
    /// full song (an out-of-date arrangement plays the full song on stage, R122).
    public static func slot(_ record: SongRecord, arrangement: SlotArrangement?) -> SlotTime {
        guard let arrangement else { return song(record) }
        let sections = sections(of: record.document)
        let units = SongSections.units(of: sections)
        guard case let .applied(order, _) = ArrangementResolver.resolve(arrangement, units: units)
        else {
            return time(of: timeline(record, sections: sections, units: units, order: nil))
        }
        return time(of: timeline(record, sections: sections, units: units, order: order))
    }

    /// A medley slot (P9-3 7): each member's `slot(_:arrangement:)` in order; a member whose
    /// song is missing (nil record) is unknown with `.missingSong`. No changeover and no
    /// transition time between members.
    public static func medley(
        _ members: [(record: SongRecord?, arrangement: SlotArrangement?)],
    ) -> MedleyTime {
        MedleyTime(members: members.map { member in
            member.record.map { slot($0, arrangement: member.arrangement) }
                ?? .unknown(.missingSong)
        })
    }

    /// The rule for any timeline (also the stage's).
    public static func time(of timeline: SongTimeline) -> SlotTime {
        guard !timeline.chords.isEmpty, timeline.totalTicks > 0,
              timeline.chords.contains(where: { !$0.isSilent })
        else {
            return .unknown(.noChords)
        }
        // The tempo map's initial value covers every chord once any `{tempo}` exists, so a
        // chord without one means the song has none.
        guard let tempo = timeline.chords.first?.tempo,
              !timeline.chords.contains(where: { $0.tempo == nil })
        else {
            return .unknown(.noTempo)
        }
        let seconds = timeline.seconds(at: timeline.totalTicks, factor: 1)
        // Every chord carries a tempo, so no fallback BPM is ever read.
        assert(seconds == timeline.seconds(at: timeline.totalTicks, factor: 1, fallback: 1))
        let bars = timeline.barBeat(at: timeline.totalTicks - 1).bar
        let estimated = timeline.chords.contains { !$0.isSilent && $0.isEstimated }
        return .known(seconds: seconds, bars: bars, tempo: tempo, estimated: estimated)
    }

    // MARK: Building

    /// The song's sections as `SongSections.units(of:)` indexes them.
    static func sections(of document: SongDocument) -> [RenderSection] {
        RenderModel(document: document, options: DisplayOptions()).sections
    }

    static func timeline(_ record: SongRecord, order: [PlayedPass]?) -> SongTimeline {
        let sections = sections(of: record.document)
        return timeline(
            record,
            sections: sections,
            units: SongSections.units(of: sections),
            order: order,
        )
    }

    static func timeline(
        _ record: SongRecord,
        sections: [RenderSection],
        units: [SongSectionUnit],
        order: [PlayedPass]?,
    ) -> SongTimeline {
        SongTimeline.build(
            document: record.document,
            sections: sections,
            units: units,
            timing: record.sidecar.bass.timing,
            order: order,
        )
    }
}

public extension SlotTime {
    /// "3:40", "~3:40" when estimated, "--:--" when unknown (the set row's Time cell).
    var clock: String {
        switch self {
        case let .known(seconds, _, _, estimated):
            (estimated ? "~" : "") + Self.clock(seconds)
        case .unknown:
            "--:--"
        }
    }

    /// "96 BPM, 72 bars" (", chord lengths estimated" when estimated), "No tempo", or "No
    /// chords to time".
    var help: String {
        switch self {
        case let .known(_, bars, tempo, estimated):
            "\(Int(tempo.rounded())) BPM, \(bars) \(bars == 1 ? "bar" : "bars")"
                + (estimated ? ", chord lengths estimated" : "")
        case .unknown(.noTempo):
            "No tempo"
        case .unknown(.noChords):
            "No chords to time"
        case .unknown(.missingSong):
            "Song missing"
        }
    }

    /// VoiceOver: "3 minutes 40 seconds", "About 3 minutes 40 seconds", "Unknown, no tempo".
    var spoken: String {
        switch self {
        case let .known(seconds, _, _, estimated):
            let words = Self.spoken(seconds)
            return estimated ? "About \(words)" : words
        case .unknown(.noTempo):
            return "Unknown, no tempo"
        case .unknown(.noChords):
            return "Unknown, no chords to time"
        case .unknown(.missingSong):
            return "Unknown, song missing"
        }
    }

    /// "m:ss" of whole seconds (rounded for display only).
    static func clock(_ seconds: TimeInterval) -> String {
        let whole = max(0, Int(seconds.rounded()))
        return String(format: "%d:%02d", whole / 60, whole % 60)
    }

    /// "3 minutes 40 seconds" of whole seconds.
    static func spoken(_ seconds: TimeInterval) -> String {
        let whole = max(0, Int(seconds.rounded()))
        let minutes = whole / 60
        let rest = whole % 60
        var parts: [String] = []
        if minutes > 0 {
            parts.append("\(minutes) \(minutes == 1 ? "minute" : "minutes")")
        }
        if rest > 0 || minutes == 0 {
            parts.append("\(rest) \(rest == 1 ? "second" : "seconds")")
        }
        return parts.joined(separator: " ")
    }
}

/// A medley slot's time (P9-3 7, R172, R173): the sum of its members' known times, with no
/// changeover and no transition time between them. A member with an unknown time adds
/// nothing and makes the medley's time a lower bound; "~" when any known member is
/// estimated.
public struct MedleyTime: Sendable, Hashable {
    /// Each member's time, in member order.
    public var members: [SlotTime]

    public init(members: [SlotTime]) {
        self.members = members
    }

    /// The known members' seconds summed.
    public var known: TimeInterval {
        members.reduce(0) { $0 + ($1.seconds ?? 0) }
    }

    /// The indexes of members whose time is unknown.
    public var unknownMembers: [Int] {
        members.indices.filter { members[$0].seconds == nil }
    }

    /// Whether any known member rests on default chord lengths.
    public var estimated: Bool {
        members.contains(where: \.isEstimated)
    }

    /// Whether at least one member is known.
    public var hasKnown: Bool {
        members.contains { $0.seconds != nil }
    }

    /// The row's Time cell: "7:40"; with an unknown member the known members' sum, "5:30"
    /// (a total: no "≥", R189; the member row shows `--:--`); "~7:40" when estimated;
    /// `--:--` when no member is known.
    public var clock: String {
        guard hasKnown else { return "--:--" }
        return (estimated ? "~" : "") + SlotTime.clock(known)
    }

    /// The row's help: "Kesariya 2:40, Tum Hi Ho 2:10" when all are known, else "1 of 3
    /// songs has no time: no tempo".
    public func help(titles: [String]) -> String {
        let unknown = unknownMembers
        guard !unknown.isEmpty else {
            return zip(titles, members).map { "\($0) \($1.clock)" }.joined(separator: ", ")
        }
        let reasons = Set(unknown.compactMap { members[$0].unknown })
        let reason = reasons.count == 1 ? reasons.first.map(Self.reasonText) ?? "no time"
            : "no time"
        let verb = unknown.count == 1 ? "has" : "have"
        return "\(unknown.count) of \(members.count) songs \(verb) no time: \(reason)"
    }

    /// VoiceOver: "7 minutes 40 seconds, medley of 3 songs", "5 minutes 30
    /// seconds so far, incomplete: 1 song has no time".
    public var spoken: String {
        let unknown = unknownMembers.count
        guard unknown > 0 else {
            let words = SlotTime.spoken(known)
            return (estimated ? "About " + words : words) + ", medley of \(members.count) songs"
        }
        let songs = unknown == 1 ? "1 song has no time" : "\(unknown) songs have no time"
        guard hasKnown else { return "Unknown, incomplete: \(songs)" }
        return "\(SlotTime.spoken(known)) so far, incomplete: \(songs)"
    }

    static func reasonText(_ reason: UnknownTime) -> String {
        switch reason {
        case .noTempo: "no tempo"
        case .noChords: "no chords"
        case .missingSong: "song missing"
        }
    }
}
