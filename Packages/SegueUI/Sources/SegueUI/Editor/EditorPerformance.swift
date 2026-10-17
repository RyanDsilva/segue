import Foundation
import os
#if os(macOS)
    import QuartzCore
#endif

/// Keystroke processing times.
struct KeystrokeStats: Sendable {
    private(set) var samples: [TimeInterval] = []
    /// The longest main run loop turn since typing began.
    var busyMaximum: TimeInterval = 0

    var count: Int {
        samples.count
    }

    mutating func record(_ seconds: TimeInterval) {
        samples.append(seconds)
    }

    /// "n=40 p95=3.10ms max=9.80ms mean=1.20ms busy=40.00ms".
    var summary: String {
        guard !samples.isEmpty else { return "" }
        let sorted = samples.sorted()
        let p95 = sorted[min(Int(Double(sorted.count) * 0.95), sorted.count - 1)]
        let mean = samples.reduce(0, +) / Double(samples.count)
        return String(
            format: "n=%d p95=%.2fms max=%.2fms mean=%.2fms busy=%.2fms",
            samples.count,
            p95 * 1000,
            (sorted.last ?? 0) * 1000,
            mean * 1000,
            busyMaximum * 1000,
        )
    }
}

#if os(macOS)
    /// Measures how long the main run loop stays busy per turn (everything a keystroke
    /// costs: our handlers, SwiftUI updates, layout and drawing), while the editor is open.
    @MainActor
    final class MainThreadHitchMonitor {
        private var observer: CFRunLoopObserver?
        private var turnStart: CFTimeInterval = 0
        private(set) var maximum: CFTimeInterval = 0

        func start() {
            guard observer == nil else { return }
            let activities = CFRunLoopActivity.afterWaiting.rawValue
                | CFRunLoopActivity.beforeWaiting.rawValue
            observer = CFRunLoopObserverCreateWithHandler(
                nil,
                activities,
                true,
                0,
            ) { [weak self] _, activity in
                MainActor.assumeIsolated {
                    self?.observe(activity)
                }
            }
            CFRunLoopAddObserver(CFRunLoopGetMain(), observer, .commonModes)
        }

        func stop() {
            if let observer {
                CFRunLoopRemoveObserver(CFRunLoopGetMain(), observer, .commonModes)
            }
            observer = nil
        }

        func reset() {
            maximum = 0
        }

        private func observe(_ activity: CFRunLoopActivity) {
            let now = CACurrentMediaTime()
            if activity == .afterWaiting {
                turnStart = now
            } else if turnStart > 0 {
                let busy = now - turnStart
                maximum = max(maximum, busy)
                turnStart = 0
                if busy > 0.03 {
                    EditorPerformance.log
                        .notice(
                            "slow run loop turn \(busy * 1000, format: .fixed(precision: 1)) ms",
                        )
                }
            }
        }
    }
#endif

/// Editor performance diagnostics (`log stream --predicate 'category == "editor-perf"'`).
enum EditorPerformance {
    static let log = Logger(subsystem: "dev.ryandsilva.segue", category: "editor-perf")
}
