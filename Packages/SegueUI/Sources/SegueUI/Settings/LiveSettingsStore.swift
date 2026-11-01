import Foundation
import Observation
import Services
import Shows
import Support

/// Settings > Live, persisted as one `LiveSettings` JSON value in UserDefaults. App-level
/// (not per song): the minimum lyric size, the two Shortcut names and the checklist rows the
/// user hid. Every change is saved at once.
@MainActor
@Observable
public final class LiveSettingsStore {
    /// The UserDefaults key holding the encoded settings.
    public static let defaultsKey = "live.settings"

    public var settings: LiveSettings {
        didSet {
            if settings != oldValue {
                save()
                updateGigModeTip()
                if !changingFromStage {
                    services.record(.featureUsed(.liveSettings, .settings))
                }
                if settings.singerView, !oldValue.singerView {
                    // `V`, the Live menu or Settings (P9-2 section 13).
                    services.record(.featureUsed(.singerView, .stage))
                }
            }
        }
    }

    /// Set while the stage changes a setting it owns (singer view, singer zoom), which is
    /// not a use of Settings > Live.
    @ObservationIgnored private var changingFromStage = false

    /// A change made on stage (P9-2: `V`, the singer zoom): saved like any other, but not
    /// counted as a Settings > Live use.
    public func updateFromStage(_ change: (inout LiveSettings) -> Void) {
        changingFromStage = true
        defer { changingFromStage = false }
        change(&settings)
    }

    /// Records analytics events (WS3 spec 5); the app hands over its hub.
    @ObservationIgnored public var services: ServicesHub = .disabled

    /// The UserDefaults key of `runsShortcutsForRehearsals`.
    public static let rehearsalShortcutsKey = "live.rehearsalShortcuts"

    /// Whether rehearsals run the start/end Shortcuts too (decisions.md, phase 2 build
    /// rulings: "Shortcuts optional" for rehearsals). Off by default.
    public var runsShortcutsForRehearsals: Bool {
        didSet {
            defaults.set(runsShortcutsForRehearsals, forKey: Self.rehearsalShortcutsKey)
        }
    }

    /// The UserDefaults key of `metronomeOn`.
    public static let metronomeKey = "live.metronome"

    /// Whether the stage metronome starts on (R108): the pre-show checklist's last choice,
    /// also set in Settings > Live. Off until first switched on.
    public var metronomeOn: Bool {
        didSet {
            defaults.set(metronomeOn, forKey: Self.metronomeKey)
        }
    }

    /// Also where the instrument profile lives by default (`LiveDependencies`).
    @ObservationIgnored let defaults: UserDefaults

    /// Reset All Settings (WS2b 4.6): the Live settings back to their defaults.
    func resetToDefaults() {
        settings = LiveSettings()
        runsShortcutsForRehearsals = false
        metronomeOn = false
    }

    public init(defaults: UserDefaults) {
        self.defaults = defaults
        settings = Self.load(from: defaults)
        runsShortcutsForRehearsals = defaults.bool(forKey: Self.rehearsalShortcutsKey)
        metronomeOn = defaults.bool(forKey: Self.metronomeKey)
        updateGigModeTip()
    }

    /// `GigModeTip` stops once a Gig Mode Shortcut is set up (A37).
    private func updateGigModeTip() {
        SegueTips.gigModeConfigured = settings.startShortcut != nil || settings.endShortcut != nil
    }

    /// The stored settings; defaults when none are stored or they cannot be read.
    static func load(from defaults: UserDefaults) -> LiveSettings {
        guard let data = defaults.data(forKey: defaultsKey),
              var settings = try? SegueJSON.decode(LiveSettings.self, from: data)
        else { return LiveSettings() }
        settings.minLyricSize = clampedMinLyricSize(settings.minLyricSize)
        return settings
    }

    private func save() {
        // Encoding a plain value type cannot fail in practice; a failure keeps the
        // in-memory value for this run.
        if let data = try? SegueJSON.encode(settings) {
            defaults.set(data, forKey: Self.defaultsKey)
        }
    }

    /// `size` kept within `LiveSettings.minLyricSizeRange`.
    public static func clampedMinLyricSize(_ size: Double) -> Double {
        let range = LiveSettings.minLyricSizeRange
        return min(max(size.rounded(), range.lowerBound), range.upperBound)
    }

    /// A Shortcut name with surrounding blanks removed; nil when blank.
    public static func shortcutName(_ name: String?) -> String? {
        guard let trimmed = name?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty
        else { return nil }
        return trimmed
    }
}
