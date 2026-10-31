// P8-4b (docs/phases/8-workstreams/P8-4-bass.md section 8, R161, R162; research
// docs/research/phase8-bass-patterns.md section 3). Deterministic, ranked walk-up
// suggestions into the next chord. Pure.

import Tonic

/// A song's feel for walk-ups (R161). Stored per song in the sidecar; the profile holds the
/// default. It only reorders candidates.
public enum BassGenre: String, Sendable, Hashable, Codable, CaseIterable {
    case pop
    case rock
    case worship
    /// "Country / gospel".
    case country
    /// "Bollywood" (Hindi film and raga-flavoured songs).
    case bollywood

    /// The menu name.
    public var title: String {
        switch self {
        case .pop: "Pop"
        case .rock: "Rock"
        case .worship: "Worship"
        case .country: "Country / gospel"
        case .bollywood: "Bollywood"
        }
    }
}

/// How many walk-ups charts and the stage show (Settings > Instrument, section 8.7).
public enum WalkUpDensity: String, Sendable, Hashable, Codable, CaseIterable {
    case off
    /// Only into a new section.
    case sections
    case everyChange

    /// The menu name.
    public var title: String {
        switch self {
        case .off: "Off"
        case .sections: "Into sections"
        case .everyChange: "Every change"
        }
    }
}

/// What a candidate is, from a closed vocabulary [R3.3] plus `hold`. Declaration order is
/// the ranking's tie-break.
public enum WalkUpKind: String, Sendable, Hashable, Codable, CaseIterable {
    /// "Nothing here": the written roots already walk (R161, bVI-bVII-i).
    case hold
    case scaleWalk
    case scaleChrom
    case diatonicNeighbour
    case chromBelow
    case chromAbove
    case fifth
    case doubleChromAbove
    case octavePickup
}

/// The facts a walk-up is chosen from (section 8.2).
public struct WalkUpContext: Sendable, Hashable {
    /// The concert key; nil = unknown.
    public var key: SongKey?
    /// Chord A at concert pitch (its tones override the scale).
    public var departing: ChordSymbol
    /// Chord B at concert pitch.
    public var arriving: ChordSymbol
    /// nil = the research's "unknown" column (the legacy rule, tests).
    public var genre: BassGenre?
    /// Chord A's estimated beats (section 8.5); nil = unknown.
    public var beats: Int?
    /// `{tempo}`; nil = assume mid.
    public var tempo: Double?
    /// A ends its section and B starts the next one with chords.
    public var intoSection: Bool
    /// B's section is a chorus or bridge (true), a verse (false), else nil.
    public var energyUp: Bool?
    /// A -> B sits in a written stepwise bass line (rule S2).
    public var writtenLine: Bool
    /// The song's scale (R170): the passing scale for a key of its quality; nil = the key's
    /// own.
    public var mode: FillMode?

    public init(
        key: SongKey?,
        departing: ChordSymbol,
        arriving: ChordSymbol,
        genre: BassGenre? = nil,
        beats: Int? = nil,
        tempo: Double? = nil,
        intoSection: Bool = false,
        energyUp: Bool? = nil,
        writtenLine: Bool = false,
        mode: FillMode? = nil,
    ) {
        self.key = key
        self.departing = departing
        self.arriving = arriving
        self.genre = genre
        self.beats = beats
        self.tempo = tempo
        self.intoSection = intoSection
        self.energyUp = energyUp
        self.writtenLine = writtenLine
        self.mode = mode
    }

    /// The pre-research rule's context: unknown genre, unknown beats, no section facts.
    public static func legacy(key: SongKey?, from: ChordSymbol, to: ChordSymbol) -> Self {
        Self(key: key, departing: from, arriving: to)
    }
}

/// One ranked suggestion.
public struct WalkUpCandidate: Sendable, Hashable {
    public enum Direction: String, Sendable, Hashable {
        case up
        case down
        case neither
    }

    public var kind: WalkUpKind
    /// Spelled, concert pitch, played order (the target follows); [] for `hold`.
    public var notes: [NoteClass]
    /// Semitones from the target bass, played order, e.g. [-3, -1].
    public var offsets: [Int]
    public var direction: Direction
    /// Per note: outside the passing scale.
    public var chromatic: [Bool]
    /// Per note, relative to the key ("2", "#4", "b7"); [] without a key.
    public var degrees: [String]
    public var score: Double
    /// Every weighted term; the values sum to `score`.
    public var breakdown: [WalkUpTerm: Double]

    public init(
        kind: WalkUpKind,
        notes: [NoteClass],
        offsets: [Int],
        direction: Direction,
        chromatic: [Bool],
        degrees: [String],
        score: Double,
        breakdown: [WalkUpTerm: Double],
    ) {
        self.kind = kind
        self.notes = notes
        self.offsets = offsets
        self.direction = direction
        self.chromatic = chromatic
        self.degrees = degrees
        self.score = score
        self.breakdown = breakdown
    }

    /// Whether any note lies outside the passing scale.
    public var isChromatic: Bool {
        chromatic.contains(true)
    }
}

/// The terms of a candidate's score.
public enum WalkUpTerm: String, Sendable, Hashable, CaseIterable {
    case genrePrior
    case clash
    case resolution
    case direction
    case length
    case minorTonic
    case intoSection
    case writtenLine
}

/// Why a change has no candidates (section 8.3), for the Walk-ups list.
public enum WalkUpSuppression: String, Sendable, Hashable, CaseIterable {
    /// S1: the same note, or already a half step.
    case step
    /// S3: A or B is `N.C.` or unknown, or A is the last chord.
    case noChord
    /// S4: too short (one beat, or fast and two beats).
    case short
    /// S5: the density skips it ("Into sections" and A does not end its section).
    case density
    /// S6: a Worship feel or a slow song keeps chromatic runs out of the section.
    case restraint
    /// No candidate scored above the floor.
    case nothingFits

    /// The muted reason in the popover and list.
    public var reason: String {
        switch self {
        case .step: "Already a step"
        case .noChord: "No chord to walk from or to"
        case .short: "The chord is too short for a walk-up"
        case .density: "Walk-ups show only into sections"
        case .restraint: "Only chromatic runs fit, and this feel keeps them out"
        case .nothingFits: "No walk-up fits"
        }
    }
}

public enum WalkUp {
    /// 0 ... 4 ranked candidates for the move from bass `from` to bass `to` (concert pitch
    /// classes).
    public static func candidates(
        from: PitchClass,
        to: PitchClass,
        context: WalkUpContext,
        weights: WalkUpWeights = .standard,
    ) -> [WalkUpCandidate] {
        evaluate(from: from, to: to, context: context, weights: weights).candidates
    }

    /// The candidates and, when there are none, which rule suppressed them.
    public static func evaluate(
        from: PitchClass,
        to: PitchClass,
        context: WalkUpContext,
        weights: WalkUpWeights = .standard,
    ) -> (candidates: [WalkUpCandidate], suppressed: WalkUpSuppression?) {
        let move = WalkUpMove(from: from, to: to, context: context, weights: weights)
        return move.ranked()
    }

    /// The legacy single answer: `candidates(from:to:context: .legacy(...)).first?.notes`.
    /// Chord A is the key's diatonic triad on `from` (a major triad off the key), chord B a
    /// major triad, so the passing scale is the key's scale.
    public static func notes(from: PitchClass, to: PitchClass, key: SongKey?) -> [NoteClass] {
        let context = WalkUpContext.legacy(
            key: key,
            from: triad(on: from, in: key),
            to: triad(on: to, in: key),
        )
        return candidates(from: from, to: to, context: context).first?.notes ?? []
    }

    /// The candidate a saved pick names, rebuilt at concert pitch and spelled by the
    /// section 8.3 rule (a pick survives transposition and key overrides). nil when the
    /// offsets do not fit (more than 4, or outside -11 ... 11).
    public static func candidate(
        kind: WalkUpKind,
        offsets: [Int],
        from: PitchClass,
        to: PitchClass,
        context: WalkUpContext,
    ) -> WalkUpCandidate? {
        guard offsets.count <= 4, offsets.allSatisfy({ (-11 ... 11).contains($0) }) else {
            return nil
        }
        if kind == .hold {
            return WalkUpMove.hold(score: 0, breakdown: [:])
        }
        let move = WalkUpMove(from: from, to: to, context: context, weights: .standard)
        if let generated = move.all().first(where: { $0.kind == kind && $0.offsets == offsets }) {
            return generated
        }
        let direction: WalkUpCandidate.Direction = if offsets.allSatisfy({ $0 < 0 }) {
            .up
        } else if offsets.allSatisfy({ $0 > 0 }) {
            .down
        } else {
            .neither
        }
        let scale = move.scale(melodic: direction == .up)
        let pitches = offsets.map { to.transposed(by: $0) }
        return move.make(kind, pitches, offsets: offsets, direction: direction, scale: scale)
    }

    /// Rule S2: the bass notes of (previous, A, B) or (A, B, next) each move 1-2 semitones
    /// in one direction (`C - C/B - Am - Am/G`, the rock `F G Am`).
    public static func isWrittenLine(
        previous: PitchClass?,
        from: PitchClass,
        to: PitchClass,
        next: PitchClass?,
    ) -> Bool {
        func steps(_ notes: [PitchClass]) -> Bool {
            let moves = zip(notes, notes.dropFirst()).map { signedDistance($0, $1) }
            return moves.allSatisfy { (1 ... 2).contains($0) }
                || moves.allSatisfy { (-2 ... -1).contains($0) }
        }
        if let previous, steps([previous, from, to]) {
            return true
        }
        if let next, steps([from, to, next]) {
            return true
        }
        return false
    }

    /// The signed shortest distance from `from` to `to`, -5 ... 6 (a tritone counts as up).
    public static func signedDistance(_ from: PitchClass, _ to: PitchClass) -> Int {
        let up = from.semitones(to: to)
        return up <= 6 ? up : up - 12
    }

    /// The most approach notes: known `n` beats give `min(3, n - 1)`, unknown 2.
    public static func maxNotes(beats: Int?) -> Int {
        beats.map { max(0, min(3, $0 - 1)) } ?? 2
    }

    /// The key's diatonic triad on `root` (major off the key or without one).
    static func triad(on root: PitchClass, in key: SongKey?) -> ChordSymbol {
        let spelled = KeySpelling.spell(root, in: key)
        var suffix = ""
        if let key {
            let scale = Set(key.scaleNotes.map(\.pitchClass))
            if scale.contains(root) {
                let third = scale.contains(root.transposed(by: 4)) ? 4 : 3
                let fifth = scale.contains(root.transposed(by: 7)) ? 7 : 6
                suffix = third == 4 ? "" : (fifth == 7 ? "m" : "dim")
            }
        }
        return ChordSymbol(parsing: spelled.chartName + suffix)
            ?? ChordSymbol(root: spelled, suffix: "", formula: ChordFormula(
                intervals: [0, 4, 7],
                essential: [0, 4],
            ))
    }
}
