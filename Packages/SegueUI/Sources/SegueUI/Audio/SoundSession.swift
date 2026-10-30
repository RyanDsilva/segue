import Diagrams
import Foundation
import MusicTheory
import Observation
import Playback
import Shows
import Support

/// The app's sound (P8-6 sections 8, 9): the gate, Settings > Audio, and the one
/// `SoundPlayer`, made lazily on the first sound and never while a gig runs. Previews,
/// the walk-up picker and Settings reach sound only through here.
@MainActor
@Observable
public final class SoundSession {
    public let gate: SoundGate
    public let settings: AudioSettingsStore
    @ObservationIgnored let host: AudioEngineHost
    @ObservationIgnored private let makeOutput: @MainActor () -> any SoundOutput
    @ObservationIgnored private let clock: any Clock
    /// The player; nil until the first sound, and dropped when a gig starts.
    public private(set) var player: SoundPlayer?

    init(
        host: AudioEngineHost,
        settings: AudioSettingsStore,
        clock: any Clock,
        makeOutput: @escaping @MainActor () -> any SoundOutput,
    ) {
        gate = SoundGate()
        self.host = host
        self.settings = settings
        self.clock = clock
        self.makeOutput = makeOutput
        apply(settings.settings)
        settings.onChange = { [weak self] new in self?.apply(new) }
    }

    /// Whether sound controls work now (they are disabled, never hidden, during a gig).
    public var isAvailable: Bool {
        !gate.gigRunning
    }

    /// The player, made on first use; nil while a gig runs.
    func makePlayer() -> SoundPlayer? {
        if let player {
            return player
        }
        let player = SoundPlayer(
            gate: gate,
            makeOutput: makeOutput,
            clock: clock,
            settings: settings,
        )
        self.player = player
        return player
    }

    /// Plays `phrase` once (a heard chord); nil-safe during a gig.
    @discardableResult
    func play(_ phrase: Phrase) -> Bool {
        guard let player = makePlayer() else { return false }
        player.play(phrase)
        return true
    }

    /// Settings > Audio "Test": a G chord over its bass (G1) in the chosen sound and style.
    func testSound() {
        guard let chord = ChordSymbol(parsing: "G") else { return }
        let bass = Voicing.bass(
            chord.root.pitchClass,
            placement: BassPlacement(tuning: .bassStandard4, home: 3),
        )
        play(PhraseBuilder.chord(
            chord,
            sound: settings.settings.chordSound,
            style: settings.settings.chordStyle,
            bass: bass,
        ))
    }

    /// Stops whatever is playing.
    func stop() {
        player?.stop()
    }

    /// A stage session is starting: editor and library sound stops first; for a gig the
    /// player and its output are released and the engine is blocked (torn down) before
    /// the stage window is presented. Called from `AppModel.live`'s `didSet`.
    func stageChanged(kind: ShowKind?) {
        let gig = kind == .gig
        if kind != nil {
            player?.stop()
        }
        if gig, !gate.gigRunning {
            gate.gigRunning = true
            player = nil
            host.block()
        } else if !gig, gate.gigRunning {
            gate.gigRunning = false
            host.unblock()
        }
    }

    /// The engine was torn down after an output change.
    func outputChanged() {
        player?.interrupted()
    }

    private func apply(_ settings: AudioSettings) {
        host.setSounds(chord: settings.chordSound, bass: settings.bassSound)
        host.setVolume(Float(settings.volume))
    }
}
