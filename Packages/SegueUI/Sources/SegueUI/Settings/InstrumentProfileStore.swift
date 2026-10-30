import Editing
import Foundation
import MusicTheory
import Observation
import Services
import Support

/// Settings > Instrument (P8-4 6.3, R152), persisted as one `InstrumentProfile` JSON value in
/// UserDefaults. App-level: never in a sidecar or a `.cho`. Every change is saved at once;
/// the editor and the stage observe it, so flipping the bass-note view anywhere re-renders
/// the open editor preview and the stage.
@MainActor
@Observable
public final class InstrumentProfileStore {
    /// The UserDefaults key holding the encoded profile.
    public static let defaultsKey = "instrument.profile"

    /// The profile. Writes keep its invariant (`InstrumentProfile.normalize()`).
    public private(set) var profile: InstrumentProfile

    /// Records analytics events (WS3 spec 5); the app hands over its hub.
    @ObservationIgnored public var services: ServicesHub = .disabled

    @ObservationIgnored private let defaults: UserDefaults

    public init(defaults: UserDefaults) {
        self.defaults = defaults
        profile = Self.load(from: defaults)
    }

    /// The render-time slice (`DisplayOptions.bass`).
    public var bassView: BassView? {
        profile.bassView
    }

    /// Changes the profile and saves it. "I play bass" turned on also turns the bass-note
    /// view on (`InstrumentProfile.setPlaysBass`).
    public func update(_ change: (inout InstrumentProfile) -> Void) {
        var next = profile
        change(&next)
        next.normalize()
        guard next != profile else { return }
        let old = profile
        profile = next
        save()
        if next.playsBass, !old.playsBass {
            services.record(.featureUsed(.bassProfile, .settings))
        }
    }

    /// Flips the bass-note view (the editor's Bass segment, `b` on stage), for anyone.
    public func toggleBassNotes(from context: FeatureContext) {
        update { $0.bassNotes.toggle() }
        services.record(.featureUsed(.bassNotes, context))
    }

    /// Walk-ups on charts (P8-4b section 8.7).
    public func setWalkUps(_ density: WalkUpDensity) {
        let wasOff = profile.walkUps == .off
        update { $0.walkUps = density }
        if wasOff, density != .off {
            services.record(.featureUsed(.walkUps, .settings))
        }
    }

    /// Reset All Settings: back to the defaults (bass-note view off, EADG).
    func resetToDefaults() {
        update { $0 = InstrumentProfile() }
    }

    /// The stored profile; defaults when none is stored or it cannot be read.
    static func load(from defaults: UserDefaults) -> InstrumentProfile {
        guard let data = defaults.data(forKey: defaultsKey),
              let profile = try? SegueJSON.decode(InstrumentProfile.self, from: data)
        else { return InstrumentProfile() }
        return profile
    }

    private func save() {
        // Encoding a plain value type cannot fail in practice; a failure keeps the
        // in-memory value for this run.
        if let data = try? SegueJSON.encode(profile) {
            defaults.set(data, forKey: Self.defaultsKey)
        }
    }
}
