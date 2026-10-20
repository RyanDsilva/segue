import Foundation

/// Settings > General "Changeover between songs" (R86): the app-wide default a setlist
/// uses when it has no changeover of its own (`Setlist.changeoverSeconds == nil`). Stored
/// in UserDefaults as whole seconds; read with `@AppStorage(ChangeoverSetting.defaultsKey)`
/// so every total updates as it changes. Default 0 s.
enum ChangeoverSetting {
    /// The UserDefaults key holding the default changeover in seconds.
    static let defaultsKey = "setlists.defaultChangeoverSeconds"

    /// The values the Settings stepper offers, in seconds.
    static let range = 0 ... 600
    static let step = 5

    /// The stored default (0 when none is stored), clamped to `range`.
    static func stored(in defaults: UserDefaults = .standard) -> Int {
        clamped(defaults.integer(forKey: defaultsKey))
    }

    static func clamped(_ seconds: Int) -> Int {
        min(max(seconds, range.lowerBound), range.upperBound)
    }

    /// Reset All Settings: back to 0 s.
    static func reset(in defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: defaultsKey)
    }

    /// The changeover a setlist's totals include: its own, else the app-wide default.
    static func effective(for setlistValue: Int?, default fallback: Int) -> TimeInterval {
        TimeInterval(clamped(setlistValue ?? fallback))
    }
}
