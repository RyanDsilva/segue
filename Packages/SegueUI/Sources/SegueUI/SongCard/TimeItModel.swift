import Foundation
import Library
import Observation
import Services
import Setlists
import Support

/// "Time it" (R91, spec 16.0.1): a per-song Start/Stop timer that fills the song card's
/// Length field. One run at a time across the app, keyed to its song. Switching the
/// selected song keeps the run alive (the card shows it again on return); the run ends only
/// by Stop, Cancel (Esc) or the song being deleted. Nothing is written to disk here: Stop
/// hands the elapsed seconds to the field, which commits them as `{duration}`.
/// What a "Time it" run times: a song (its `{duration}`), or an arranged setlist slot (its
/// slot length, R122).
public enum TimeItTarget: Sendable, Hashable {
    case song(SongID)
    case slot(SetlistItemID)
}

@MainActor
@Observable
public final class TimeItModel {
    /// The run in progress.
    public struct Run: Sendable, Hashable {
        public let target: TimeItTarget
        public let startedAt: Date

        /// The song being timed; nil for a slot.
        public var songID: SongID? {
            if case let .song(id) = target {
                return id
            }
            return nil
        }
    }

    /// The one shared timer the app's song cards use, on a monotonic clock (a changed
    /// system clock never jumps the elapsed time).
    public static let shared = TimeItModel()

    /// The run in progress, if any.
    public private(set) var run: Run?

    @ObservationIgnored private let clock: any Support.Clock
    /// Records the Time it analytics row; the app hands over its hub when a library opens.
    @ObservationIgnored public var services: ServicesHub = .disabled

    /// `clock` is injectable so tests script the elapsed time.
    public init(clock: any Support.Clock = MonotonicClock()) {
        self.clock = clock
    }

    /// Whether song `id` is being timed.
    public func isTiming(_ id: SongID) -> Bool {
        isTiming(.song(id))
    }

    public func isTiming(_ target: TimeItTarget) -> Bool {
        run?.target == target
    }

    /// Whether another song than `id` is being timed (its card's Time it is unavailable).
    public func isTimingOther(than id: SongID) -> Bool {
        isTimingOther(than: .song(id))
    }

    public func isTimingOther(than target: TimeItTarget) -> Bool {
        run.map { $0.target != target } ?? false
    }

    /// Starts timing song `id`. Returns false, changing nothing, when another song is being
    /// timed (one run at a time); starting the song already being timed keeps its run.
    @discardableResult
    public func start(_ id: SongID) -> Bool {
        start(.song(id))
    }

    @discardableResult
    public func start(_ target: TimeItTarget) -> Bool {
        if let run {
            return run.target == target
        }
        run = Run(target: target, startedAt: clock.now())
        return true
    }

    /// Seconds since the run started (0 without a run).
    public func elapsed() -> TimeInterval {
        guard let run else { return 0 }
        return max(0, clock.now().timeIntervalSince(run.startedAt))
    }

    /// Ends song `id`'s run and returns its elapsed time rounded to the nearest second; nil
    /// (changing nothing) when that song is not being timed.
    public func stop(_ id: SongID) -> Int? {
        stop(.song(id))
    }

    public func stop(_ target: TimeItTarget) -> Int? {
        guard isTiming(target) else { return nil }
        let seconds = Int(elapsed().rounded())
        run = nil
        return seconds
    }

    /// Records that a run was stopped into a length (`featureUsed(.timeIt)`, R74).
    public func recordTimed(in context: FeatureContext) {
        services.record(.featureUsed(.timeIt, context))
    }

    /// Ends song `id`'s run without a result (Esc). Nothing happens for another song.
    public func cancel(_ id: SongID) {
        cancel(.song(id))
    }

    public func cancel(_ target: TimeItTarget) {
        guard isTiming(target) else { return }
        run = nil
    }

    /// Ends the run when its song was deleted. Hosts call this after a delete.
    public func songsDeleted(_ ids: some Sequence<SongID>) {
        guard let song = run?.songID, ids.contains(song) else { return }
        run = nil
    }
}
