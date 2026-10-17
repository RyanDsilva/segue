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
        guard fileSystem.fileExists(at: url) else { return .empty }
        let data = try fileSystem.readData(at: url)
        switch try migrator.migrate(data) {
        case let .current(data), let .migrated(data, _):
            return try SegueJSON.decode(StoredLibrary.self, from: data).library
        case let .newer(found):
            throw UserShapeLibraryError.newerSchema(found: found, supported: currentSchemaVersion)
        }
    }

    /// Writes the library to `url` atomically (versioned JSON via `SegueJSON`).
    public func save(to url: URL, fileSystem: any FileSystem) throws {
        let directory = url.deletingLastPathComponent()
        if !fileSystem.directoryExists(at: directory) {
            try fileSystem.createDirectory(at: directory)
        }
        let stored = StoredLibrary(schemaVersion: Self.currentSchemaVersion, entries: entries)
        try fileSystem.writeAtomically(SegueJSON.encode(stored), to: url)
    }

    /// Adds `shape` for `name` in `tuning`, replacing any existing entry for both.
    public mutating func set(_ shape: GuitarShape, named name: String, tuning: Tuning) {
        entries.removeAll { $0.name == name && $0.tuning.strings == tuning.strings }
        entries.append(Entry(name: name, tuning: tuning, shape: shape))
    }

    /// The file name inside the app's Application Support folder.
    public static let fileName = "shape-library.json"
    /// The on-disk schema version this build writes.
    public static let currentSchemaVersion = 1
    private static let migrator = SchemaMigrator(currentVersion: currentSchemaVersion, steps: [:])

    /// The on-disk form: `{ "entries": [...], "schemaVersion": 1 }`.
    private struct StoredLibrary: Codable {
        var schemaVersion: Int
        var entries: [Entry]

        var library: UserShapeLibrary {
            UserShapeLibrary(entries: entries)
        }
    }
}

/// Errors reading the user shape library.
public enum UserShapeLibraryError: Error, Equatable, CustomStringConvertible {
    /// The file was written by a newer Segue; it is left untouched.
    case newerSchema(found: Int, supported: Int)

    public var description: String {
        switch self {
        case let .newerSchema(found, supported):
            "the shape library uses schema \(found); this version reads up to \(supported)"
        }
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
        let name = Self.key(chord.original)
        if let define = defines.last(where: { definition in
            guard Self.key(definition.name) == name,
                  case let .guitar(shape) = definition.shape
            else { return false }
            return shape.frets.count == tuning.strings.count
        }), case let .guitar(shape) = define.shape {
            return ResolvedGuitarShape(shape: shape, source: .songDefine)
        }
        if let shape = userLibrary.shape(named: name, tuning: tuning) {
            return ResolvedGuitarShape(shape: shape, source: .userLibrary)
        }
        if let shape = CuratedShapes.shape(for: chord.tones, tuning: tuning) {
            return ResolvedGuitarShape(shape: shape, source: .curated)
        }
        return GuitarShapeGenerator.shapes(for: chord.tones, tuning: tuning, limit: 1).first
            .map { ResolvedGuitarShape(shape: $0, source: .generated) }
    }

    /// Piano voicings for `chords` in song order: a piano `{define ... keys}` of the same
    /// name wins, otherwise `PianoVoicingGenerator` with voice leading across the sequence.
    public func pianoVoicings(for chords: [ChartChord]) -> [PianoVoicing] {
        var previous: PianoVoicing?
        return chords.map { chord in
            let tones = chord.tones
            let voicing: PianoVoicing = if let keys = pianoKeys(named: chord.original) {
                Self.voicing(keys: keys, tones: tones, after: previous)
            } else {
                PianoVoicingGenerator.voicing(for: tones, after: previous)
            }
            previous = voicing
            return voicing
        }
    }

    /// The keys of the last piano `{define}` named `name`.
    private func pianoKeys(named name: String) -> [Int]? {
        let key = Self.key(name)
        for definition in defines.reversed() where Self.key(definition.name) == key {
            if case let .piano(keys) = definition.shape {
                return keys
            }
        }
        return nil
    }

    /// A `{define ... keys}` voicing: the keys are semitones above the root, placed at the
    /// octave (within C3 ... C5 where possible) that sits nearest the previous voicing, or
    /// nearest middle C. The bass is the chord's lowest note, as for generated voicings.
    static func voicing(keys: [Int], tones: ChordTones, after previous: PianoVoicing?)
        -> PianoVoicing
    {
        let offsets = Array(Set(keys)).sorted()
        let target = previous.flatMap { voicing -> Int? in
            guard let low = voicing.notes.first, let high = voicing.notes.last else { return nil }
            return (low + high) / 2
        } ?? PianoVoicingGenerator.preferredCentre
        let range = PianoVoicingGenerator.rightHandRange
        let options = (2 ... 6)
            .map { octave in offsets.map { 12 * octave + tones.root.rawValue + $0 } }
        let fitting = options.filter { notes in
            guard let low = notes.first, let high = notes.last else { return false }
            return range.contains(low) && range.contains(high)
        }
        let notes = (fitting.isEmpty ? options : fitting).min { lhs, rhs in
            abs(centre(lhs) - target) < abs(centre(rhs) - target)
        } ?? []
        return PianoVoicing(
            notes: notes,
            bass: PianoVoicingGenerator.bassNote(
                tones.lowest,
                below: notes.first ?? PianoVoicingGenerator.preferredCentre,
            ),
            root: tones.root,
        )
    }

    private static func centre(_ notes: [Int]) -> Int {
        ((notes.first ?? 0) + (notes.last ?? 0)) / 2
    }

    /// Chord names compare without surrounding whitespace (tokens keep it in `original`).
    private static func key(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespaces)
    }
}
