// P8-7c (docs/phases/8-workstreams/P8-7-time-model-and-fills.md sections 11.2-11.3, R168).
// The fill templates: rhythms measured back from the landing onset whose slots carry note
// functions, derived from the fill corpus (docs/research/phase8-fill-corpus.md section 5-6,
// fixture `Tests/Fixtures/fills/fill-corpus.json`). Compiled data, no runtime resource.

/// A slot's note function: the spec's closed R/C/S/A/O/P/D vocabulary.
public enum FillFunction: String, Sendable, Hashable, CaseIterable {
    /// The root (bass) of the chord sounding.
    case root = "R"
    /// A chord tone.
    case chordTone = "C"
    /// A passing-scale (or pentatonic) tone.
    case scale = "S"
    /// An approach into the next chord.
    case approach = "A"
    /// The octave.
    case octave = "O"
    /// A tone common to the two keys.
    case pivot = "P"
    /// The dominant of the next chord.
    case dominant = "D"
}

/// A time measured in a unit, so a template fits 4/4, 3/4 and 6/8 alike.
public struct FillTime: Sendable, Hashable {
    public enum Unit: Sendable, Hashable {
        /// The meter's pulse (a dotted quarter in 6/8, R118).
        case pulse
        case eighth
        case sixteenth
        /// An eighth-note triplet (160 ticks).
        case triplet
        /// The meter's bar.
        case bar
    }

    public var count: Int
    public var unit: Unit

    public init(_ count: Int, _ unit: Unit) {
        self.count = count
        self.unit = unit
    }

    /// Ticks at 480 per quarter.
    func ticks(pulse: Int, bar: Int) -> Int {
        switch unit {
        case .pulse: count * pulse
        case .eighth: count * 240
        case .sixteenth: count * 120
        case .triplet: count * 160
        case .bar: count * bar
        }
    }
}

/// How a slot's pitch is found (section 11.2).
public enum FillPitch: Sendable, Hashable {
    case root
    case octave
    case third
    case fifth
    /// The seventh, else the octave.
    case seventh
    case ninth
    /// Consecutive `approach` slots take the walk-up candidates into the landing (11.2).
    case approach
    /// Consecutive `scaleUp` / `scaleDown` slots: a passing-scale run into the landing.
    case scaleUp
    case scaleDown
    /// Consecutive slots: the sounding chord's pentatonic, down from the octave.
    case pentatonicDown
    /// Consecutive slots: the pentatonic up from the root (a bar figure).
    case pentatonicUp
    /// The landing chord's fifth (or the new key's 5 at a key change).
    case dominant
    /// The landing bass itself (an anticipation, a tihai's last note).
    case target
    /// `k` passing-scale steps above the landing bass (a tihai cell).
    case targetStep(Int)
    /// The half step below the landing bass (every corpus `approachNote`).
    case halfStepBelow
    /// Consecutive slots: the walk-up into the landing that arrives from a half step below
    /// (every corpus `pickup8` row), else the sounding chord's octave then the half step.
    case leadIn
    /// Consecutive slots: a passing-scale run into the landing, the shorter way.
    case scaleToward
    /// Consecutive slots: the departing root, then half steps into the landing. From a root
    /// within a major third of it the line starts on the root and covers the distance (B C
    /// into C#); from farther away the root then the last three half steps (A B C C# into
    /// D); the slots it does not need are dropped from the front.
    case chromaticLine
    /// The departing bass when it sits within a whole step of the landing (or on it, as
    /// the octave), else the approach: where a slide starts (every corpus `slideInto` row).
    case slideStart

    /// The spec vocabulary letter.
    public var function: FillFunction {
        switch self {
        case .root, .target: .root
        case .octave: .octave
        case .fifth, .ninth, .seventh, .third: .chordTone
        case .approach, .chromaticLine, .halfStepBelow, .leadIn, .slideStart, .targetStep:
            .approach
        case .pentatonicDown, .pentatonicUp, .scaleDown, .scaleToward, .scaleUp: .scale
        case .dominant: .dominant
        }
    }

    /// Slots of this kind are resolved together.
    var group: Int? {
        switch self {
        case .approach: 1
        case .scaleUp: 2
        case .scaleDown: 3
        case .pentatonicDown: 4
        case .pentatonicUp: 5
        case .leadIn: 6
        case .scaleToward: 7
        case .chromaticLine: 8
        default: nil
        }
    }
}

/// One note of a template.
public struct FillSlot: Sendable, Hashable {
    /// Before the landing onset (negative), or at / after it for an overhang.
    public var at: FillTime
    public var len: FillTime
    public var pitch: FillPitch
    public var articulations: Set<Articulation>
    /// Only in compound meters (a 6/8 pickup has three eighths).
    public var compoundOnly: Bool
    /// Dropped unless it falls inside the departing span after its first onset (a root
    /// re-struck on the last bar line of a chord longer than a bar).
    public var optional: Bool

    public init(
        _ at: FillTime,
        _ len: FillTime,
        _ pitch: FillPitch,
        articulations: Set<Articulation> = [],
        compoundOnly: Bool = false,
        optional: Bool = false,
    ) {
        self.at = at
        self.len = len
        self.pitch = pitch
        self.articulations = articulations
        self.compoundOnly = compoundOnly
        self.optional = optional
    }
}

/// When a template is offered.
public enum FillCondition: Sendable, Hashable {
    case always
    /// The landing is in a new key, prepared by its dominant (V' just before).
    case preparedLift
    /// The song's feel is Bollywood (R168: a tihai only then).
    case bollywood
    /// The landing is in the same key: into a new key a stop is the true break, with no
    /// pickup giving the new key away before the band (the corpus's only stop at a lift).
    case sameKey
    /// The landing is a different chord: there is a change to anticipate (an anticipation
    /// over a repeated chord pushes nothing).
    case change
}

/// What a template's shape does, which the situation it is offered in rewards or not
/// (`FillWeights.situation`, section 11.3).
public enum FillTrait: String, Sendable, Hashable, CaseIterable {
    /// Aims at the landing from outside it (a walk, a chromatic line, an approach note):
    /// nothing to aim at when the chord repeats.
    case approach
    /// Chord-scale material of the sounding chord (a pentatonic run, octaves, root-fifth):
    /// what a fill plays over a repeated chord.
    case chordScale
    /// Spells the sounding chord out (its arpeggio): what a dominant seventh invites.
    case arpeggio
    /// Marks the new downbeat itself (an anticipation, a slide, a repeated note, a stop):
    /// what the start of a new section invites.
    case accent
    /// A rhythmic cadence (a tihai): only into a new section.
    case cadence
}

/// One rhythm template (section 11.3).
public struct FillTemplate: Sendable, Hashable, Identifiable {
    public var id: String
    public var family: FillFamily
    /// The corpus family it implements (`fill-corpus.json`'s `family`).
    public var corpusFamily: String
    /// `walk`: one note per pulse over every departing chord (roots on onsets and bar lines,
    /// walk-ups into each next chord); otherwise `slots` before the landing.
    public var coversSpan: Bool
    public var slots: [FillSlot]
    public var condition: FillCondition
    /// Not offered in compound meters (they already triple, 11.5).
    public var simpleOnly: Bool
    /// The landing note is part of the template (an anticipation, an overhang, a tihai).
    public var ownsLanding: Bool
    /// The last note is made to lead into the landing; false for a break-stop, whose last
    /// note is the band's hit before the silence.
    public var leads: Bool
    public var traits: Set<FillTrait>
    /// The corpus example ids it was derived from.
    public var corpus: [String]

    public init(
        id: String,
        family: FillFamily,
        corpusFamily: String,
        coversSpan: Bool = false,
        slots: [FillSlot] = [],
        condition: FillCondition = .always,
        simpleOnly: Bool = false,
        ownsLanding: Bool = false,
        leads: Bool = true,
        traits: Set<FillTrait> = [],
        corpus: [String],
    ) {
        self.id = id
        self.family = family
        self.corpusFamily = corpusFamily
        self.coversSpan = coversSpan
        self.slots = slots
        self.condition = condition
        self.simpleOnly = simpleOnly
        self.ownsLanding = ownsLanding
        self.leads = leads
        self.traits = traits
        self.corpus = corpus
    }
}

/// The template set. Declaration order is the ranking's tie-break within a family.
public struct FillTemplates: Sendable, Hashable {
    public var templates: [FillTemplate]
    /// Corpus examples per (corpus family, feel), the source of `templatePrior` (11.3):
    /// fill-corpus.json at d2805f3 (81 examples). `FillTemplateCorpusTests` recounts them.
    public var counts: [String: [BassGenre: Int]]

    public init(templates: [FillTemplate], counts: [String: [BassGenre: Int]]) {
        self.templates = templates
        self.counts = counts
    }

    /// The template with this id.
    public func template(_ id: String) -> FillTemplate? {
        templates.first { $0.id == id }
    }

    /// The corpus families with no template of their own, and why: `turnaround` is a span
    /// shape the walk already plays (roots plus an approach), `melodicUnison` needs the melody
    /// (out of scope), `hold` is the explicit "no fill" candidate.
    public static let untemplated: [String: String] = [
        "turnaround": "quarterWalk",
        "melodicUnison": "",
        "hold": "hold",
    ]

    public static let standard = Self(templates: standardTemplates, counts: [
        "anticipation": [.rock: 1, .pop: 1],
        "approachNote": [.pop: 3, .worship: 1],
        "chordArpeggio": [.pop: 2],
        "chromaticLine": [.rock: 5, .pop: 3],
        "dominantApproach": [.pop: 3, .worship: 1, .bollywood: 1],
        "dominantPedal": [.pop: 1],
        "hold": [.worship: 2, .rock: 1, .bollywood: 2],
        "machineGun": [.rock: 1],
        "melodicUnison": [.bollywood: 1],
        "octavePops": [.rock: 2, .bollywood: 1],
        "pentatonicRun": [.pop: 3, .rock: 4, .bollywood: 1],
        "pickup8": [.pop: 4, .rock: 2, .bollywood: 4],
        "quarterWalk": [.pop: 3, .country: 2, .rock: 2, .bollywood: 1],
        "restPickup": [.rock: 1, .bollywood: 2],
        "rootFiveOctave": [.rock: 1, .pop: 2, .bollywood: 1],
        "scaleRun": [.worship: 1, .rock: 1, .country: 1, .bollywood: 1],
        "sixteenRun": [.rock: 1, .country: 1, .bollywood: 1],
        "slideInto": [.rock: 2, .pop: 1, .bollywood: 1],
        "stopTime": [.rock: 1, .pop: 1],
        "tihai": [.bollywood: 1],
        "tripletRun": [.pop: 1],
        "turnaround": [.rock: 1],
    ])
}
