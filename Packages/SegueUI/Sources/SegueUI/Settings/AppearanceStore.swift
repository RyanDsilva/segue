#if os(macOS)
    import AppKit
    import Observation

    /// Settings > Appearance (R36, A42): Match System (default), Light or Dark for the main
    /// window, Settings and every other non-stage window. The stage is always dark.
    public enum AppearanceMode: String, CaseIterable, Identifiable, Sendable {
        case system
        case light
        case dark

        public var id: String {
            rawValue
        }

        public var title: String {
            switch self {
            case .system: "Match System"
            case .light: "Light"
            case .dark: "Dark"
            }
        }

        /// What `NSApp.appearance` becomes: nil follows the system.
        var appearance: NSAppearance? {
            switch self {
            case .system: nil
            case .light: NSAppearance(named: .aqua)
            case .dark: NSAppearance(named: .darkAqua)
            }
        }
    }

    /// `appearance.mode` (absent = Match System). The only writer of the key; applying it sets
    /// `NSApp.appearance`, so it takes effect at once in every window that does not force its
    /// own (the stage window forces dark).
    @MainActor
    @Observable
    public final class AppearanceStore {
        static let key = "appearance.mode"

        @ObservationIgnored private let defaults: UserDefaults
        /// A launch-time override (`-SegueAppearance`, screenshots) that wins over the stored
        /// mode for this launch without changing it, until the user picks a mode.
        @ObservationIgnored private var forced: AppearanceMode?

        public var mode: AppearanceMode {
            didSet {
                guard mode != oldValue else { return }
                forced = nil
                if mode == .system {
                    defaults.removeObject(forKey: Self.key)
                } else {
                    defaults.set(mode.rawValue, forKey: Self.key)
                }
                apply()
            }
        }

        public init(defaults: UserDefaults, forced: AppearanceMode? = nil) {
            self.defaults = defaults
            self.forced = forced
            mode = defaults.string(forKey: Self.key).flatMap(AppearanceMode.init) ?? .system
        }

        /// Sets `NSApp.appearance` for the effective mode.
        public func apply() {
            NSApplication.shared.appearance = (forced ?? mode).appearance
        }

        /// Reset All Settings: back to Match System.
        func reset() {
            mode = .system
        }
    }
#endif
