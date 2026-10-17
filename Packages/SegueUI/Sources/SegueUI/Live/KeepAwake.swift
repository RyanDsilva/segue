import Foundation

/// Holds a `ProcessInfo` activity with idle display sleep disabled until `end()` (or
/// deinit). Live mode holds one for the whole show (phase 2 spec, "Keep awake").
final class DisplaySleepAssertion {
    private var token: (any NSObjectProtocol)?

    init(reason: String) {
        token = ProcessInfo.processInfo.beginActivity(
            options: [.idleDisplaySleepDisabled, .userInitiated],
            reason: reason,
        )
    }

    /// Whether the assertion is still held.
    var isHeld: Bool {
        token != nil
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
