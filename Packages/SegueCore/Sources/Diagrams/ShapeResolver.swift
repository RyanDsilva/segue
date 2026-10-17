// Owner: unit B (Diagrams). Frozen interface: docs/phases/1-interfaces.md.

import Foundation
import MusicTheory
import Support

/// User-saved guitar shapes (app support JSON), keyed by chord name and tuning.
public struct UserShapeLibrary: Sendable, Hashable, Codable {
    public struct Entry: Sendable, Hashable, Codable {
        /// Chord name, matched against a chord token's `original` text.
        public var name: String
        public var tuning: Tuning
        public var shape: GuitarShape

        public init(name: String, tuning: Tuning, shape: GuitarShape) {
            self.name = name
            self.tuning = tuning
            self.shape = shape
        }
    }

    public var entries: [Entry]

    public init(entries: [Entry] = []) {
        self.entries = entries
    }

    public static let empty = Self()

    /// The user's shape for `name` in `tuning` (strings compared, not the tuning's name).
    public func shape(named name: String, tuning: Tuning) -> GuitarShape? {
        entries.first { $0.name == name && $0.tuning.strings == tuning.strings }?.shape
    }

    /// Reads the library at `url`; a missing file is an empty library.
    public static func load(from url: URL, fileSystem: any FileSystem) throws -> Self {
        fatalError("unimplemented: unit B")
    }

    /// Writes the library to `url` atomically (versioned JSON via `SegueJSON`).
    public func save(to url: URL, fileSystem: any FileSystem) throws {
        fatalError("unimplemented: unit B")
    }
}

/// Shape lookup in the frozen order: song `{define}` -> user library -> curated ->
/// generator (phase 1 spec).
public struct ShapeResolver: Sendable {
    public let defines: [ChordDefinition]
    public let userLibrary: UserShapeLibrary
    public let tuning: Tuning

    /// - Parameter defines: the song's `{define}`s in source order (a later define of the
    ///   same name wins, as in ChordPro).
    public init(defines: [ChordDefinition], userLibrary: UserShapeLibrary, tuning: Tuning) {
        self.defines = defines
        self.userLibrary = userLibrary
        self.tuning = tuning
    }

    /// The guitar shape for `chord` (matched by `chord.original` for defines and the user
    /// library, by pitch content for curated and generated shapes). `nil` only if the
    /// generator finds nothing.
    public func guitarShape(for chord: ChartChord) -> ResolvedGuitarShape? {
        fatalError("unimplemented: unit B")
    }

    /// Piano voicings for `chords` in song order: a piano `{define ... keys}` of the same
    /// name wins, otherwise `PianoVoicingGenerator` with voice leading across the sequence.
    public func pianoVoicings(for chords: [ChartChord]) -> [PianoVoicing] {
        fatalError("unimplemented: unit B")
    }
}
