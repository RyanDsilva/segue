import Foundation
import Playback
@testable import SegueUI
import Services
import Support
import Synchronization

extension SoundBank {
    /// The bank in the source tree: the app ships it from there (Project.swift), and the
    /// package's tests, which have no app bundle, read it in place.
    static let sourceURL: URL? = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appending(path: "Sources/SegueUI/Audio/Sounds/SegueSounds.sf2")
}

/// A recording `SoundOutput` (P8-6 section 15.2): what was scheduled, at what time on the
/// test clock, and every `stopAll`.
final class RecordingSoundOutput: SoundOutput, @unchecked Sendable {
    struct Played: Equatable {
        var event: NoteEvent
        /// Seconds since the reference date on the test clock (0 without a clock).
        var at: TimeInterval
    }

    enum Call: Equatable {
        case prepare(ChordSound, BassSound)
        case play(Played)
        case stopAll
    }

    private let clock: (any Clock)?
    private let state = Mutex<[Call]>([])
    /// Runs on each `stopAll` (to observe what else was true at that moment).
    let onStop: (@Sendable () -> Void)?

    init(clock: (any Clock)?, onStop: (@Sendable () -> Void)? = nil) {
        self.clock = clock
        self.onStop = onStop
    }

    var calls: [Call] {
        state.withLock { $0 }
    }

    /// Every event scheduled, in order.
    var played: [Played] {
        calls.compactMap {
            if case let .play(played) = $0 {
                played
            } else {
                nil
            }
        }
    }

    var stops: Int {
        calls.count { $0 == .stopAll }
    }

    func prepare(chord: ChordSound, bass: BassSound) {
        state.withLock { $0.append(.prepare(chord, bass)) }
    }

    func schedule(_ events: [NoteEvent], in delay: TimeInterval) {
        let now = clock?.now().timeIntervalSinceReferenceDate ?? 0
        state.withLock { calls in
            calls += events.map { event in
                .play(Played(event: event, at: now + delay + event.onset))
            }
        }
    }

    func stopAll() {
        state.withLock { $0.append(.stopAll) }
        onStop?()
    }
}

/// Every sound output the app made.
@MainActor
final class SoundOutputs {
    /// How many outputs the app made.
    private(set) var made = 0
    /// The latest, held weakly so a test can see the app release it.
    private(set) weak var last: RecordingSoundOutput?
    var onStop: (@Sendable () -> Void)?

    func make(_ clock: any Clock) -> RecordingSoundOutput {
        let output = RecordingSoundOutput(clock: clock, onStop: onStop)
        made += 1
        last = output
        return output
    }
}

/// A sound session for a view model under test: a never-built engine and recorded outputs.
@MainActor
struct SoundRig {
    let session: SoundSession
    let outputs = SoundOutputs()

    let devices: FixedAudioDeviceDirectory

    init(
        _ env: TestEnvironment,
        services: ServicesHub = .disabled,
        devices: FixedAudioDeviceDirectory = FixedAudioDeviceDirectory(),
    ) {
        let outputs = outputs
        let clock = env.clock
        let settings = AudioSettingsStore(defaults: env.defaults)
        settings.services = services
        self.devices = devices
        session = SoundSession(
            host: AudioEngineHost(bank: nil, systemBank: nil),
            settings: settings,
            clock: clock,
            devices: devices,
            makeOutput: { outputs.make(clock) },
        )
    }

    /// The notes of `voice` the latest output was handed, in order.
    func notes(_ voice: Voice) -> [Int] {
        outputs.last?.played.filter { $0.event.voice == voice }.map { Int($0.event.note) } ?? []
    }
}
