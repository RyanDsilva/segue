import Diagrams
import Editing
import Foundation
import MusicTheory

/// `songs/<slug>.segue.json`: the only home of app metadata. The `.cho` stays clean ChordPro.
///
/// Versioning: older `schemaVersion`s are migrated forward on read and written back at
/// `currentSchemaVersion` on next save; a newer one opens the song read-only
/// (`ReadOnlyReason.newerSchema`) and the file is never rewritten.
/// Implementers may add fields; bump `currentSchemaVersion` and add a migration when the
/// on-disk shape changes.
public struct Sidecar: Sendable, Equatable, Codable {
    /// The schema version this build reads and writes.
    ///
    /// History: 0 = pre-versioned; 1 = phase 0 (`displayPrefs` an opaque object, `{}`);
    /// 2 = phase 1 (`displayPrefs` holds the view toggles: transpose, capo mode, Nashville,
    /// diagrams, instrument, tuning).
    public static let currentSchemaVersion = 2

    public var schemaVersion: Int
    public var id: SongID
    public var tags: [String]
    public var proficiency: Proficiency?
    public var notes: String?
    public var displayPrefs: DisplayPrefs
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        schemaVersion: Int = Self.currentSchemaVersion,
        id: SongID,
        tags: [String] = [],
        proficiency: Proficiency? = nil,
        notes: String? = nil,
        displayPrefs: DisplayPrefs = DisplayPrefs(),
        createdAt: Date,
        updatedAt: Date,
    ) {
        self.schemaVersion = schemaVersion
        self.id = id
        self.tags = tags
        self.proficiency = proficiency
        self.notes = notes
        self.displayPrefs = displayPrefs
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

/// How well the user knows a song (decisions.md: Learning / Ready / Pro).
public enum Proficiency: String, Sendable, Equatable, Codable, CaseIterable {
    case learning
    case ready
    case pro
}

/// Per-song display preferences, persisted in the sidecar (phase 1: the view toggles; phase
/// 2 adds stage fields). Owner: unit C. Frozen interface: docs/phases/1-interfaces.md.
///
/// Decoding is per field and lenient: a missing or unreadable field takes its default, so
/// older sidecars (`"displayPrefs": {}`) and partially foreign ones still open.
public struct DisplayPrefs: Sendable, Equatable, Codable {
    public var transpose: Int
    public var capoMode: CapoMode
    public var nashville: Bool
    public var showDiagrams: Bool
    public var instrument: Instrument
    /// The song's guitar tuning (also written to the source as `{meta: tuning ...}`, which
    /// wins when present).
    public var tuning: Tuning

    public init(
        transpose: Int = 0,
        capoMode: CapoMode = .shapes,
        nashville: Bool = false,
        showDiagrams: Bool = true,
        instrument: Instrument = .guitar,
        tuning: Tuning = .standard,
    ) {
        self.transpose = transpose
        self.capoMode = capoMode
        self.nashville = nashville
        self.showDiagrams = showDiagrams
        self.instrument = instrument
        self.tuning = tuning
    }

    /// The prefs as render options.
    public init(_ options: DisplayOptions) {
        self.init(
            transpose: options.transpose,
            capoMode: options.capoMode,
            nashville: options.nashville,
            showDiagrams: options.showDiagrams,
            instrument: options.instrument,
            tuning: options.tuning,
        )
    }

    /// Render options for these prefs.
    public var displayOptions: DisplayOptions {
        DisplayOptions(
            transpose: transpose,
            capoMode: capoMode,
            nashville: nashville,
            showDiagrams: showDiagrams,
            instrument: instrument,
            tuning: tuning,
        )
    }

    private enum CodingKeys: String, CodingKey {
        case transpose
        case capoMode
        case nashville
        case showDiagrams
        case instrument
        case tuning
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = Self()
        func field<T: Decodable>(_ key: CodingKeys, _ fallback: T) -> T {
            (try? container.decodeIfPresent(T.self, forKey: key)) ?? fallback
        }
        transpose = field(.transpose, defaults.transpose)
        capoMode = field(.capoMode, defaults.capoMode)
        nashville = field(.nashville, defaults.nashville)
        showDiagrams = field(.showDiagrams, defaults.showDiagrams)
        instrument = field(.instrument, defaults.instrument)
        tuning = field(.tuning, defaults.tuning)
    }
}
