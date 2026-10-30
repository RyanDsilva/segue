// P8-4b (docs/phases/8-workstreams/P8-4-bass.md section 8.3, research section 3). The
// walk-up rules: suppression, passing scale, candidate generation, spelling and scoring.

import Tonic

/// One move from bass `source` to bass `target` with its context: generates, scores and ranks.
struct WalkUpMove {
    let source: PitchClass
    let target: PitchClass
    let context: WalkUpContext
    let weights: WalkUpWeights
    /// Signed shortest distance, -5 ... 6.
    let distance: Int
    let dUp: Int
    let maxNotes: Int
    /// Chord A's tones (any of them is never a clash).
    let departingTones: Set<PitchClass>
    /// Chord A's third, fifth and seventh, spelled.
    let third: NoteClass?
    let fifth: NoteClass?
    let seventh: NoteClass?

    init(from: PitchClass, to: PitchClass, context: WalkUpContext, weights: WalkUpWeights) {
        source = from
        target = to
        self.context = context
        self.weights = weights
        distance = WalkUp.signedDistance(from, to)
        dUp = from.semitones(to: to)
        maxNotes = WalkUp.maxNotes(beats: context.beats)
        departingTones = Set(context.departing.tones.pitchClasses)
        let tones = ChordToneSpelling(context.departing)
        third = tones.third
        fifth = tones.fifth
        seventh = tones.seventh
    }

    // MARK: Suppression and ranking

    func ranked() -> (candidates: [WalkUpCandidate], suppressed: WalkUpSuppression?) {
        // S1: the same note, or already a half step.
        if source == target || abs(distance) == 1 {
            return ([], .step)
        }
        // S4: a one-beat chord, or a fast song with two beats or fewer.
        if let beats = context.beats, beats <= 1 || ((context.tempo ?? 0) > 160 && beats <= 2) {
            return ([], .short)
        }
        // S2: a written stepwise line. "Nothing" first, the note between second (R162 Q1).
        if context.writtenLine, abs(distance) == 2 {
            return (writtenLine(), nil)
        }
        var seen: Set<[PitchClass]> = []
        let survivors = all()
            .sorted(by: Self.ranksBefore)
            .filter { seen.insert($0.notes.map(\.pitchClass)).inserted }
            .filter { $0.score >= weights.floor }
        guard !survivors.isEmpty else { return ([], .nothingFits) }
        // S6: Worship or a slow song, not into a section, only chromatic runs left.
        let restrained = context.genre == .worship || (context.tempo ?? 100) < 70
        if restrained, !context.intoSection, survivors.allSatisfy(\.isChromatic) {
            return ([], .restraint)
        }
        return (Array(survivors.prefix(weights.limit)), nil)
    }

    /// Higher score first; ties by kind declaration order, then lower first note. An
    /// octave pickup is always last.
    static func ranksBefore(_ left: WalkUpCandidate, _ right: WalkUpCandidate) -> Bool {
        let leftLast = left.kind == .octavePickup
        let rightLast = right.kind == .octavePickup
        if leftLast != rightLast {
            return rightLast
        }
        if left.score != right.score {
            return left.score > right.score
        }
        let order = WalkUpKind.allCases
        let leftIndex = order.firstIndex(of: left.kind) ?? 0
        let rightIndex = order.firstIndex(of: right.kind) ?? 0
        if leftIndex != rightIndex {
            return leftIndex < rightIndex
        }
        let leftFirst = left.notes.first?.pitchClass.rawValue ?? -1
        let rightFirst = right.notes.first?.pitchClass.rawValue ?? -1
        return leftFirst < rightFirst
    }

    /// Rule S2's two candidates: `hold`, then the note between.
    func writtenLine() -> [WalkUpCandidate] {
        let between = distance > 0 ? target.transposed(by: -1) : target.transposed(by: 1)
        let direction: WalkUpCandidate.Direction = distance > 0 ? .up : .down
        let scale = scale(melodic: distance > 0)
        let kind: WalkUpKind = if context.key != nil, scale.contains(between) {
            .diatonicNeighbour
        } else {
            distance > 0 ? .chromBelow : .chromAbove
        }
        let hold = Self.hold(
            score: weights.writtenLineHold,
            breakdown: [.writtenLine: weights.writtenLineHold],
        )
        var passing = make(
            kind,
            [between],
            offsets: [distance > 0 ? -1 : 1],
            direction: direction,
            scale: scale,
        )
        passing.score = weights.writtenLinePassing
        passing.breakdown = [.writtenLine: weights.writtenLinePassing]
        return [hold, passing]
    }

    static func hold(score: Double, breakdown: [WalkUpTerm: Double]) -> WalkUpCandidate {
        WalkUpCandidate(
            kind: .hold,
            notes: [],
            offsets: [],
            direction: .neither,
            chromatic: [],
            degrees: [],
            score: score,
            breakdown: breakdown,
        )
    }

    // MARK: The passing scale

    /// Minor key, walking up to i from a chord holding the raised 7: the raised 6 as well
    /// (melodic), so E -> Am walks F# G#.
    var raisesSixth: Bool {
        leadsToMinorTonic
    }

    /// Minor key, B is i and chord A holds the raised 7 (V, V7, vii°): the leading tone
    /// into i is the strongest approach (harmonic minor, research section 2).
    var leadsToMinorTonic: Bool {
        guard let key = context.key, targetIsMinorTonic else { return false }
        return departingTones.contains(key.tonic.pitchClass.transposed(by: 11))
    }

    /// B is i in a minor key.
    var targetIsMinorTonic: Bool {
        guard let key = context.key, key.mode == .minor else { return false }
        let arriving = context.arriving
        let intervals = Set(arriving.formula.intervals.map { $0 % 12 })
        return target == key.tonic.pitchClass && arriving.root.pitchClass == target
            && intervals.contains(3) && !intervals.contains(4)
    }

    /// The key's scale with every letter chord A alters replaced by A's tone (its third,
    /// fifth and seventh as spelled); with `melodic` and `raisesSixth`, the raised 6 too.
    /// No key: chord A's tones only.
    func scale(melodic: Bool) -> PassingScale {
        guard let key = context.key else {
            var notes: [PitchClass: NoteClass] = [:]
            let root = context.departing.root
            notes[root.pitchClass] = root
            for tone in [third, fifth, seventh].compactMap(\.self) {
                notes[tone.pitchClass] = tone
            }
            for pitch in departingTones where notes[pitch] == nil {
                notes[pitch] = KeySpelling.spell(pitch, in: nil)
            }
            return PassingScale(notes: notes)
        }
        var byLetter: [Letter: NoteClass] = [:]
        for note in key.scaleNotes {
            byLetter[note.letter] = note
        }
        for tone in [third, fifth, seventh].compactMap(\.self) {
            byLetter[tone.letter] = tone
        }
        if melodic, raisesSixth {
            let sixth = key.tonic.pitchClass.transposed(by: 9)
            let letter = Letter(rawValue: (key.tonic.letter.rawValue + 5) % 7) ?? .F
            byLetter[letter] = ChordToneSpelling.spell(letter: letter, pitch: sixth, key: key)
        }
        // In letter order, and chord A's tones win when two letters share a pitch class
        // (A's Ab over the scale's G#), so the spelling never depends on dictionary order.
        let tones = Set([third, fifth, seventh].compactMap(\.self))
        var notes: [PitchClass: NoteClass] = [:]
        for note in byLetter.sorted(by: { $0.key.rawValue < $1.key.rawValue }).map(\.value)
            where notes[note.pitchClass] == nil || tones.contains(note)
        {
            notes[note.pitchClass] = note
        }
        return PassingScale(notes: notes)
    }
}

/// A passing scale: pitch classes with their spelling.
struct PassingScale {
    var notes: [PitchClass: NoteClass]

    func contains(_ pitch: PitchClass) -> Bool {
        notes[pitch] != nil
    }
}

/// Chord A's third, fifth and seventh spelled from its root letter (`G#` in E, `C#` in A7).
struct ChordToneSpelling {
    var third: NoteClass?
    var fifth: NoteClass?
    var seventh: NoteClass?

    init(_ symbol: ChordSymbol) {
        let root = symbol.root
        let intervals = symbol.formula.intervals.filter { $0 < 12 }
        func tone(_ wanted: Set<Int>, letters: Int) -> NoteClass? {
            guard let interval = intervals.first(where: wanted.contains) else { return nil }
            let letter = Letter(rawValue: (root.letter.rawValue + letters) % 7) ?? .C
            return Self.spell(
                letter: letter,
                pitch: root.pitchClass.transposed(by: interval),
                key: nil,
            )
        }
        third = tone([3, 4], letters: 2)
        fifth = tone([7, 6, 8], letters: 4)
        seventh = tone([10, 11], letters: 6)
    }

    /// `pitch` on `letter` with at most one accidental, else the key's spelling.
    static func spell(letter: Letter, pitch: PitchClass, key: SongKey?) -> NoteClass {
        let natural = NoteClass(letter)
        switch natural.pitchClass.semitones(to: pitch) {
        case 0: return natural
        case 1: return NoteClass(letter, accidental: .sharp)
        case 11: return NoteClass(letter, accidental: .flat)
        default: return KeySpelling.spell(pitch, in: key)
        }
    }
}
