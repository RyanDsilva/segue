import Foundation
import Synchronization

/// Source of wall-clock time. Core code never calls `Date()` directly; it asks an injected
/// `Clock` so integration tests are reproducible.
///
/// Note: this shadows the standard library's `_Concurrency.Clock` inside modules that import
/// `Support`. Use `Swift.Clock` explicitly if the concurrency clock is ever needed there.
public protocol Clock: Sendable {
    /// The current instant.
    func now() -> Date
}

/// The real system clock.
public struct SystemClock: Clock {
    public init() {}

    public func now() -> Date {
        Date()
    }
}

/// A clock that only moves when told to. Used by tests for deterministic timestamps.
public final class ManualClock: Clock {
    private let current: Mutex<Date>

    /// Creates a clock frozen at `start` (default: 2026-01-01T00:00:00Z).
    public init(start: Date = Date(timeIntervalSince1970: 1_767_225_600)) {
        current = Mutex(start)
    }

    public func now() -> Date {
        current.withLock { $0 }
    }

    /// Moves the clock forward by `interval` seconds.
    public func advance(by interval: TimeInterval) {
        current.withLock { $0 = $0.addingTimeInterval(interval) }
    }

    /// Sets the clock to an absolute instant.
    public func set(_ date: Date) {
        current.withLock { $0 = date }
    }
}

/// A monotonic clock for measuring how long something has been running (auto-scroll):
/// `now()` is the wall-clock instant it was made plus the time elapsed on a
/// `SuspendingClock`, so it never jumps when NTP or the user sets the system clock, and it
/// does not advance while the Mac sleeps (a scroll paused by sleep resumes where it was).
/// Use it only for durations; its dates drift from wall-clock time by design.
public struct MonotonicClock: Clock {
    private let origin: Date
    private let elapsed: @Sendable () -> Duration

    /// Measures from now on the system's suspending clock.
    public init() {
        let clock = SuspendingClock()
        let start = clock.now
        self.init(origin: Date(), elapsed: { start.duration(to: clock.now) })
    }

    /// For tests: `elapsed` reports the monotonic time since `origin`.
    public init(origin: Date, elapsed: @escaping @Sendable () -> Duration) {
        self.origin = origin
        self.elapsed = elapsed
    }

    public func now() -> Date {
        let duration = elapsed()
        let seconds = Double(duration.components.seconds)
            + Double(duration.components.attoseconds) / 1e18
        return origin.addingTimeInterval(max(0, seconds))
    }
}
