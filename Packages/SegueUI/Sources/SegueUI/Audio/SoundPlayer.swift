import Foundation
import Observation
import Playback
import Support

/// The only holder of a `SoundOutput` (P8-6 section 8.4). It plays one phrase at a time:
/// a phrase is walked by a `PhraseCursor` and handed to the output a little ahead of time
/// by a pump on the injected clock (the `RehearsalClick` shape), so notes land on the audio
/// clock whatever the main thread is doing. It cannot exist while a gig runs: `init`
/// fails, and the app drops it and blocks the engine when a gig starts (section 9).
@MainActor
@Observable
public final class SoundPlayer {
    /// How far ahead events are handed to the output.
    static let lookahead: TimeInterval = 0.3
    /// How often the queue is topped up (well inside `lookahead`).
    static let pumpInterval: Duration = .milliseconds(100)

    @ObservationIgnored private let gate: SoundGate
    @ObservationIgnored private let makeOutput: @MainActor () -> any SoundOutput
    @ObservationIgnored private let clock: any Clock
    @ObservationIgnored private let settings: AudioSettingsStore
    /// Made on the first sound, never before.
    @ObservationIgnored private(set) var output: (any SoundOutput)?
    @ObservationIgnored private var cursor: PhraseCursor?
    @ObservationIgnored private var pumpTask: Task<Void, Never>?

    /// Whether a phrase is sounding (or about to).
    public private(set) var isPlaying = false
    /// Whether the phrase repeats.
    public private(set) var isLooping = false
    /// Which pass of a looping phrase is sounding (1 for the first).
    public private(set) var pass = 0
    /// A short line when sound stopped by itself ("Stopped: the audio output changed").
    public internal(set) var status: String?

    /// Nil while a gig runs.
    init?(
        gate: SoundGate,
        makeOutput: @escaping @MainActor () -> any SoundOutput,
        clock: any Clock,
        settings: AudioSettingsStore,
    ) {
        guard !gate.gigRunning else { return nil }
        self.gate = gate
        self.makeOutput = makeOutput
        self.clock = clock
        self.settings = settings
    }

    /// Plays `phrase` once, stopping whatever was playing.
    public func play(_ phrase: Phrase) {
        start(phrase, loop: false)
    }

    /// Plays `phrase` over and over, stopping whatever was playing.
    public func loop(_ phrase: Phrase) {
        start(phrase, loop: true)
    }

    /// While looping, `phrase` takes over at the next pass (A/B); otherwise it plays now.
    public func swapAtNextWrap(_ phrase: Phrase) {
        guard isPlaying, isLooping, cursor != nil else {
            play(phrase)
            return
        }
        cursor?.swap(to: phrase)
    }

    /// Stops at once: pending notes dropped, sounding notes released.
    public func stop() {
        let wasPlaying = isPlaying
        pumpTask?.cancel()
        pumpTask = nil
        cursor = nil
        isPlaying = false
        isLooping = false
        pass = 0
        if wasPlaying {
            output?.stopAll()
        }
    }

    /// Seconds into the pass sounding now (for a playhead); 0 when stopped.
    public var position: TimeInterval {
        cursor?.position(at: clock.now()) ?? 0
    }

    /// The engine stopped by itself (the output device changed): stop and say so. A loop
    /// never resumes by itself.
    func interrupted() {
        guard isPlaying else { return }
        stop()
        status = "Stopped: the audio output changed"
    }

    private func start(_ phrase: Phrase, loop: Bool) {
        guard !gate.gigRunning else { return }
        stop()
        status = nil
        let output = output ?? makeOutput()
        if self.output == nil {
            self.output = output
            output.prepare(chord: settings.settings.chordSound, bass: settings.settings.bassSound)
        }
        cursor = PhraseCursor(phrase: phrase, start: clock.now(), loop: loop)
        isPlaying = true
        isLooping = loop
        pass = 1
        pump()
        pumpTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: Self.pumpInterval)
                self?.pump()
            }
        }
    }

    /// Hands the output every event due within `lookahead` it does not have yet.
    func pump() {
        guard var cursor, let output, !gate.gigRunning else {
            if gate.gigRunning {
                stop()
            }
            return
        }
        let now = clock.now()
        let due = cursor.due(at: now, lookahead: Self.lookahead)
        if !due.isEmpty {
            output.schedule(due.map { event, delay in
                var timed = event
                timed.onset = delay
                return timed
            }, in: 0)
        }
        if cursor.pass != pass {
            pass = cursor.pass
        }
        self.cursor = cursor
        if cursor.isFinished(at: now) {
            pumpTask?.cancel()
            pumpTask = nil
            self.cursor = nil
            isPlaying = false
            isLooping = false
            pass = 0
        }
    }
}
