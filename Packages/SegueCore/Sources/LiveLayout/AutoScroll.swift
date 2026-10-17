// Phase 2 frozen interface (docs/phases/2-interfaces.md). Owner: unit B.

import Foundation

/// Where an auto-scroll speed came from.
public enum ScrollSpeedSource: Sendable, Hashable {
    /// `{duration}`: the overflow scrolls over the duration minus the lead-in.
    case duration
    /// No duration: estimated from `{tempo}` and `{time}` (beats per line).
    case tempo
    /// Neither: `ScrollSpeedModel.defaultSpeed`.
    case fallback
}

/// A derived auto-scroll speed.
public struct ScrollSpeed: Sendable, Hashable {
    public var pointsPerSecond: Double
    /// Seconds after start before the content moves (the song's intro).
    public var leadIn: TimeInterval
    public var source: ScrollSpeedSource

    public init(pointsPerSecond: Double, leadIn: TimeInterval, source: ScrollSpeedSource) {
        self.pointsPerSecond = pointsPerSecond
        self.leadIn = leadIn
        self.source = source
    }
}

/// Inputs for the speed derivation.
public struct ScrollSpeedInput: Sendable, Hashable {
    /// `LayoutPlan.overflow`.
    public var overflow: Double
    /// `{duration}` seconds.
    public var duration: TimeInterval?
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
        duration: TimeInterval?,
        tempo: Double?,
        time: String?,
        lineCount: Int,
        factor: Double = 1,
    ) {
        self.overflow = overflow
        self.duration = duration
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
    /// Speed used when the song has neither duration nor tempo.
    public static let defaultSpeed: Double = 12
    /// Multiplier applied per `[` / `]` nudge.
    public static let nudgeStep = 1.1

    public static func speed(_ input: ScrollSpeedInput) -> ScrollSpeed {
        fatalError("unimplemented: unit B (ScrollSpeedModel.speed)")
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

    /// Idle at the top.
    public init(speed: ScrollSpeed, overflow: Double) {
        phase = .idle
        self.speed = speed
        self.overflow = overflow
    }

    /// Offset in points at `now` (0 ... overflow).
    public func offset(at now: Date) -> Double {
        fatalError("unimplemented: unit B (AutoScroller.offset)")
    }

    /// Starts (or resumes) at `now`. The lead-in applies only to a start from the top.
    public mutating func start(at now: Date) {
        fatalError("unimplemented: unit B (AutoScroller.start)")
    }

    public mutating func pause(at now: Date) {
        fatalError("unimplemented: unit B (AutoScroller.pause)")
    }

    /// Back to the top, idle.
    public mutating func restart(at now: Date) {
        fatalError("unimplemented: unit B (AutoScroller.restart)")
    }

    /// Manual scroll or page step: continues from `offset` (keeps running if running).
    public mutating func seek(to offset: Double, at now: Date) {
        fatalError("unimplemented: unit B (AutoScroller.seek)")
    }

    /// A new speed from `now` on (nudge), keeping the current offset.
    public mutating func setSpeed(_ speed: ScrollSpeed, at now: Date) {
        fatalError("unimplemented: unit B (AutoScroller.setSpeed)")
    }

    /// A re-layout changed the overflow (zoom, resize): keeps the same fraction.
    public mutating func setOverflow(_ overflow: Double, at now: Date) {
        fatalError("unimplemented: unit B (AutoScroller.setOverflow)")
    }
}
