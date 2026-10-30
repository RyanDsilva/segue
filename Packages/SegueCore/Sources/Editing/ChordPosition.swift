// P8-4b (docs/phases/8-workstreams/P8-4-bass.md sections 8.5, 8.11). Where a chord sits in a
// song, as beat estimates, walk-up picks and play-along timing key it.

/// A `.chord`-kind chord of a song: its render section and its 0-based ordinal among that
/// section's `.chord`-kind chords in written order.
public struct ChordPosition: Sendable, Hashable, Comparable, CustomStringConvertible {
    public var section: Int
    public var chord: Int

    public init(section: Int, chord: Int) {
        self.section = section
        self.chord = chord
    }

    public static func < (lhs: Self, rhs: Self) -> Bool {
        (lhs.section, lhs.chord) < (rhs.section, rhs.chord)
    }

    public var description: String {
        "\(section).\(chord)"
    }
}
