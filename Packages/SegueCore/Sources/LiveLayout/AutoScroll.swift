// Phase 2 frozen interface (docs/phases/2-interfaces.md). Owner: unit B.

import Foundation

/// Where an auto-scroll speed came from.
public enum ScrollSpeedSource: Sendable, Hashable {
    /// The item's time from its timeline (`SlotTimes`, tempo x the played bars, P8-8 5.6):
    /// the overflow scrolls over that time minus the lead-in.
    case timeline
    /// No timeline time (a chordless song with a tempo): estimated from `{tempo}` and
    /// `{time}` (beats per line).
    case tempo
    /// Neither: `ScrollSpeedModel.defaultSpeed`.
    case fallback
}

/// One stretch of a piecewise scroll (P9-3 9.7): from `fromOffset` on (until the next
/// segment's), the content moves at `speed` points per second.
public struct ScrollSegment: Sendable, Hashable {
    public var fromOffset: Double
    public var speed: Double

    public init(fromOffset: Double, speed: Double) {
        self.fromOffset = fromOffset
        self.speed = speed
    }
}

/// A derived auto-scroll speed.
public struct ScrollSpeed: Sendable, Hashable {
    /// The speed (a piecewise speed's first segment's).
    public var pointsPerSecond: Double
    /// Seconds after start before the content moves (the song's intro).
    public var leadIn: TimeInterval
    public var source: ScrollSpeedSource
    /// A medley's per-member speeds, in offset order (P9-3 9.7); empty: `pointsPerSecond`
    /// all the way.
    public var segments: [ScrollSegment]

    public init(
        pointsPerSecond: Double,
        leadIn: TimeInterval,
        source: ScrollSpeedSource,
        segments: [ScrollSegment] = [],
    ) {
        self.pointsPerSecond = pointsPerSecond
        self.leadIn = leadIn
        self.source = source
        self.segments = segments
    }

    /// The segments the scroll moves through: one at `pointsPerSecond` from the top when
    /// the speed is uniform.
    var pieces: [ScrollSegment] {
        segments.isEmpty ? [ScrollSegment(fromOffset: 0, speed: pointsPerSecond)] : segments
    }

    /// Where the scroll is after moving for `seconds` from `offset`.
    func offset(from offset: Double, moving seconds: TimeInterval) -> Double {
        let pieces = pieces
        var position = offset
        var remaining = max(0, seconds)
        var index = pieces.lastIndex { $0.fromOffset <= position } ?? 0
        while remaining > 0 {
            let speed = max(0, pieces[index].speed)
            guard index + 1 < pieces.count else {
                return position + remaining * speed
            }
            let end = pieces[index + 1].fromOffset
            if end > position {
                guard speed > 0 else { return position }
                let time = (end - position) / speed
                if time >= remaining {
                    return position + remaining * speed
                }
                remaining -= time
                position = end
            }
            index += 1
        }
        return position
    }

    /// Seconds of movement from `start` to `target` (above it); nil when a segment on the
    /// way never moves.
    func seconds(from start: Double, to target: Double) -> TimeInterval? {
        let pieces = pieces
        var position = start
        var total: TimeInterval = 0
        var index = pieces.lastIndex { $0.fromOffset <= position } ?? 0
        while position < target {
            let end = index + 1 < pieces.count ? min(pieces[index + 1].fromOffset, target)
                : target
            if end > position {
                let speed = pieces[index].speed
                guard speed > 0 else { return nil }
                total += (end - position) / speed
                position = end
            }
            index += 1
        }
        return total
    }
}

/// Inputs for the speed derivation.
public struct ScrollSpeedInput: Sendable, Hashable {
    /// `LayoutPlan.overflow`.
    public var overflow: Double
    /// The item's played time in seconds (`SlotTimes.time(of:)`); nil when unknown.
    public var playedTime: TimeInterval?
    /// `{tempo}` BPM.
    public var tempo: Double?
    /// `{time}` ("4/4", "3/4", "6/8").
    public var time: String?
    /// `LayoutPlan.lineCount`.
    public var lineCount: Int
    /// `LivePrefs.scrollSpeedFactor`.
    public var factor: Double

    public init(
        overflow: Double,
        playedTime: TimeInterval?,
        tempo: Double?,
        time: String?,
        lineCount: Int,
        factor: Double = 1,
    ) {
        self.overflow = overflow
        self.playedTime = playedTime
        self.tempo = tempo
        self.time = time
        self.lineCount = lineCount
        self.factor = factor
    }
}

/// Speed derivation (phase 2 spec, "Auto-scroll"). Pure.
public enum ScrollSpeedModel {
    /// Lead-in before scrolling starts (the intro offset).
    public static let leadIn: TimeInterval = 10
    /// Speed used when the song has no tempo (adjusted with [ and ]).
    public static let defaultSpeed: Double = 12
    /// Multiplier applied per `[` / `]` nudge.
    public static let nudgeStep = 1.1

    /// The shortest scroll time a played time may leave after the lead-in; shorter songs
    /// scroll over their whole time with no lead-in.
    public static let minimumScrollTime: TimeInterval = 20
    /// Bars one lyric line takes, for the tempo estimate.
    public static let barsPerLine = 2.0

    public static func speed(_ input: ScrollSpeedInput) -> ScrollSpeed {
        let factor = input.factor.isFinite && input.factor > 0 ? input.factor : 1
        let overflow = max(0, input.overflow)
        if let played = input.playedTime, played.isFinite, played > 0 {
            return derived(overflow: overflow, seconds: played, factor: factor, .timeline)
        }
        if let estimate = estimatedTime(input) {
            return derived(overflow: overflow, seconds: estimate, factor: factor, .tempo)
        }
        return ScrollSpeed(
            pointsPerSecond: defaultSpeed * factor,
            leadIn: leadIn,
            source: .fallback,
        )
    }

    /// `lineCount` lines x `barsPerLine` bars x beats per bar at `tempo`. Compound metres
    /// (6/8, 9/8, 12/8) count the dotted beat.
    public static func estimatedTime(_ input: ScrollSpeedInput) -> TimeInterval? {
        guard let tempo = input.tempo, tempo.isFinite, tempo > 0, input.lineCount > 0 else {
            return nil
        }
        return Double(input.lineCount) * barsPerLine * beatsPerBar(input.time) * 60 / tempo
    }

    static func beatsPerBar(_ time: String?) -> Double {
        let parts = (time ?? "").split(separator: "/").map {
            Int($0.trimmingCharacters(in: .whitespaces))
        }
        guard parts.count == 2, let top = parts[0], let bottom = parts[1], top > 0, bottom > 0
        else { return 4 }
        if bottom == 8, top.isMultiple(of: 3), top > 3 {
            return Double(top / 3)
        }
        return Double(top)
    }

    private static func derived(
        overflow: Double,
        seconds: TimeInterval,
        factor: Double,
        _ source: ScrollSpeedSource,
    ) -> ScrollSpeed {
        let lead = seconds - leadIn >= minimumScrollTime ? leadIn : 0
        let time = seconds - lead
        return ScrollSpeed(pointsPerSecond: overflow / time * factor, leadIn: lead, source: source)
    }
}

/// Auto-scroll position over time, driven by injected instants (no timers), so a 3-minute
/// song can be tested without waiting. Never moves until `start`.
public struct AutoScroller: Sendable, Hashable {
    public enum Phase: Sendable, Hashable {
        case idle
        case running
        case paused
        /// Reached the end of the overflow.
        case finished
    }

    public private(set) var phase: Phase
    public private(set) var speed: ScrollSpeed
    public private(set) var overflow: Double
    /// Offset at `anchor` (or the held offset when not running).
    private var base: Double
    /// When `base` was taken (running only).
    private var anchor: Date?
    /// Lead-in still to wait before moving (a start from the top, possibly paused mid-way).
    private var pendingLeadIn: TimeInterval

    /// Idle at the top.
    public init(speed: ScrollSpeed, overflow: Double) {
        phase = .idle
        self.speed = speed
        self.overflow = max(0, overflow)
        base = 0
        anchor = nil
        pendingLeadIn = speed.leadIn
    }

    /// Offset in points at `now` (0 ... overflow).
    public func offset(at now: Date) -> Double {
        guard phase == .running, let anchor else {
            return min(base, overflow)
        }
        let moving = max(0, now.timeIntervalSince(anchor) - pendingLeadIn)
        return min(overflow, max(0, speed.offset(from: base, moving: moving)))
    }

    /// The phase at `now`: `.finished` once a running scroll has reached the end.
    public func phase(at now: Date) -> Phase {
        if phase == .running, offset(at: now) >= overflow {
            return .finished
        }
        return phase
    }

    /// Starts (or resumes) at `now`. The lead-in applies only to a start from the top.
    public mutating func start(at now: Date) {
        switch phase(at: now) {
        case .finished, .running:
            settle(at: now)
        case .idle, .paused:
            if base > 0 {
                pendingLeadIn = 0
            }
            anchor = now
            phase = overflow > 0 && base < overflow ? .running : .finished
        }
    }

    public mutating func pause(at now: Date) {
        guard phase == .running, let anchor else { return }
        let elapsed = now.timeIntervalSince(anchor)
        base = offset(at: now)
        pendingLeadIn = max(0, pendingLeadIn - elapsed)
        self.anchor = nil
        phase = base >= overflow ? .finished : .paused
    }

    /// Back to the top, idle.
    public mutating func restart(at _: Date) {
        phase = .idle
        base = 0
        anchor = nil
        pendingLeadIn = speed.leadIn
    }

    /// Manual scroll or page step: continues from `offset` (keeps running if running).
    public mutating func seek(to offset: Double, at now: Date) {
        base = min(max(0, offset), overflow)
        pendingLeadIn = 0
        switch phase(at: now) {
        case .running:
            anchor = now
            if base >= overflow {
                phase = .finished
                anchor = nil
            }
        case .finished:
            phase = base >= overflow ? .finished : .paused
            anchor = nil
        case .idle, .paused:
            anchor = nil
        }
    }

    /// A seek that then holds the scroll still for `holding` seconds before it moves on at
    /// the same speed (the rehearsal loop's one-bar count-in, P8-2). Not running: a plain
    /// seek.
    public mutating func seek(to offset: Double, at now: Date, holding: TimeInterval) {
        seek(to: offset, at: now)
        if phase == .running {
            pendingLeadIn = max(0, holding)
        }
    }

    /// A medley's per-member speeds (P9-3 9.7); empty for one speed throughout.
    public var segments: [ScrollSegment] {
        speed.segments
    }

    /// When a running scroll will reach `offset`, through every segment on the way: nil when
    /// it is not running, is already at or past it, never moves, or stops at the end of the
    /// overflow first (P8-2, the loop wrap).
    public func instant(reaching offset: Double) -> Date? {
        guard phase == .running, let anchor, offset > base, offset <= overflow,
              let seconds = speed.seconds(from: base, to: offset)
        else { return nil }
        return anchor.addingTimeInterval(pendingLeadIn + seconds)
    }

    /// A new speed from `now` on (nudge), keeping the current offset.
    public mutating func setSpeed(_ speed: ScrollSpeed, at now: Date) {
        rebase(at: now)
        self.speed = speed
        if phase == .idle, base == 0 {
            pendingLeadIn = speed.leadIn
        }
    }

    /// A re-layout changed the overflow (zoom, resize): keeps the same fraction.
    public mutating func setOverflow(_ overflow: Double, at now: Date) {
        rebase(at: now)
        let fraction = self.overflow > 0 ? base / self.overflow : 0
        self.overflow = max(0, overflow)
        base = fraction * self.overflow
        if phase == .finished, base < self.overflow {
            phase = .paused
        }
    }

    /// Records a running scroll that reached the end as `.finished` (call from the display
    /// tick; `offset(at:)` already clamps, so this only updates `phase`).
    public mutating func settle(at now: Date) {
        if phase(at: now) == .finished, phase == .running {
            base = overflow
            anchor = nil
            phase = .finished
        }
    }

    /// Moves the anchor to `now`, keeping the offset and the remaining lead-in.
    private mutating func rebase(at now: Date) {
        settle(at: now)
        guard phase == .running, let anchor else { return }
        let elapsed = now.timeIntervalSince(anchor)
        base = offset(at: now)
        pendingLeadIn = max(0, pendingLeadIn - elapsed)
        self.anchor = now
    }
}
