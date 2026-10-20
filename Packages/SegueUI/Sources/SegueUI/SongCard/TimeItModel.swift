import Foundation
import Library
import Observation
import Services
import Support

/// "Time it" (R91, spec 16.0.1): a per-song Start/Stop timer that fills the song card's
/// Length field. One run at a time across the app, keyed to its song. Switching the
/// selected song keeps the run alive (the card shows it again on return); the run ends only
/// by Stop, Cancel (Esc) or the song being deleted. Nothing is written to disk here: Stop
/// hands the elapsed seconds to the field, which commits them as `{duration}`.
@MainActor
@Observable
public final class TimeItModel {
    /// The run in progress.
    public struct Run: Sendable, Hashable {
        public let songID: SongID
        public let startedAt: Date
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
        run?.songID == id
    }

    /// Whether another song than `id` is being timed (its card's Time it is unavailable).
    public func isTimingOther(than id: SongID) -> Bool {
        run.map { $0.songID != id } ?? false
    }

    /// Starts timing song `id`. Returns false, changing nothing, when another song is being
    /// timed (one run at a time); starting the song already being timed keeps its run.
    @discardableResult
    public func start(_ id: SongID) -> Bool {
        if let run {
            return run.songID == id
        }
        run = Run(songID: id, startedAt: clock.now())
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
        guard isTiming(id) else { return nil }
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
        guard isTiming(id) else { return }
        run = nil
    }

    /// Ends the run when its song was deleted. Hosts call this after a delete.
    public func songsDeleted(_ ids: some Sequence<SongID>) {
        guard let run, ids.contains(run.songID) else { return }
        self.run = nil
    }
}
