// P8-4b (docs/phases/8-workstreams/P8-4-bass.md section 8.10, R161, R162 Q6). The sidecar's
// `bass` object (schema 5): a song's walk-up feel, its scale (R170, optional, still schema 6)
// and saved picks, and the play-along timing P8-6 fills (decoded and preserved here).

import Foundation
import MusicTheory
import Support

/// A song's bass settings: never in the `.cho`.
public struct BassPrefs: Sendable, Hashable, Codable {
    /// nil = the profile's default feel.
    public var genre: BassGenre?
    /// The song's scale for passing notes in walk-ups and fills (R170); nil = the default
    /// from the feel and key (`FillMode.standard`).
    public var mode: FillMode?
    /// Saved walk-up picks, one per (anchor, target).
    public var walkUps: [WalkUpPick]
    /// Filled by P8-6 (its section 7.3); P8-4b only preserves it.
    public var timing: ChordTiming
    /// Keys this build does not model, kept for the next save.
    public var unknown: UnknownFields = .empty

    public init(
        genre: BassGenre? = nil,
        mode: FillMode? = nil,
        walkUps: [WalkUpPick] = [],
        timing: ChordTiming = .init(),
    ) {
        self.genre = genre
        self.mode = mode
        self.walkUps = walkUps
        self.timing = timing
    }

    /// Nothing saved.
    public var isEmpty: Bool {
        genre == nil && mode == nil && walkUps.isEmpty && timing.isEmpty
    }

    /// `pick` saved, replacing any pick with the same anchor and target.
    public func saving(_ pick: WalkUpPick) -> Self {
        var prefs = removing(anchor: pick.anchor, to: pick.to)
        prefs.walkUps.append(pick)
        return prefs
    }

    /// Without the pick on `anchor` into `to` (pitch-class equality on both basses).
    public func removing(anchor: ChordAnchor, to: String) -> Self {
        var prefs = self
        prefs.walkUps.removeAll { $0.anchor.sameAnchor(as: anchor) && $0.to.sameBass(as: to) }
        return prefs
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case genre
        case mode
        case walkUps
        case timing
    }

    /// Lenient per field: a bad `genre` or `mode` reads nil, picks decode one by one (a bad
    /// one is dropped, the rest survive), a malformed `timing` reads empty.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        genre = try? container.decodeIfPresent(BassGenre.self, forKey: .genre)
        mode = try? container.decodeIfPresent(FillMode.self, forKey: .mode)
        walkUps = (try? container.decodeIfPresent([Lenient<WalkUpPick>].self, forKey: .walkUps))?
            .compactMap(\.value) ?? []
        timing = (try? container.decodeIfPresent(ChordTiming.self, forKey: .timing)) ?? .init()
        var object = try LenientObject<CodingKeys>(decoder)
        let _: BassGenre? = object.value(.genre)
        let _: FillMode? = object.value(.mode)
        unknown = object.unknown
    }

    public func encode(to encoder: any Encoder) throws {
        try unknown.encode(to: encoder)
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(genre, forKey: .genre)
        try container.encodeIfPresent(mode, forKey: .mode)
        try container.encode(walkUps, forKey: .walkUps)
        try container.encode(timing, forKey: .timing)
    }
}

/// One chord of a song, anchored so it survives edits (section 8.11): its section (the
/// arrangement keys), that section's content fingerprint, its ordinal among the section's
/// `.chord` chords and its bass as written.
public struct ChordAnchor: Sendable, Hashable {
    public var section: SectionAnchor
    /// "fp".
    public var fingerprint: String
    /// 0-based among the section's `.chord`-kind chords in written order.
    public var chord: Int
    /// The chord's bass as written ("B" for G/B), before any transpose or capo.
    public var from: String

    public init(section: SectionAnchor, fingerprint: String, chord: Int, from: String) {
        self.section = section
        self.fingerprint = fingerprint
        self.chord = chord
        self.from = from
    }

    /// The same chord: section, fingerprint, ordinal and bass (pitch class).
    func sameAnchor(as other: Self) -> Bool {
        section.matches(other.section) && fingerprint == other.fingerprint
            && chord == other.chord && from.sameBass(as: other.from)
    }

    private enum Keys: String, CodingKey {
        case chord
        case from
    }

    /// Reads the flattened anchor keys of a pick or a timing override.
    init(from decoder: any Decoder) throws {
        let anchor = try decoder.container(keyedBy: AnchorCodingKeys.self)
        section = try SectionAnchor.decode(from: anchor)
        fingerprint = try anchor.decode(String.self, forKey: .fingerprint)
        let container = try decoder.container(keyedBy: Keys.self)
        chord = try container.decode(Int.self, forKey: .chord)
        from = try container.decode(String.self, forKey: .from)
        guard chord >= 0, from.bassPitch != nil else {
            throw DecodingError.dataCorruptedError(
                forKey: .from,
                in: container,
                debugDescription: "not a chord anchor",
            )
        }
    }

    func encode(to encoder: any Encoder) throws {
        var anchor = encoder.container(keyedBy: AnchorCodingKeys.self)
        try section.encode(to: &anchor)
        try anchor.encode(fingerprint, forKey: .fingerprint)
        var container = encoder.container(keyedBy: Keys.self)
        try container.encode(chord, forKey: .chord)
        try container.encode(from, forKey: .from)
    }
}

/// A saved walk-up: on disk `{"section": "Verse", "occurrence": 1, "fp": "1a2b3c4d",
/// "chord": 3, "from": "G", "to": "C", "pick": "scaleWalk", "offsets": [-3, -1]}`.
public struct WalkUpPick: Sendable, Hashable, Codable {
    public var anchor: ChordAnchor
    /// The target's bass as written.
    public var to: String
    /// "pick".
    public var kind: WalkUpKind
    /// Semitones from the target bass, played order; [] for hold.
    public var offsets: [Int]

    public init(anchor: ChordAnchor, to: String, kind: WalkUpKind, offsets: [Int]) {
        self.anchor = anchor
        self.to = to
        self.kind = kind
        self.offsets = offsets
    }

    private enum Keys: String, CodingKey {
        case to
        case pick
        case offsets
    }

    /// Strict: an unknown kind, a missing anchor, more than 4 offsets or one outside
    /// -11 ... 11 throws (the sidecar then drops this pick alone).
    public init(from decoder: any Decoder) throws {
        anchor = try ChordAnchor(from: decoder)
        let container = try decoder.container(keyedBy: Keys.self)
        to = try container.decode(String.self, forKey: .to)
        kind = try container.decode(WalkUpKind.self, forKey: .pick)
        offsets = try container.decodeIfPresent([Int].self, forKey: .offsets) ?? []
        guard to.bassPitch != nil, offsets.count <= 4,
              offsets.allSatisfy({ (-11 ... 11).contains($0) })
        else {
            throw DecodingError.dataCorruptedError(
                forKey: .offsets,
                in: container,
                debugDescription: "not a walk-up pick",
            )
        }
    }

    public func encode(to encoder: any Encoder) throws {
        try anchor.encode(to: encoder)
        var container = encoder.container(keyedBy: Keys.self)
        try container.encode(to, forKey: .to)
        try container.encode(kind, forKey: .pick)
        try container.encode(offsets, forKey: .offsets)
    }
}

/// Play-along timing (P8-6 section 7.3): a song-wide rule and per-chord overrides, read by
/// `SongTimeline` (P8-7 section 5.6), plus the key-change suggestions dismissed (P8-7 6.2).
public struct ChordTiming: Sendable, Hashable, Codable {
    /// nil = one bar per chord.
    public var rule: TimingRule?
    public var chords: [ChordBeatsOverride]
    /// "Looks like a key change" chips dismissed with "x" (P8-7 section 6.2).
    public var dismissedKeys: [KeyChangeDismissal]

    public init(
        rule: TimingRule? = nil,
        chords: [ChordBeatsOverride] = [],
        dismissedKeys: [KeyChangeDismissal] = [],
    ) {
        self.rule = rule
        self.chords = chords
        self.dismissedKeys = dismissedKeys
    }

    public var isEmpty: Bool {
        rule == nil && chords.isEmpty && dismissedKeys.isEmpty
    }

    private enum CodingKeys: String, CodingKey {
        case rule
        case chords
        case dismissedKeys
    }

    /// Lenient: an unknown rule reads as absent; overrides and dismissals decode one by one.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        rule = try? container.decodeIfPresent(TimingRule.self, forKey: .rule)
        chords = (try? container.decodeIfPresent(
            [Lenient<ChordBeatsOverride>].self,
            forKey: .chords,
        ))?.compactMap(\.value) ?? []
        dismissedKeys = (try? container.decodeIfPresent(
            [Lenient<KeyChangeDismissal>].self,
            forKey: .dismissedKeys,
        ))?.compactMap(\.value) ?? []
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(rule, forKey: .rule)
        try container.encode(chords, forKey: .chords)
        if !dismissedKeys.isEmpty {
            try container.encode(dismissedKeys, forKey: .dismissedKeys)
        }
    }
}

/// A dismissed "Looks like a key change to A" chip (P8-7 section 6.2): on disk
/// `{"section": "Chorus", "occurrence": 3, "fp": "5e6f7a8b", "key": "A"}`.
public struct KeyChangeDismissal: Sendable, Hashable, Codable {
    public var section: SectionAnchor
    /// "fp".
    public var fingerprint: String
    /// The key the chip suggested.
    public var key: SongKey

    public init(section: SectionAnchor, fingerprint: String, key: SongKey) {
        self.section = section
        self.fingerprint = fingerprint
        self.key = key
    }

    private enum Keys: String, CodingKey {
        case key
    }

    public init(from decoder: any Decoder) throws {
        let anchor = try decoder.container(keyedBy: AnchorCodingKeys.self)
        section = try SectionAnchor.decode(from: anchor)
        fingerprint = try anchor.decode(String.self, forKey: .fingerprint)
        let container = try decoder.container(keyedBy: Keys.self)
        let name = try container.decode(String.self, forKey: .key)
        guard let key = SongKey(parsing: name) else {
            throw DecodingError.dataCorruptedError(
                forKey: .key,
                in: container,
                debugDescription: "not a key",
            )
        }
        self.key = key
    }

    public func encode(to encoder: any Encoder) throws {
        var anchor = encoder.container(keyedBy: AnchorCodingKeys.self)
        try section.encode(to: &anchor)
        try anchor.encode(fingerprint, forKey: .fingerprint)
        var container = encoder.container(keyedBy: Keys.self)
        try container.encode(key.name, forKey: .key)
    }
}

/// How long every chord lasts in play-along (P8-6 section 7.3): `{"each": "bar"}`,
/// `{"beats": 2}` or `{"line": 2}`.
public enum TimingRule: Sendable, Hashable, Codable {
    public enum Unit: String, Sendable, Hashable, Codable {
        case halfBar
        case bar
        case twoBars
    }

    case each(Unit)
    /// 1 ... 16 beats per chord.
    case beats(Int)
    /// Each lyric line lasts 1, 2 or 4 bars, shared by its chords.
    case line(Int)

    private enum CodingKeys: String, CodingKey {
        case each
        case beats
        case line
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let unit = try container.decodeIfPresent(Unit.self, forKey: .each) {
            self = .each(unit)
        } else if let beats = try container.decodeIfPresent(Int.self, forKey: .beats),
                  (1 ... 16).contains(beats)
        {
            self = .beats(beats)
        } else if let bars = try container.decodeIfPresent(Int.self, forKey: .line),
                  [1, 2, 4].contains(bars)
        {
            self = .line(bars)
        } else {
            throw DecodingError.dataCorrupted(.init(
                codingPath: decoder.codingPath,
                debugDescription: "unknown timing rule",
            ))
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .each(unit): try container.encode(unit, forKey: .each)
        case let .beats(beats): try container.encode(beats, forKey: .beats)
        case let .line(bars): try container.encode(bars, forKey: .line)
        }
    }
}

/// A timing correction (P8-6 section 7.3, P8-7 section 5.6): one chord lasts `beats`
/// pulses (1 ... 32), or `ticks` when set (a sub-beat length; it wins, and `beats` is
/// written as its rounded value so a reader that knows only `beats` gets a sensible length),
/// optionally pushed an eighth or sixteenth early. `source` is "tap" for a tapped length.
public struct ChordBeatsOverride: Sendable, Hashable, Codable {
    public enum Source: String, Sendable, Hashable, Codable {
        case tap
    }

    public var anchor: ChordAnchor
    public var beats: Int
    public var ticks: Int?
    public var push: Push?
    public var source: Source?

    /// `ticks` beyond 32 pulses of the longest pulse are refused.
    public static let ticksRange = 1 ... 32 * Ticks.perWhole

    public init(
        anchor: ChordAnchor,
        beats: Int,
        ticks: Int? = nil,
        push: Push? = nil,
        source: Source? = nil,
    ) {
        self.anchor = anchor
        self.beats = beats
        self.ticks = ticks
        self.push = push
        self.source = source
    }

    /// A sub-beat correction: `ticks` long in `meter`, `beats` its rounded pulses.
    public init(
        anchor: ChordAnchor,
        ticks: Int,
        meter: Meter,
        push: Push? = nil,
        source: Source? = nil,
    ) {
        let pulses = (Double(ticks) / Double(meter.ticksPerPulse)).rounded()
        self.init(
            anchor: anchor,
            beats: min(32, max(1, Int(pulses))),
            ticks: ticks,
            push: push,
            source: source,
        )
    }

    private enum Keys: String, CodingKey {
        case beats
        case ticks
        case push
        case source
    }

    /// Strict on the anchor and `beats` (the sidecar then drops this override alone);
    /// lenient on the P8-7 fields: a bad `ticks`, `push` or `source` drops only that field.
    public init(from decoder: any Decoder) throws {
        anchor = try ChordAnchor(from: decoder)
        let container = try decoder.container(keyedBy: Keys.self)
        beats = try container.decode(Int.self, forKey: .beats)
        guard (1 ... 32).contains(beats) else {
            throw DecodingError.dataCorruptedError(
                forKey: .beats,
                in: container,
                debugDescription: "beats outside 1 ... 32",
            )
        }
        ticks = (try? container.decodeIfPresent(Int.self, forKey: .ticks))
            .flatMap { Self.ticksRange.contains($0) ? $0 : nil }
        push = try? container.decodeIfPresent(Push.self, forKey: .push)
        source = try? container.decodeIfPresent(Source.self, forKey: .source)
    }

    public func encode(to encoder: any Encoder) throws {
        try anchor.encode(to: encoder)
        var container = encoder.container(keyedBy: Keys.self)
        try container.encode(beats, forKey: .beats)
        try container.encodeIfPresent(ticks, forKey: .ticks)
        try container.encodeIfPresent(push, forKey: .push)
        try container.encodeIfPresent(source, forKey: .source)
    }
}

/// Decodes one element, keeping nil instead of failing the whole array.
private struct Lenient<Value: Decodable>: Decodable {
    var value: Value?

    init(from decoder: any Decoder) throws {
        value = try? Value(from: decoder)
    }
}

extension String {
    /// The pitch class of a bass as a pick stores it: a chart note name ("B", "F#", "Bb").
    var bassPitch: PitchClass? {
        guard let symbol = ChordSymbol(parsing: self), symbol.suffix.isEmpty, symbol.bass == nil
        else { return nil }
        return symbol.root.pitchClass
    }

    /// The same bass note, by pitch class ("A#" and "Bb" agree).
    func sameBass(as other: String) -> Bool {
        guard let left = bassPitch, let right = other.bassPitch else { return self == other }
        return left == right
    }
}
