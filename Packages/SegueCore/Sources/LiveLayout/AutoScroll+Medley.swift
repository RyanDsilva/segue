// P9-3 9.7 (R178): a medley scrolls at each member's own speed, so a slow song into a fast
// one reads right in both. Pure.

import Foundation

/// One member's stretch of a medley's scroll.
public struct MedleyScrollMember: Sendable, Hashable {
    /// The offset at which the member starts (its header at the reading line).
    public var fromOffset: Double
    /// The member's time from its played passes (`SlotTimes.slot`); nil when unknown.
    public var seconds: TimeInterval?

    public init(fromOffset: Double, seconds: TimeInterval?) {
        self.fromOffset = fromOffset
        self.seconds = seconds
    }
}

public extension ScrollSpeedModel {
    /// The medley's piecewise speed: each member covers the offsets up to the next member's
    /// start (the last up to `overflow`) over its own time, the song's lead-in taken from
    /// the first member's. A member with no time moves at the members' average known speed;
    /// with none known, every member moves at the default speed (source `.fallback`, the
    /// add-a-tempo hint). `factor` (`[` / `]`) scales every segment.
    static func medley(
        _ members: [MedleyScrollMember],
        overflow: Double,
        factor: Double = 1,
    ) -> ScrollSpeed {
        let factor = factor.isFinite && factor > 0 ? factor : 1
        let overflow = max(0, overflow)
        let starts = members.indices.map { index in
            index == 0 ? 0 : min(max(0, members[index].fromOffset), overflow)
        }
        let distances = starts.indices.map { index in
            max(0, (index + 1 < starts.count ? starts[index + 1] : overflow) - starts[index])
        }
        var times = members.map { $0.seconds.flatMap { $0.isFinite && $0 > 0 ? $0 : nil } }
        var lead = leadIn
        if let first = times.first, let seconds = first {
            lead = seconds - leadIn >= minimumScrollTime ? leadIn : 0
            times[0] = seconds - lead
        }
        let known = times.indices.filter { times[$0] != nil && distances[$0] > 0 }
        let knownTime = known.reduce(0) { $0 + (times[$1] ?? 0) }
        guard !known.isEmpty, knownTime > 0 else {
            return ScrollSpeed(
                pointsPerSecond: defaultSpeed * factor,
                leadIn: lead,
                source: .fallback,
            )
        }
        let average = known.reduce(0) { $0 + distances[$1] } / knownTime
        let segments = starts.indices.map { index in
            let speed = times[index].map { distances[index] / $0 } ?? average
            return ScrollSegment(fromOffset: starts[index], speed: speed * factor)
        }
        return ScrollSpeed(
            pointsPerSecond: segments.first?.speed ?? average * factor,
            leadIn: lead,
            source: .timeline,
            segments: segments,
        )
    }
}
