// Owner: unit B (Diagrams). Frozen interface: docs/phases/1-interfaces.md.

/// A custom chord shape from a ChordPro `{define}` directive:
/// `{define: Gadd9 base-fret 1 frets 3 2 0 2 0 3 fingers 2 1 0 3 0 4}` (guitar) or
/// `{define: Cmaj7 keys 0 4 7 11}` (ChordPro 6 piano define).
public struct ChordDefinition: Sendable, Hashable {
    public enum Shape: Sendable, Hashable {
        case guitar(GuitarShape)
        /// Piano keys as ChordPro writes them: semitones relative to the chord root.
        case piano(keys: [Int])
    }

    /// The chord name being defined, verbatim (`Gadd9`). Matched against chord tokens'
    /// `original` text.
    public var name: String
    public var shape: Shape

    public init(name: String, shape: Shape) {
        self.name = name
        self.shape = shape
    }

    /// Parses the value of a `{define}` directive (everything after `define:`). `nil` when
    /// malformed; the editor reports it as a malformed directive.
    public init?(directiveValue: String) {
        fatalError("unimplemented: unit B")
    }

    /// Canonical directive value (without `{define: ` and `}`), parseable by
    /// `init?(directiveValue:)`; fingers and barres are omitted when unspecified.
    public var directiveValue: String {
        fatalError("unimplemented: unit B")
    }
}
