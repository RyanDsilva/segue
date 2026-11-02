// P8-7c (docs/phases/8-workstreams/P8-7-time-model-and-fills.md section 9, R167 Q7-Q10).
// An instrument-neutral part over a span of chords (a bass fill), saved per song in the
// sidecar's `parts` (schema 6), never in the `.cho`. Pure.

import Foundation
import MusicTheory
import Support

/// Stable identity of a part: a ULID, unique within its song. Encoded as its string.
public struct PartID: Sendable, Hashable, Comparable, Codable, CustomStringConvertible {
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
}

/// Which instrument a part is for. Only bass in P8-7 (R167 Q10; guitar and keys later).
public enum InstrumentRef: String, Sendable, Hashable, Codable, CaseIterable {
    case bass
}

/// The chords a part is written over: the first departing chord, the landing chord, and the
/// written bass of every chord from start to landing (a span must still have them to apply).
public struct SpanAnchor: Sendable, Hashable {
    public var start: ChordAnchor
    public var end: ChordAnchor
    /// Written basses ("E", "A"), start ... landing, 2 ... 9 of them.
    public var spanBass: [String]

    public init(start: ChordAnchor, end: ChordAnchor, spanBass: [String]) {
        self.start = start
        self.end = end
        self.spanBass = spanBass
    }

    /// The chords a span may hold (R168 Q11).
    public static let chordCount = 2 ... 9
}

/// "Shows on" (R146, R167 Q7): on which plays of the start chord's section a part applies.
public enum PassFilter: Sendable, Hashable, Codable {
    case all
    /// 1-based plays of the section ("Chorus 2/3").
    case only(Set<Int>)
    case last

    /// Whether the `occurrence`-th play of `of` plays applies.
    public func admits(occurrence: Int, of plays: Int) -> Bool {
        switch self {
        case .all: true
        case let .only(set): set.contains(occurrence)
        case .last: occurrence == plays
        }
    }

    /// `"all"`, `"last"` or an array of 1-based plays.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let text = try? container.decode(String.self) {
            switch text {
            case "all": self = .all
            case "last": self = .last
            default:
                throw DecodingError.dataCorruptedError(
                    in: container,
                    debugDescription: "not a pass filter",
                )
            }
            return
        }
        let plays = try container.decode([Int].self)
        guard !plays.isEmpty, plays.allSatisfy({ $0 >= 1 }) else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "not a pass filter",
            )
        }
        self = .only(Set(plays))
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .all: try container.encode("all")
        case .last: try container.encode("last")
        case let .only(set): try container.encode(set.sorted())
        }
    }
}

/// How a part reads on stage (R167 Q12).
public enum PartShow: String, Sendable, Hashable, Codable, CaseIterable {
    case names
    case tab
}

/// Where a part came from, for analytics and "Revert".
public struct PartOrigin: Sendable, Hashable, Codable {
    public var family: FillFamily
    /// A `FillTemplates` id.
    public var template: String
    public var rank: CandidateRank
    public var edited: Bool

    public init(family: FillFamily, template: String, rank: CandidateRank, edited: Bool) {
        self.family = family
        self.template = template
        self.rank = rank
        self.edited = edited
    }
}

/// An instrument-neutral list of note events over a span (section 9.1). A fill is a bass
/// part.
///
/// On disk (section 9.5): `{"id", "instrument": "bass", "name", "start": {anchor},
/// "end": {anchor}, "span": ["E", "A"], "passes": "all", "show": "names", "origin",
/// "events": [...]}`.
public struct Part: Sendable, Hashable, Identifiable, Codable {
    public var id: PartID
    public var instrument: InstrumentRef
    public var name: String?
    public var span: SpanAnchor
    public var passes: PassFilter
    public var show: PartShow
    /// nil = written from scratch.
    public var origin: PartOrigin?
    public var events: [PartEvent]
    /// Keys this build does not model, kept for the next save.
    public var unknown: UnknownFields = .empty

    public init(
        id: PartID = PartID(),
        instrument: InstrumentRef = .bass,
        name: String? = nil,
        span: SpanAnchor,
        passes: PassFilter = .all,
        show: PartShow = .names,
        origin: PartOrigin? = nil,
        events: [PartEvent],
    ) {
        self.id = id
        self.instrument = instrument
        self.name = name
        self.span = span
        self.passes = passes
        self.show = show
        self.origin = origin
        self.events = events
    }

    /// The number of chords in the span, the landing included.
    public var chordCount: Int {
        span.spanBass.count
    }

    /// The written changes the part covers: (departing ordinal in the span, landing ordinal).
    public var changes: [(from: Int, to: Int)] {
        (0 ..< max(0, chordCount - 1)).map { ($0, $0 + 1) }
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case id
        case instrument
        case name
        case start
        case end
        case span
        case passes
        case show
        case origin
        case events
    }

    /// Lenient inside, strict at the part level (section 9.5): events decode one by one and a
    /// bad one is dropped; an unknown instrument, a bad anchor, a span outside 2 ... 9
    /// chords or no valid event throws, so the sidecar drops this part alone.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(PartID.self, forKey: .id)
        instrument = try container.decode(InstrumentRef.self, forKey: .instrument)
        name = try? container.decodeIfPresent(String.self, forKey: .name)
        let start = try ChordAnchor(from: container.superDecoder(forKey: .start))
        let end = try ChordAnchor(from: container.superDecoder(forKey: .end))
        let bass = try container.decode([String].self, forKey: .span)
        guard SpanAnchor.chordCount.contains(bass.count), bass.allSatisfy({ $0.bassPitch != nil })
        else {
            throw DecodingError.dataCorruptedError(
                forKey: .span,
                in: container,
                debugDescription: "a span holds 2 ... 9 chords",
            )
        }
        span = SpanAnchor(start: start, end: end, spanBass: bass)
        passes = (try? container.decodeIfPresent(PassFilter.self, forKey: .passes)) ?? .all
        show = (try? container.decodeIfPresent(PartShow.self, forKey: .show)) ?? .names
        origin = try? container.decodeIfPresent(PartOrigin.self, forKey: .origin)
        struct LenientEvent: Decodable {
            var event: PartEvent?

            init(from decoder: any Decoder) throws {
                event = try? PartEvent(from: decoder)
            }
        }
        events = try container.decode([LenientEvent].self, forKey: .events)
            .compactMap(\.event)
            .filter { $0.chord < bass.count }
        guard !events.isEmpty else {
            throw DecodingError.dataCorruptedError(
                forKey: .events,
                in: container,
                debugDescription: "a part has at least one event",
            )
        }
        var object = try LenientObject<CodingKeys>(decoder)
        let _: PassFilter? = object.value(.passes)
        let _: PartShow? = object.value(.show)
        let _: PartOrigin? = object.value(.origin)
        unknown = object.unknown
    }

    public func encode(to encoder: any Encoder) throws {
        try unknown.encode(to: encoder)
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(instrument, forKey: .instrument)
        try container.encodeIfPresent(name, forKey: .name)
        try span.start.encode(to: container.superEncoder(forKey: .start))
        try span.end.encode(to: container.superEncoder(forKey: .end))
        try container.encode(span.spanBass, forKey: .span)
        try container.encode(passes, forKey: .passes)
        try container.encode(show, forKey: .show)
        try container.encodeIfPresent(origin, forKey: .origin)
        try container.encode(events, forKey: .events)
    }
}
