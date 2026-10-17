import Foundation
import Library
import Observation

/// One performance of a setlist: a snapshot of its songs taken when "Perform" was pressed,
/// the current position, and the idle-display-sleep assertion held while the stage is up.
@MainActor
@Observable
public final class LiveViewModel {
    public let setlistName: String
    public let songs: [SongRecord]
    public private(set) var index = 0

    @ObservationIgnored private var sleepAssertion: DisplaySleepAssertion?

    public init(setlistName: String, songs: [SongRecord]) {
        self.setlistName = setlistName
        self.songs = songs
    }

    public var current: SongRecord? {
        songs.indices.contains(index) ? songs[index] : nil
    }

    public var upNext: SongRecord? {
        songs.indices.contains(index + 1) ? songs[index + 1] : nil
    }

    public var hasNext: Bool {
        index + 1 < songs.count
    }

    public var hasPrevious: Bool {
        index > 0
    }

    /// "2 of 5".
    public var positionText: String {
        songs.isEmpty ? "" : "\(index + 1) of \(songs.count)"
    }

    public func next() {
        if hasNext {
            index += 1
        }
    }

    public func previous() {
        if hasPrevious {
            index -= 1
        }
    }

    /// Call when the stage appears: keeps the display awake.
    public func stageDidAppear() {
        if sleepAssertion == nil {
            sleepAssertion = DisplaySleepAssertion(reason: "Performing \(setlistName)")
        }
    }

    /// Call when the stage goes away: lets the display sleep again.
    public func stageDidDisappear() {
        sleepAssertion?.end()
        sleepAssertion = nil
    }
}

/// Holds `ProcessInfo` activity with idle display sleep disabled until `end()` (or deinit).
final class DisplaySleepAssertion {
    private var token: (any NSObjectProtocol)?

    init(reason: String) {
        token = ProcessInfo.processInfo.beginActivity(
            options: [.idleDisplaySleepDisabled, .userInitiated],
            reason: reason,
        )
    }

    func end() {
        if let token {
            ProcessInfo.processInfo.endActivity(token)
        }
        token = nil
    }

    deinit {
        end()
    }
}
