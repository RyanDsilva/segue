import Foundation

/// Tap tempo (R111): the BPM of a run of taps. A gap longer than `resetAfter` starts a new
/// run; the tempo is the mean of the last `window` intervals, so it settles as you keep
/// tapping. Pure: timestamps come from the caller (a monotonic clock in the app).
struct TapTempo: Equatable {
    static let resetAfter: TimeInterval = 2
    static let window = 8

    private(set) var taps: [TimeInterval] = []

    /// Records a tap at `time` (seconds, monotonic) and returns the tempo once there are
    /// two taps in the run, rounded to a whole BPM and clamped to 20...400.
    mutating func tap(at time: TimeInterval) -> Int? {
        if let last = taps.last, time - last > Self.resetAfter || time < last {
            taps.removeAll()
        }
        taps.append(time)
        if taps.count > Self.window + 1 {
            taps.removeFirst(taps.count - Self.window - 1)
        }
        return bpm
    }

    /// The current run's tempo, nil before the second tap.
    var bpm: Int? {
        guard let first = taps.first, let last = taps.last, taps.count >= 2 else { return nil }
        let interval = (last - first) / Double(taps.count - 1)
        guard interval > 0 else { return nil }
        return min(max(Int((60 / interval).rounded()), 20), 400)
    }

    mutating func reset() {
        taps.removeAll()
    }
}
