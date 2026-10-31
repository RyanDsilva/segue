// P8-7c (docs/phases/8-workstreams/P8-7-time-model-and-fills.md section 9.1, R167 Q9-Q10).
// One note of an instrument-neutral part, chord-relative so transpose, capo and slot key
// overrides keep it right. It lives in MusicTheory (not Library, where `Part` is) because the
// fill generator writes its candidates in it. Pure.

/// How a note is played. A closed vocabulary.
public enum Articulation: String, Sendable, Hashable, Codable, CaseIterable {
    case slide
    case hammer
    case pull
    case ghost
    case staccato
    case accent
}

/// One note of a `Part` (a fill), relative to a chord of the part's span.
///
/// On disk `{"chord": 0, "at": 960, "len": 240, "deg": 2, "oct": 0, "vel": 110,
/// "art": ["slide"], "string": "A1"}` (`vel`, `art` and `string` only when set).
public struct PartEvent: Sendable, Hashable, Codable {
    /// Index into the span, 0 ... count - 1 (the landing chord allowed).
    public var chord: Int
    /// Ticks from that chord's onset (480 per quarter), at least 0.
    public var at: Int
    /// Ticks, at least 1.
    public var len: Int
    /// 0 ... 11 semitones above that chord's bass (the slash bass, else the root).
    public var deg: Int
    /// -2 ... 2 octaves from the chord's placed bass note.
    public var oct: Int
    /// nil = `PartEvent.defaultVelocity`.
    public var velocity: UInt8?
    public var articulations: Set<Articulation>
    /// An optional pin: the open string's pitch ("A1"). Never changes the pitch.
    public var string: String?

    public static let defaultVelocity: UInt8 = 96
    public static let degrees = 0 ... 11
    public static let octaves = -2 ... 2

    public init(
        chord: Int,
        at: Int,
        len: Int,
        deg: Int,
        oct: Int = 0,
        velocity: UInt8? = nil,
        articulations: Set<Articulation> = [],
        string: String? = nil,
    ) {
        self.chord = chord
        self.at = at
        self.len = len
        self.deg = deg
        self.oct = oct
        self.velocity = velocity
        self.articulations = articulations
        self.string = string
    }

    /// The event for a note `semitones` above (or below) the chord's placed bass note: the
    /// canonical form, `deg` 0 ... 11 and `oct` the floor.
    public static func relative(
        chord: Int,
        at: Int,
        len: Int,
        semitones: Int,
        velocity: UInt8? = nil,
        articulations: Set<Articulation> = [],
    ) -> Self {
        let deg = ((semitones % 12) + 12) % 12
        return Self(
            chord: chord,
            at: at,
            len: len,
            deg: deg,
            oct: (semitones - deg) / 12,
            velocity: velocity,
            articulations: articulations,
        )
    }

    /// Semitones above the chord's placed bass note.
    public var semitones: Int {
        deg + 12 * oct
    }

    /// The velocity played.
    public var playedVelocity: UInt8 {
        velocity ?? Self.defaultVelocity
    }

    /// The open-string pitch of a pin, as MIDI ("A1" = 33); nil when it does not parse.
    public static func stringPitch(_ name: String) -> Int? {
        guard let match = name.wholeMatch(of: /([A-Ga-g])([#b]?)(-?\d)/),
              let octave = Int(match.output.3)
        else { return nil }
        let letters: [Character: Int] = ["C": 0, "D": 2, "E": 4, "F": 5, "G": 7, "A": 9, "B": 11]
        guard let base = letters[Character(match.output.1.uppercased())] else { return nil }
        let accidental = match.output.2 == "#" ? 1 : match.output.2 == "b" ? -1 : 0
        return 12 * (octave + 1) + base + accidental
    }

    private enum CodingKeys: String, CodingKey {
        case chord
        case at
        case len
        case deg
        case oct
        case velocity = "vel"
        case articulations = "art"
        case string
    }

    /// Strict: a value out of range, an unknown articulation or an unparsable `string`
    /// throws, so the part's lenient decoder drops this event alone.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        chord = try container.decode(Int.self, forKey: .chord)
        at = try container.decode(Int.self, forKey: .at)
        len = try container.decode(Int.self, forKey: .len)
        deg = try container.decode(Int.self, forKey: .deg)
        oct = try container.decodeIfPresent(Int.self, forKey: .oct) ?? 0
        velocity = try container.decodeIfPresent(UInt8.self, forKey: .velocity)
        articulations = try Set(
            container.decodeIfPresent([Articulation].self, forKey: .articulations) ?? [],
        )
        string = try container.decodeIfPresent(String.self, forKey: .string)
        guard chord >= 0, at >= 0, len >= 1, Self.degrees.contains(deg),
              Self.octaves.contains(oct), string.map({ Self.stringPitch($0) != nil }) ?? true
        else {
            throw DecodingError.dataCorruptedError(
                forKey: .deg,
                in: container,
                debugDescription: "not a part event",
            )
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(chord, forKey: .chord)
        try container.encode(at, forKey: .at)
        try container.encode(len, forKey: .len)
        try container.encode(deg, forKey: .deg)
        try container.encode(oct, forKey: .oct)
        try container.encodeIfPresent(velocity, forKey: .velocity)
        if !articulations.isEmpty {
            try container.encode(
                Articulation.allCases.filter(articulations.contains),
                forKey: .articulations,
            )
        }
        try container.encodeIfPresent(string, forKey: .string)
    }
}
