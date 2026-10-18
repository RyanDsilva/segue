import Foundation
import Support
import Synchronization

/// Keeps analytics inside the event budget (spec 3.4): *daily* events go out at most once
/// per local calendar day per key, *once* events once per install. The state stays on this
/// Mac (UserDefaults) and is cleared when analytics consent is revoked.
public final class AnalyticsThrottle: Sendable {
    /// The UserDefaults key holding the throttle state.
    public static let defaultsKey = "analytics.throttle"

    private struct State: Codable, Equatable {
        /// The local day `daily` belongs to; a new day starts empty.
        var day: CalendarDay?
        var daily: Set<String> = []
        var once: Set<String> = []
    }

    /// The defaults suite (nil = standard). Held by name because `UserDefaults` is not
    /// `Sendable`; instances for one suite share storage.
    private let suiteName: String?
    private let clock: any Clock
    private let timeZone: @Sendable () -> TimeZone
    private let state: Mutex<State>

    /// - Parameters:
    ///   - suiteName: the UserDefaults suite the state persists in (nil = standard; test
    ///     runs pass the app's test suite, package tests a throwaway one).
    ///   - timeZone: the zone that defines "today" (default: the Mac's current zone).
    public init(
        suiteName: String?,
        clock: any Clock,
        timeZone: @escaping @Sendable () -> TimeZone = { .current },
    ) {
        self.suiteName = suiteName
        let defaults = Self.defaults(suiteName)
        self.clock = clock
        self.timeZone = timeZone
        let stored = defaults.data(forKey: Self.defaultsKey)
            .flatMap { try? JSONDecoder().decode(State.self, from: $0) }
        state = Mutex(stored ?? State())
    }

    /// Whether `event` may be sent now. Returns true at most once per window and records it,
    /// so call it only when the signal will actually be sent.
    public func admit(_ event: AnalyticsEvent) -> Bool {
        let today = CalendarDay(clock.now(), timeZone: timeZone())
        return state.withLock { state in
            let before = state
            if state.day != today {
                state.day = today
                state.daily = []
            }
            let admitted: Bool = switch event.throttle {
            case .perOccurrence: true
            case let .daily(key): state.daily.insert(key).inserted
            case let .once(key): state.once.insert(key).inserted
            }
            // Persisted under the lock so two callers can never write stale state last.
            if state != before {
                persist(state)
            }
            return admitted
        }
    }

    /// Forgets everything (analytics consent revoked).
    public func reset() {
        state.withLock { state in
            state = State()
            defaults.removeObject(forKey: Self.defaultsKey)
        }
    }

    private var defaults: UserDefaults {
        Self.defaults(suiteName)
    }

    private static func defaults(_ suiteName: String?) -> UserDefaults {
        suiteName.flatMap(UserDefaults.init(suiteName:)) ?? .standard
    }

    private func persist(_ snapshot: State) {
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        defaults.set(data, forKey: Self.defaultsKey)
    }
}
