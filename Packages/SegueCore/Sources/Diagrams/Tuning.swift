// Owner: unit B (Diagrams). Frozen interface: docs/phases/1-interfaces.md.

/// A stringed-instrument tuning.
public struct Tuning: Sendable, Hashable, Codable {
    /// Display name ("Standard", "Drop D", "DADGAD", "Open G", or a user label).
    public var name: String
    /// Open-string pitches as MIDI note numbers, lowest string first (Standard: E2 A2 D3 G3
    /// B3 E4 = 40 45 50 55 59 64). The count is the number of strings.
    public var strings: [Int]

    public init(name: String, strings: [Int]) {
        self.name = name
        self.strings = strings
    }

    public static let standard = Self(name: "Standard", strings: [40, 45, 50, 55, 59, 64])
    public static let dropD = Self(name: "Drop D", strings: [38, 45, 50, 55, 59, 64])
    public static let dadgad = Self(name: "DADGAD", strings: [38, 45, 50, 55, 57, 62])
    public static let openG = Self(name: "Open G", strings: [38, 43, 50, 55, 59, 62])

    /// Built-in tunings, in menu order.
    public static let presets: [Self] = [.standard, .dropD, .dadgad, .openG]

    /// Parses a `{meta: tuning ...}` value: a preset name (case-insensitive, e.g. "DADGAD",
    /// "drop d") or scientific pitches low to high ("D2 A2 D3 G3 A3 D4"). `nil` if neither.
    public init?(metaValue: String) {
        fatalError("unimplemented: unit B")
    }

    /// The value written to `{meta: tuning ...}`: the preset name for a preset, otherwise
    /// scientific pitches low to high. `Tuning(metaValue: t.metaValue) == t` for presets
    /// and for named-by-pitches tunings.
    public var metaValue: String {
        fatalError("unimplemented: unit B")
    }
}
