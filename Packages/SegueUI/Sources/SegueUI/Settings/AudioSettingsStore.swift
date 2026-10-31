import Foundation
import Observation
import Playback
import Services
import Support

/// Settings > Audio (P8-6 section 11): how heard chords and walk-ups sound. App-level.
/// Decoded leniently per field: a missing or unreadable field keeps its default.
public struct AudioSettings: Sendable, Hashable, Codable {
    /// Piano or clean guitar (R161; default piano, R162 Q8).
    public var chordSound: ChordSound
    /// Strummed or block (default strummed, R162 Q8).
    public var chordStyle: ChordStyle
    /// Finger or pick bass (default finger).
    public var bassSound: BassSound
    /// The output level, 0 ... 1 (default 70%).
    public var volume: Double
    /// "Play through": the chosen output device's UID; nil = the system output (default).
    public var outputUID: String?
    /// That device's name when it was chosen, for "<name> (not connected)" while it is gone.
    public var outputName: String?

    public init(
        chordSound: ChordSound = .piano,
        chordStyle: ChordStyle = .strum,
        bassSound: BassSound = .finger,
        volume: Double = 0.7,
        outputUID: String? = nil,
        outputName: String? = nil,
    ) {
        self.chordSound = chordSound
        self.chordStyle = chordStyle
        self.bassSound = bassSound
        self.volume = min(max(volume, 0), 1)
        self.outputUID = outputUID
        self.outputName = outputUID == nil ? nil : outputName
    }

    private enum CodingKeys: String, CodingKey {
        case chordSound
        case chordStyle
        case bassSound
        case volume
        case outputUID
        case outputName
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = Self()
        func field<T: Decodable>(_ key: CodingKeys, _ fallback: T) -> T {
            (try? container.decodeIfPresent(T.self, forKey: key)) ?? fallback
        }
        self.init(
            chordSound: field(.chordSound, defaults.chordSound),
            chordStyle: field(.chordStyle, defaults.chordStyle),
            bassSound: field(.bassSound, defaults.bassSound),
            volume: field(.volume, defaults.volume),
            outputUID: field(.outputUID, defaults.outputUID),
            outputName: field(.outputName, defaults.outputName),
        )
    }
}

/// Settings > Audio, persisted as one `AudioSettings` JSON value in UserDefaults. Every
/// change is saved at once and handed to the audio engine (`onChange`).
@MainActor
@Observable
public final class AudioSettingsStore {
    /// The UserDefaults key holding the encoded settings.
    public static let defaultsKey = "audio.settings"

    public private(set) var settings: AudioSettings

    /// Records analytics events (WS3 spec 5); the app hands over its hub.
    @ObservationIgnored public var services: ServicesHub = .disabled
    /// Called after every change (the app pushes sounds and volume to the engine).
    @ObservationIgnored var onChange: (@MainActor (AudioSettings) -> Void)?

    @ObservationIgnored private let defaults: UserDefaults

    public init(defaults: UserDefaults) {
        self.defaults = defaults
        settings = Self.load(from: defaults)
    }

    /// Changes the settings and saves them.
    public func update(_ change: (inout AudioSettings) -> Void) {
        var next = settings
        change(&next)
        next.volume = min(max(next.volume, 0), 1)
        guard next != settings else { return }
        let old = settings
        settings = next
        save()
        onChange?(next)
        if next.chordSound == .cleanGuitar, old.chordSound != .cleanGuitar {
            services.record(.featureUsed(.chordSoundGuitar, .settings))
        }
        // Only that a non-default output was chosen, never which (P8-6 section 14).
        if let uid = next.outputUID, uid != old.outputUID {
            services.record(.featureUsed(.audioOutput, .settings))
        }
    }

    /// Reset All Settings: back to the defaults.
    func resetToDefaults() {
        update { $0 = AudioSettings() }
    }

    static func load(from defaults: UserDefaults) -> AudioSettings {
        guard let data = defaults.data(forKey: defaultsKey),
              let settings = try? SegueJSON.decode(AudioSettings.self, from: data)
        else { return AudioSettings() }
        return settings
    }

    private func save() {
        // Encoding a plain value type cannot fail in practice; a failure keeps the
        // in-memory value for this run.
        if let data = try? SegueJSON.encode(settings) {
            defaults.set(data, forKey: Self.defaultsKey)
        }
    }
}
