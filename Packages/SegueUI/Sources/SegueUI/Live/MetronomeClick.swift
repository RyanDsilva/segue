#if os(macOS)
    import Foundation
    import Shows
    import Support

    /// Where rehearsal clicks go: the audio engine in the app, a recorder in tests. Only a
    /// `RehearsalClick` ever holds one, and a gig never makes a `RehearsalClick` (R90).
    public protocol MetronomeClickOutput: AnyObject, Sendable {
        /// Plays one click `delay` seconds from now (0 for "as soon as possible").
        func schedule(_ accent: MetronomeAccent, beat: Int, in delay: TimeInterval)
        /// Silences every click already scheduled, at once.
        func stop()
    }

    /// The rehearsal click (R90, R108): schedules a click per beat of the current track a
    /// little ahead of time, so the audio hardware plays it on the beat's host time while
    /// the main thread only tops up the queue. It exists only in a rehearsal: `init` fails
    /// for a gig, so no state of a gig can make a sound. The output (the audio engine) is
    /// made on the first click, never before.
    @MainActor
    final class RehearsalClick {
        /// How far ahead clicks are handed to the output.
        static let lookahead: TimeInterval = 0.3
        /// How often the queue is topped up (well inside `lookahead`).
        static let pumpInterval: Duration = .milliseconds(100)

        private let clock: any Clock
        private let makeOutput: @MainActor () -> any MetronomeClickOutput
        /// Made on the first click.
        private(set) var output: (any MetronomeClickOutput)?
        private var track: MetronomeTrack?
        /// The last beat index handed to the output for `track`.
        private var scheduledThrough: Int?
        private var pumpTask: Task<Void, Never>?

        /// Nil unless `kind` is a rehearsal.
        init?(
            kind: ShowKind,
            clock: any Clock,
            makeOutput: @escaping @MainActor () -> any MetronomeClickOutput,
        ) {
            guard kind == .rehearsal else { return nil }
            self.clock = clock
            self.makeOutput = makeOutput
        }

        var isRunning: Bool {
            track != nil
        }

        /// Clicks along `track` from its next beat (nil stops).
        func play(_ track: MetronomeTrack?) {
            guard track != self.track else { return }
            stop()
            guard let track else { return }
            self.track = track
            pump()
            pumpTask = Task { [weak self] in
                while !Task.isCancelled {
                    try? await Task.sleep(for: Self.pumpInterval)
                    self?.pump()
                }
            }
        }

        /// Stops at once: pending clicks are dropped (pause, song change, break, End).
        func stop() {
            pumpTask?.cancel()
            pumpTask = nil
            track = nil
            scheduledThrough = nil
            output?.stop()
        }

        /// Hands the output every beat due within `lookahead` that it does not have yet.
        func pump() {
            guard let track else { return }
            let now = clock.now()
            var index = max(
                track.nextBeat(atOrAfter: now).beat.index,
                (scheduledThrough ?? -1) + 1,
            )
            while track.time(ofBeat: index).timeIntervalSince(now) <= Self.lookahead {
                let output = output ?? makeOutput()
                self.output = output
                output.schedule(
                    track.beat(index).accent,
                    beat: index,
                    in: max(0, track.time(ofBeat: index).timeIntervalSince(now)),
                )
                scheduledThrough = index
                index += 1
            }
        }
    }

    /// The rehearsal click on the shared audio engine (P8-6 section 8.2): a short
    /// synthesized tick per beat (higher on beat 1), scheduled on the audio clock so it lands
    /// on the beat whatever the main thread is doing. The engine starts on the first click,
    /// follows the system's output device and is rebuilt after a device change.
    public final class AudioEngineClickOutput: MetronomeClickOutput {
        private let host: AudioEngineHost

        public init(host: AudioEngineHost = .shared) {
            self.host = host
        }

        public func schedule(_ accent: MetronomeAccent, beat _: Int, in delay: TimeInterval) {
            host.scheduleClick(accent, in: delay)
        }

        public func stop() {
            host.stopClicks()
        }
    }
#endif
