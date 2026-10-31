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
