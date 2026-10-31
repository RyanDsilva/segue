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
    @ObservationIgnored let devices: any AudioDeviceDirectory
    /// The player; nil until the first sound, and dropped when a gig starts.
    public private(set) var player: SoundPlayer?
    /// Every output device now (Settings > Audio "Play through"), refreshed on a change.
    public private(set) var outputs: [AudioOutputDevice] = []
    /// The system output now.
    public private(set) var systemOutput: AudioOutputDevice?
    /// The device UID the engine was last told to use (nil = the system output).
    @ObservationIgnored private(set) var routedUID: String?
    @ObservationIgnored private var routed = false

    init(
        host: AudioEngineHost,
        settings: AudioSettingsStore,
        clock: any Clock,
        devices: any AudioDeviceDirectory,
        makeOutput: @escaping @MainActor () -> any SoundOutput,
    ) {
        gate = SoundGate()
        self.host = host
        self.settings = settings
        self.clock = clock
        self.devices = devices
        self.makeOutput = makeOutput
        refreshDevices()
        apply(settings.settings)
        settings.onChange = { [weak self] new in self?.apply(new) }
        devices.onChange = { [weak self] in self?.refreshDevices() }
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
        route()
    }

    // MARK: Output (P8-6 section 11, P8-6c)

    /// Re-reads the devices (one came or went, or the system output changed) and re-routes.
    func refreshDevices() {
        let now = devices.outputs()
        if now != outputs {
            outputs = now
        }
        let system = devices.defaultOutput()
        if system != systemOutput {
            systemOutput = system
        }
        route()
    }

    /// The chosen device when it is connected; nil = the system output.
    var activeOutputUID: String? {
        guard let uid = settings.settings.outputUID, outputs.contains(where: { $0.uid == uid })
        else { return nil }
        return uid
    }

    /// The device sound goes to now: the chosen one when connected, else the system output.
    public var activeOutput: AudioOutputDevice? {
        activeOutputUID.flatMap { uid in outputs.first { $0.uid == uid } } ?? systemOutput
    }

    /// Whether the chosen device is gone (sound uses the system output until it returns).
    public var chosenOutputMissing: Bool {
        settings.settings.outputUID != nil && activeOutputUID == nil
    }

    /// The quiet note under the picker when sound goes to a USB interface (R162 Q10: the only
    /// USB hint; nothing for built-in, Bluetooth or HDMI outputs).
    public var usbNote: String? {
        guard let device = activeOutput, device.transport == .usb else { return nil }
        return "\(device.name) is a USB audio interface. Sound goes wherever it is connected, "
            + "such as an amp or PA."
    }

    /// One "Play through" row after the system output.
    public struct OutputChoice: Identifiable, Hashable {
        public var uid: String
        public var title: String
        public var id: String {
            uid
        }
    }

    /// The first "Play through" row: "System output (MacBook Pro Speakers)".
    public var systemOutputTitle: String {
        systemOutput.map { "System output (\($0.name))" } ?? "System output"
    }

    /// Every output device by name, plus the chosen one as "<name> (not connected)" while
    /// it is gone.
    public var outputChoices: [OutputChoice] {
        var choices = outputs
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
            .map { OutputChoice(uid: $0.uid, title: $0.name) }
        if chosenOutputMissing, let uid = settings.settings.outputUID {
            let name = settings.settings.outputName ?? "Chosen output"
            choices.append(OutputChoice(uid: uid, title: "\(name) (not connected)"))
        }
        return choices
    }

    /// "Play through" picked a device (nil = the system output); its name is kept for the
    /// not-connected row.
    func chooseOutput(_ uid: String?) {
        let name = uid.flatMap { uid in outputs.first { $0.uid == uid }?.name }
        settings.update { settings in
            guard settings.outputUID != uid else { return }
            settings.outputUID = uid
            settings.outputName = uid == nil ? nil : name ?? settings.outputName
        }
    }

    /// Tells the engine where sound goes when that changed. Anything playing stops and says
    /// so, and never resumes by itself (P8-6 8.1); the next sound uses the new device.
    private func route() {
        let uid = activeOutputUID
        guard !routed || uid != routedUID else { return }
        if routed {
            player?.interrupted()
        }
        routed = true
        routedUID = uid
        host.setOutputDevice(uid: uid)
    }
}
