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
    /// (each cue has a stable `id`; a cue on one occurrence stores its section's `fp`);
    /// 5 = P8-4b (`bass`: per-song walk-up feel and picks, play-along timing for P8-6; R161);
    /// 6 = P8-7c (`parts`: per-song instrument-neutral parts, bass fills; R167).
    public static let currentSchemaVersion = 6
    /// The `minReaderVersion` this build writes (R196: equal to the schema version in v1.0).
    public static let currentMinReaderVersion = 6

    public var schemaVersion: Int
    /// The file's `minReaderVersion` as read (R196); written back only while the file stays
    /// at a newer version than this build's.
    public var minReaderVersion: Int?
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
    /// The song's walk-up feel and picks, and play-along timing (schema 5, P8-4b).
    public var bass: BassPrefs
    /// Instrument-neutral parts: the song's bass fills (schema 6, P8-7c). Always encoded.
    public var parts: [Part]
    public var createdAt: Date
    public var updatedAt: Date
    /// Keys this build does not model, kept verbatim for the next save
    /// (docs/architecture/data-compatibility.md).
    public var unknown: UnknownFields

    public init(
        schemaVersion: Int = Self.currentSchemaVersion,
        id: SongID,
        tags: [String] = [],
        proficiency: Proficiency? = nil,
        notes: String? = nil,
        cues: [SongCue] = [],
        displayPrefs: DisplayPrefs = DisplayPrefs(),
        live: LivePrefs = LivePrefs(),
        bass: BassPrefs = BassPrefs(),
        parts: [Part] = [],
        createdAt: Date,
        updatedAt: Date,
        unknown: UnknownFields = .empty,
    ) {
        self.schemaVersion = schemaVersion
        self.id = id
        self.tags = tags
        self.proficiency = proficiency
        self.notes = notes
        self.cues = cues
        self.displayPrefs = displayPrefs
        self.live = live
        self.bass = bass
        self.parts = parts
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.unknown = unknown
    }

    /// The top-level keys this build models (`SidecarCodec` reads every other key into
    /// `unknown`).
    enum CodingKeys: String, CodingKey, CaseIterable {
        case schemaVersion
        case minReaderVersion
        case id
        case tags
        case proficiency
        case notes
        case cues
        case displayPrefs
        case live
        case bass
        case parts
        case createdAt
        case updatedAt
    }

    /// Decoded field by field and leniently (`SidecarCodec`); without a usable `id` the
    /// file is not a sidecar.
    public init(from decoder: any Decoder) throws {
        var partial = try PartialSidecar(from: decoder)
        partial.repairCueIDs()
        let version = max(
            partial.schemaVersion ?? Self.currentSchemaVersion,
            Self.currentSchemaVersion,
        )
        guard let sidecar = partial.complete(schemaVersion: version) else {
            throw DecodingError.dataCorrupted(DecodingError.Context(
                codingPath: decoder.codingPath,
                debugDescription: "a sidecar needs an id",
            ))
        }
        self = sidecar
    }

    public func encode(to encoder: any Encoder) throws {
        try unknown.encode(to: encoder)
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(schemaVersion, forKey: .schemaVersion)
        try container.encode(
            SchemaMigrator.minReaderVersion(
                writing: schemaVersion,
                kept: minReaderVersion,
                current: Self.currentSchemaVersion,
                currentMinimum: Self.currentMinReaderVersion,
            ),
            forKey: .minReaderVersion,
        )
        try container.encode(id, forKey: .id)
        try container.encode(tags, forKey: .tags)
        try container.encodeIfPresent(proficiency, forKey: .proficiency)
        try container.encodeIfPresent(notes, forKey: .notes)
        try container.encode(unknown.appending(cues, to: "cues"), forKey: .cues)
        try container.encode(displayPrefs, forKey: .displayPrefs)
        try container.encode(live, forKey: .live)
        try container.encode(bass, forKey: .bass)
        try container.encode(unknown.appending(parts, to: "parts"), forKey: .parts)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(updatedAt, forKey: .updatedAt)
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
    /// Keys this build does not model, kept for the next save.
    public var unknown: UnknownFields = .empty

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

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case id
        case section
        case occurrence
        case text
        case fingerprint = "fp"
    }

    /// A missing or unparseable `id` decodes as `CueID.unassigned`; the sidecar decoder then
    /// derives a stable one (`SidecarCodec`).
    public init(from decoder: any Decoder) throws {
        var object = try LenientObject<CodingKeys>(decoder)
        let container = object.container
        id = object.value(.id) ?? .unassigned
        section = try container.decode(String.self, forKey: .section)
        occurrence = try container.decodeIfPresent(Int.self, forKey: .occurrence)
        text = try container.decode(String.self, forKey: .text)
        fingerprint = object.value(.fingerprint)
        unknown = object.unknown
    }

    public func encode(to encoder: any Encoder) throws {
        try unknown.encode(to: encoder)
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
/// takes its default; a key this build no longer has (`collapseRepeats`, removed by R147) is
/// ignored and not written back.
public struct LivePrefs: Sendable, Hashable, Codable {
    /// Multiplier on the auto-fit lyric size (Cmd +/-, pinch); 1 = as fitted. The result is
    /// never below the user's minimum lyric size.
    public var zoom: Double
    /// Forced column count (1...3); nil = auto-fit chooses.
    public var columns: Int?
    /// Multiplier on the derived auto-scroll speed ([ and ] nudges); 1 = as derived.
    public var scrollSpeedFactor: Double
    /// Start auto-scroll on the first advance into this song instead of waiting for `A`.
    public var autoStartScroll: Bool
    /// Keys this build does not model, kept for the next save.
    public var unknown: UnknownFields = .empty

    public init(
        zoom: Double = 1,
        columns: Int? = nil,
        scrollSpeedFactor: Double = 1,
        autoStartScroll: Bool = false,
    ) {
        self.zoom = zoom
        self.columns = columns
        self.scrollSpeedFactor = scrollSpeedFactor
        self.autoStartScroll = autoStartScroll
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case zoom
        case columns
        case scrollSpeedFactor
        case autoStartScroll
    }

    /// Keys removed on purpose, dropped rather than kept: `collapseRepeats` (R147).
    static let retiredKeys: Set = ["collapseRepeats"]

    public init(from decoder: any Decoder) throws {
        var object = try LenientObject<CodingKeys>(decoder, retired: Self.retiredKeys)
        let defaults = Self()
        zoom = object.value(.zoom, default: defaults.zoom)
        columns = object.value(.columns)
        scrollSpeedFactor = object.value(.scrollSpeedFactor, default: defaults.scrollSpeedFactor)
        autoStartScroll = object.value(.autoStartScroll, default: defaults.autoStartScroll)
        unknown = object.unknown
    }

    public func encode(to encoder: any Encoder) throws {
        try unknown.encode(to: encoder)
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(zoom, forKey: .zoom)
        try container.encodeIfPresent(columns, forKey: .columns)
        try container.encode(scrollSpeedFactor, forKey: .scrollSpeedFactor)
        try container.encode(autoStartScroll, forKey: .autoStartScroll)
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
    /// Keys this build does not model, kept for the next save.
    public var unknown: UnknownFields = .empty

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

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case transpose
        case capoMode
        case nashville
        case showDiagrams
        case instrument
        case tuning
    }

    public init(from decoder: any Decoder) throws {
        var object = try LenientObject<CodingKeys>(decoder)
        let defaults = Self()
        transpose = object.value(.transpose, default: defaults.transpose)
        capoMode = object.value(.capoMode, default: defaults.capoMode)
        nashville = object.value(.nashville, default: defaults.nashville)
        showDiagrams = object.value(.showDiagrams, default: defaults.showDiagrams)
        instrument = object.value(.instrument, default: defaults.instrument)
        tuning = object.value(.tuning, default: defaults.tuning)
        unknown = object.unknown
    }

    public func encode(to encoder: any Encoder) throws {
        try unknown.encode(to: encoder)
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(transpose, forKey: .transpose)
        try container.encode(capoMode, forKey: .capoMode)
        try container.encode(nashville, forKey: .nashville)
        try container.encode(showDiagrams, forKey: .showDiagrams)
        try container.encode(instrument, forKey: .instrument)
        try container.encode(tuning, forKey: .tuning)
    }
}
