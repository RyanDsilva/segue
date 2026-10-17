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
