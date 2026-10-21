import Diagrams
import Editing
import Foundation
import MusicTheory
import Support

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
    /// diagrams, instrument, tuning); 3 = phase 2 (`cues`, `live` stage memory); 4 = P3-17
    /// (each cue has a stable `id`; a cue on one occurrence stores its section's `fp`).
    public static let currentSchemaVersion = 4

    public var schemaVersion: Int
    public var id: SongID
    /// Free-form tags, in the user's order and spelling (matching is case-insensitive).
    public var tags: [String]
    public var proficiency: Proficiency?
    /// Per-song notes, shown in live mode.
    public var notes: String?
    /// Cues pinned to sections, shown as callouts in live mode.
    public var cues: [SongCue]
    public var displayPrefs: DisplayPrefs
    /// Per-song live-mode memory (zoom, columns, scroll speed, repeat collapsing).
    public var live: LivePrefs
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        schemaVersion: Int = Self.currentSchemaVersion,
        id: SongID,
        tags: [String] = [],
        proficiency: Proficiency? = nil,
        notes: String? = nil,
        cues: [SongCue] = [],
        displayPrefs: DisplayPrefs = DisplayPrefs(),
        live: LivePrefs = LivePrefs(),
        createdAt: Date,
        updatedAt: Date,
    ) {
        self.schemaVersion = schemaVersion
        self.id = id
        self.tags = tags
        self.proficiency = proficiency
        self.notes = notes
        self.cues = cues
        self.displayPrefs = displayPrefs
        self.live = live
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

/// Stable identity of a stage note (a sidecar cue, R144): a ULID, unique within its song,
/// never reused and never shown. Encoded as its 26-character string.
public struct CueID: Sendable, Hashable, Comparable, Codable, CustomStringConvertible {
    public let ulid: ULID

    public init(_ ulid: ULID) {
        self.ulid = ulid
    }

    /// A new ID stamped now, with system randomness.
    public init() {
        var generator = SystemRandomNumberGenerator()
        let randomness = (0 ..< 10).map { _ in UInt8.random(in: .min ... .max, using: &generator) }
        ulid = ULID(timestamp: Date(), randomness: randomness)
    }

    public var description: String {
        ulid.description
    }

    public static func < (lhs: Self, rhs: Self) -> Bool {
        lhs.ulid < rhs.ulid
    }

    public init(from decoder: any Decoder) throws {
        ulid = try ULID(from: decoder)
    }

    public func encode(to encoder: any Encoder) throws {
        try ulid.encode(to: encoder)
    }

    /// Placeholder for a cue decoded without a usable `id`; never written (the sidecar
    /// decoder replaces it with a derived ID, `SidecarCodec`).
    public static let unassigned = Self(ULID(
        milliseconds: 0,
        randomness: Array(repeating: 0, count: 10),
    ))
}

/// A cue pinned to a section ("watch Ravi for the stop"), shown as a callout at the section's
/// edge in live mode. Phase 2 frozen interface (docs/phases/2-interfaces.md), plus `id` and
/// `fingerprint` (schema 4, P3-17).
///
/// On disk: `{"id": "01JB...", "section": "Chorus", "occurrence": 2, "fp": "1a2b3c4d",
/// "text": "Watch Ravi"}`.
public struct SongCue: Sendable, Hashable, Codable {
    /// Stable identity (R144), unique within the song.
    public var id: CueID
    /// The section label it is pinned to, as `RenderSection.label` shows it ("Chorus",
    /// "Verse 2"); matched case-insensitively after trimming.
    public var section: String
    /// Which occurrence of that label (1-based); nil pins it to every occurrence.
    public var occurrence: Int?
    public var text: String
    /// The content fingerprint (`SongSections.fingerprint`, R123) of the section a cue on
    /// one occurrence was placed on; nil for every-time cues. When label and occurrence no
    /// longer name a section with this fingerprint, the cue re-anchors to the one same-label
    /// section that has it (R145 question 5, `SectionNotes.reanchor`).
    public var fingerprint: String?

    public init(
        id: CueID = CueID(),
        section: String,
        occurrence: Int? = nil,
        text: String,
        fingerprint: String? = nil,
    ) {
        self.id = id
        self.section = section
        self.occurrence = occurrence
        self.text = text
        self.fingerprint = fingerprint
    }

    /// The same note content, identity ignored.
    public func sameContent(as other: Self) -> Bool {
        section == other.section && occurrence == other.occurrence && text == other.text
            && fingerprint == other.fingerprint
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case section
        case occurrence
        case text
        case fingerprint = "fp"
    }

    /// A missing or unparseable `id` decodes as `CueID.unassigned`; the sidecar decoder then
    /// derives a stable one (`SidecarCodec`).
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? container.decodeIfPresent(CueID.self, forKey: .id)) ?? .unassigned
        section = try container.decode(String.self, forKey: .section)
        occurrence = try container.decodeIfPresent(Int.self, forKey: .occurrence)
        text = try container.decode(String.self, forKey: .text)
        fingerprint = try? container.decodeIfPresent(String.self, forKey: .fingerprint)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(section, forKey: .section)
        try container.encodeIfPresent(occurrence, forKey: .occurrence)
        try container.encode(text, forKey: .text)
        try container.encodeIfPresent(fingerprint, forKey: .fingerprint)
    }
}

/// Per-song live-mode memory, persisted in the sidecar as `live`. Phase 2 frozen interface.
///
/// Decoding is per field and lenient, like `DisplayPrefs`: a missing or unreadable field
/// takes its default (so `collapseRepeats` reads as true when absent).
public struct LivePrefs: Sendable, Hashable, Codable {
    /// Multiplier on the auto-fit lyric size (Cmd +/-, pinch); 1 = as fitted. The result is
    /// never below the user's minimum lyric size.
    public var zoom: Double
    /// Forced column count (1...3); nil = auto-fit chooses.
    public var columns: Int?
    /// Multiplier on the derived auto-scroll speed ([ and ] nudges); 1 = as derived.
    public var scrollSpeedFactor: Double
    /// Collapse later repeats of an identical section into a one-line reference.
    public var collapseRepeats: Bool
    /// Start auto-scroll on the first advance into this song instead of waiting for `A`.
    public var autoStartScroll: Bool

    public init(
        zoom: Double = 1,
        columns: Int? = nil,
        scrollSpeedFactor: Double = 1,
        collapseRepeats: Bool = true,
        autoStartScroll: Bool = false,
    ) {
        self.zoom = zoom
        self.columns = columns
        self.scrollSpeedFactor = scrollSpeedFactor
        self.collapseRepeats = collapseRepeats
        self.autoStartScroll = autoStartScroll
    }

    private enum CodingKeys: String, CodingKey {
        case zoom
        case columns
        case scrollSpeedFactor
        case collapseRepeats
        case autoStartScroll
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = Self()
        func field<T: Decodable>(_ key: CodingKeys, _ fallback: T) -> T {
            (try? container.decodeIfPresent(T.self, forKey: key)) ?? fallback
        }
        zoom = field(.zoom, defaults.zoom)
        columns = (try? container.decodeIfPresent(Int.self, forKey: .columns))
        scrollSpeedFactor = field(.scrollSpeedFactor, defaults.scrollSpeedFactor)
        collapseRepeats = field(.collapseRepeats, defaults.collapseRepeats)
        autoStartScroll = field(.autoStartScroll, defaults.autoStartScroll)
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
        showDiagrams: Bool = false,
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
