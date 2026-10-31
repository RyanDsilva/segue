// P8-7c (docs/phases/8-workstreams/P8-7-time-model-and-fills.md section 11, R166-R168).
// Bass fills over a span of chords: the closed vocabularies a saved part's provenance uses.
// Pure.

import Tonic

/// A fill's rhythm family (section 11.3). Closed: widening it is a spec change (R168 Q10).
/// Declaration order is the ranking's tie-break.
public enum FillFamily: String, Sendable, Hashable, Codable, CaseIterable {
    /// One note per pulse, a walking line.
    case walk
    /// Eighth pickups into the landing.
    case pickup
    /// Sixteenth runs.
    case run
    /// Eighth or sixteenth triplets.
    case triplet
    /// Root, fifth and octave figures.
    case octave
    /// Anticipations, stops and rest-then-approach.
    case push

    /// The candidate row's name in the fill editor.
    public var title: String {
        switch self {
        case .walk: "Walk"
        case .pickup: "Pickup"
        case .run: "Sixteenth run"
        case .triplet: "Triplets"
        case .octave: "Octaves"
        case .push: "Push"
        }
    }
}

/// Where a saved fill came from in the candidate list: A-D, "More" (the fifth), or written
/// from scratch.
public enum CandidateRank: String, Sendable, Hashable, Codable, CaseIterable {
    // The option letters the sheet shows (section 9.5 stores them as "a" ... "d").
    // swiftlint:disable identifier_name
    case a
    case b
    case c
    case d
    // swiftlint:enable identifier_name
    case more
    case scratch

    /// The rank of the candidate at `index` (0-based) in `Fill.candidates`.
    public init(index: Int) {
        self = switch index {
        case 0: .a
        case 1: .b
        case 2: .c
        case 3: .d
        default: .more
        }
    }
}

/// The terms of a candidate's score.
public enum FillTerm: String, Sendable, Hashable, CaseIterable {
    case templatePrior
    case strongBeatTone
    case clash
    case resolution
    case density
    case contour
    case range
    case keyChange
    case downbeat
    case walkUpAgreement
    /// The hold candidate's restraint bonus (R168: first for written lines, bVI-bVII-i and
    /// slow Worship, top two at a key change).
    case restraint

    /// The terms summed in declaration order, so the score never depends on dictionary
    /// order (deterministic to the last bit).
    public static func sum(_ terms: [Self: Double]) -> Double {
        allCases.reduce(0) { $0 + (terms[$1] ?? 0) }
    }
}

/// A meter as the generator counts it (the timeline's `Meter`, R118).
public struct FillMeter: Sendable, Hashable {
    public var pulses: Int
    public var ticksPerPulse: Int
    /// 6/8, 9/8, 12/8.
    public var compound: Bool

    public init(pulses: Int, ticksPerPulse: Int, compound: Bool) {
        self.pulses = max(1, pulses)
        self.ticksPerPulse = max(1, ticksPerPulse)
        self.compound = compound
    }

    public static let common = Self(pulses: 4, ticksPerPulse: 480, compound: false)

    public var ticksPerBar: Int {
        pulses * ticksPerPulse
    }
}

/// One chord of a fill span, at concert pitch.
public struct FillSpanChord: Sendable, Hashable {
    public var chord: ChordSymbol
    /// The slash bass, else the root.
    public var bass: PitchClass
    /// Ticks (480 per quarter).
    public var length: Int
    /// The length is the song's rule (no chart marks or correction).
    public var estimated: Bool
    /// The concert key in effect.
    public var key: SongKey?
    public var meter: FillMeter
    /// The chord's placed bass note (MIDI): where the play-along bass plays it, and what a
    /// part event's `oct` counts from.
    public var placed: Int
    /// Ticks from its bar's downbeat to its onset (0 on a downbeat).
    public var onsetInBar: Int

    public init(
        chord: ChordSymbol,
        bass: PitchClass? = nil,
        length: Int,
        estimated: Bool = false,
        key: SongKey?,
        meter: FillMeter = .common,
        placed: Int,
        onsetInBar: Int = 0,
    ) {
        self.chord = chord
        self.bass = bass ?? (chord.bass ?? chord.root).pitchClass
        self.length = length
        self.estimated = estimated
        self.key = key
        self.meter = meter
        self.placed = placed
        self.onsetInBar = onsetInBar
    }
}

/// The facts a fill is chosen from (section 11.1).
public struct FillContext: Sendable, Hashable {
    /// The departing chords, then the landing.
    public var span: [FillSpanChord]
    /// The song's feel, else the profile's (R161).
    public var genre: BassGenre?
    public var tempo: Double?
    /// The passing scale's mode for keys of its quality (harmonic minor, Bhairav, the major
    /// pentatonic); nil = each key's own.
    public var mode: FillMode?
    /// The instrument's range (MIDI): lowest open string ... highest + 20 frets.
    public var range: ClosedRange<Int>
    /// The landing starts a new section.
    public var intoSection: Bool
    /// The landing section raises the energy (chorus, bridge), settles it (verse), else nil.
    public var energyUp: Bool?

    public init(
        span: [FillSpanChord],
        genre: BassGenre? = nil,
        tempo: Double? = nil,
        mode: FillMode? = nil,
        range: ClosedRange<Int> = 28 ... 63,
        intoSection: Bool = false,
        energyUp: Bool? = nil,
    ) {
        self.span = span
        self.genre = genre
        self.tempo = tempo
        self.mode = mode
        self.range = range
        self.intoSection = intoSection
        self.energyUp = energyUp
    }
}

/// One ranked fill.
public struct FillCandidate: Sendable, Hashable {
    /// nil for the hold ("no fill") candidate.
    public var family: FillFamily?
    /// A `FillTemplates` id, or "hold".
    public var template: String
    /// Chord-relative, in time order; [] for hold.
    public var events: [PartEvent]
    /// Per event, spelled (section 9.2).
    public var names: [NoteClass]
    public var score: Double
    /// Every weighted term; the values sum to `score`.
    public var breakdown: [FillTerm: Double]
    /// The corpus example ids the template came from.
    public var corpus: [String]

    public init(
        family: FillFamily?,
        template: String,
        events: [PartEvent],
        names: [NoteClass],
        score: Double,
        breakdown: [FillTerm: Double],
        corpus: [String],
    ) {
        self.family = family
        self.template = template
        self.events = events
        self.names = names
        self.score = score
        self.breakdown = breakdown
        self.corpus = corpus
    }

    public static let holdTemplate = "hold"

    /// "No fill": the written roots, the pick kept (R168).
    public var isHold: Bool {
        template == Self.holdTemplate
    }
}

public enum Fill {
    /// Up to `weights.limit` candidates (A-D, then "More"), at most one per family plus the
    /// hold candidate, best first; deterministic. `[]` only for a span the generator cannot
    /// read (fewer than two chords).
    public static func candidates(
        _ context: FillContext,
        weights: FillWeights = .standard,
        templates: FillTemplates = .standard,
    ) -> [FillCandidate] {
        FillGenerator(context: context, weights: weights, templates: templates)?.ranked() ?? []
    }

    /// Every template's candidate that fits (before choosing one per family), best first.
    public static func all(
        _ context: FillContext,
        weights: FillWeights = .standard,
        templates: FillTemplates = .standard,
    ) -> [FillCandidate] {
        FillGenerator(context: context, weights: weights, templates: templates)?.all() ?? []
    }
}
