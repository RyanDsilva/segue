// P8-7c (docs/phases/8-workstreams/P8-7-time-model-and-fills.md sections 11.2-11.3, R165,
// R168, R169). Realising each template over a span, the hard constraints, the score with its
// breakdown, and one candidate per family. Pure and deterministic: no randomness, no clock.

import Tonic

/// A span with its context: realises, checks, scores and ranks every template.
struct FillGenerator {
    let context: FillContext
    let weights: FillWeights
    let templates: FillTemplates
    let span: [FillSpanChord]
    /// Each chord's onset, ticks from the landing onset (negative before it; the landing 0).
    let starts: [Int]
    let departingLength: Int
    let landingIndex: Int
    let target: PitchClass
    let lift: Lift?
    /// The walk-up the chart would show for the last change (section 11.3 `walkUpAgreement`).
    let chartWalkUp: [Int]?

    /// The landing is in a new key.
    struct Lift {
        var newKey: SongKey
        /// Semitones up from the old tonic, 0 ... 11.
        var semitones: Int
        /// The last departing chord is the new key's V (V').
        var prepared: Bool
        /// The last departing chord's tones all sit in the new key (V', ii', a pivot).
        var lastFitsNewKey: Bool
    }

    /// One placed note before encoding.
    struct Note {
        var at: Int
        var len: Int
        var pitch: PitchClass
        var midi = 0
        var articulations: Set<Articulation>
        /// Resolved as an approach into the landing (spelled in the landing's key).
        var approach = false
        /// Placement direction from the note before: up, down or nearest.
        var direction = 0
        var isOctave = false
        var isRoot = false
        var isLanding = false
        var folded = false
        /// Inside a stepwise chromatic run into the landing (R168 exemption).
        var chromaticRun = false
        /// A slot its line did not need (a short chromatic line), removed before placing.
        var dropped = false
    }

    init?(context: FillContext, weights: FillWeights, templates: FillTemplates) {
        guard context.span.count >= 2 else { return nil }
        self.context = context
        self.weights = weights
        self.templates = templates
        span = context.span
        landingIndex = span.count - 1
        var starts = Array(repeating: 0, count: span.count)
        var tick = 0
        for index in stride(from: landingIndex - 1, through: 0, by: -1) {
            tick -= max(1, span[index].length)
            starts[index] = tick
        }
        self.starts = starts
        departingLength = -tick
        let landing = span[landingIndex]
        target = landing.bass
        let last = span[landingIndex - 1]
        if let new = landing.key, let old = last.key, new != old {
            let semitones = old.tonic.pitchClass.semitones(to: new.tonic.pitchClass)
            let fifth = new.tonic.pitchClass.transposed(by: 7)
            let scale = Set(FillSpelling.scaleNotes(new).map(\.pitchClass))
            lift = Lift(
                newKey: new,
                semitones: semitones,
                prepared: last.chord.root.pitchClass == fifth,
                lastFitsNewKey: last.chord.tones.pitchClasses.allSatisfy(scale.contains),
            )
        } else {
            lift = nil
        }
        let lastPulses = last.estimated ? nil : max(1, last.length / last.meter.ticksPerPulse)
        let chart = WalkUp.candidates(
            from: last.bass,
            to: landing.bass,
            context: Self.walkContext(context, from: landingIndex - 1, beats: lastPulses),
        ).first { $0.kind != .hold }
        chartWalkUp = chart?.offsets
    }

    // MARK: Ranking

    /// The best candidate per corpus pattern family plus hold, best first, at most
    /// `weights.limit` (R170: diversity is per corpus family, so the four shown and "More"
    /// are the five best-fitting different patterns).
    func ranked() -> [FillCandidate] {
        var seen: Set<String> = []
        var list: [FillCandidate] = []
        for candidate in all() {
            let family = templates.template(candidate.template)?.corpusFamily ?? candidate.template
            if seen.insert(family).inserted {
                list.append(candidate)
            }
        }
        list.append(hold(others: list.map(\.score)))
        return Array(list.sorted(by: ranksBefore).prefix(weights.limit))
    }

    /// Every template's candidate that fits, best first (the hold candidate excluded).
    func all() -> [FillCandidate] {
        templates.templates.compactMap(realise).sorted(by: ranksBefore)
    }

    /// Higher score first; ties: hold, then family order, then template order, then the
    /// lower first note.
    func ranksBefore(_ left: FillCandidate, _ right: FillCandidate) -> Bool {
        if left.score != right.score {
            return left.score > right.score
        }
        if left.isHold != right.isHold {
            return left.isHold
        }
        let families = FillFamily.allCases
        let leftFamily = left.family.flatMap { families.firstIndex(of: $0) } ?? -1
        let rightFamily = right.family.flatMap { families.firstIndex(of: $0) } ?? -1
        if leftFamily != rightFamily {
            return leftFamily < rightFamily
        }
        let ids = templates.templates.map(\.id)
        let leftTemplate = ids.firstIndex(of: left.template) ?? 0
        let rightTemplate = ids.firstIndex(of: right.template) ?? 0
        if leftTemplate != rightTemplate {
            return leftTemplate < rightTemplate
        }
        return (left.events.first?.semitones ?? 0) < (right.events.first?.semitones ?? 0)
    }

    /// "No fill" (R168): first for a written stepwise line (bVI-bVII-i too) and slow
    /// Worship, and at least second at a key change.
    func hold(others: [Double]) -> FillCandidate {
        var terms: [FillTerm: Double] = [:]
        let prior = templatePrior(FillCandidate.holdTemplate)
        terms[.templatePrior] = prior
        let basses = span.map(\.bass)
        let stepwise = basses.count >= 3 && Self.stepwise(basses)
        let restrained = context.genre == .worship && (context.tempo ?? 100) < weights.slowTempo
        var restraint = 0.0
        if stepwise || restrained {
            restraint = (others.first ?? 0) - prior + weights.holdFirst
        } else if lift != nil {
            let second = others.count >= 2 ? others[1] : (others.first ?? 0)
            restraint = max(weights.holdKeyChange, second - prior)
        }
        if restraint != 0 {
            terms[.restraint] = restraint
        }
        return FillCandidate(
            family: nil,
            template: FillCandidate.holdTemplate,
            events: [],
            names: [],
            score: FillTerm.sum(terms),
            breakdown: terms,
            corpus: [],
        )
    }

    /// Every move 1-2 semitones in one direction (a written line, rule S2).
    static func stepwise(_ basses: [PitchClass]) -> Bool {
        let moves = zip(basses, basses.dropFirst()).map { WalkUp.signedDistance($0, $1) }
        return moves.allSatisfy { (1 ... 2).contains($0) }
            || moves.allSatisfy { (-2 ... -1).contains($0) }
    }
}

extension FillGenerator {
    // MARK: Realising a template

    /// The template's condition holds for this span.
    func offers(_ template: FillTemplate) -> Bool {
        let last = span[landingIndex - 1]
        if template.simpleOnly, last.meter.compound {
            return false
        }
        return switch template.condition {
        case .always: true
        case .preparedLift: lift?.prepared == true
        case .bollywood: context.genre == .bollywood
        case .sameKey: lift == nil
        case .change: last.chord != span[landingIndex].chord
        }
    }

    func realise(_ template: FillTemplate) -> FillCandidate? {
        guard offers(template), var notes = template.coversSpan ? walk() : slots(template)
        else { return nil }
        if !template.ownsLanding {
            if template.leads {
                lead(&notes)
            }
            notes.append(Note(
                at: 0,
                len: min(span[landingIndex].length, span[landingIndex].meter.ticksPerPulse),
                pitch: target,
                articulations: [],
                approach: true,
                isLanding: true,
            ))
        }
        place(&notes)
        markChromaticRun(&notes)
        guard fits(notes, template: template) else { return nil }
        return candidate(template, notes: notes)
    }

    /// The template's slots before the landing, pitched; nil when they do not fit the span.
    func slots(_ template: FillTemplate) -> [Note]? {
        let last = span[landingIndex - 1]
        let pulse = last.meter.ticksPerPulse
        let bar = last.meter.ticksPerBar
        let slots = template.slots.filter { slot in
            (!slot.compoundOnly || last.meter.compound)
                && !(slot.optional && slot.at.ticks(pulse: pulse, bar: bar) <= -departingLength)
        }
        var notes = slots.map { slot in
            Note(
                at: slot.at.ticks(pulse: pulse, bar: bar),
                len: slot.len.ticks(pulse: pulse, bar: bar),
                pitch: target,
                articulations: slot.articulations,
            )
        }
        guard let first = notes.first, first.at >= -departingLength else { return nil }
        // A held note (the root re-struck on the bar line) lasts until the next one.
        for index in notes.indices.dropLast() {
            notes[index].len = min(notes[index].len, notes[index + 1].at - notes[index].at)
        }
        var index = 0
        while index < slots.count {
            let pitch = slots[index].pitch
            var end = index + 1
            if let group = pitch.group {
                while end < slots.count, slots[end].pitch.group == group {
                    end += 1
                }
            }
            guard resolve(pitch, notes: &notes, range: index ..< end) else { return nil }
            index = end
        }
        notes.removeAll(where: \.dropped)
        return notes
    }

    /// A slot's or group's pitches and how they are placed.
    struct Line {
        var pitches: [PitchClass]
        /// After the first note: up (1), down (-1) or nearest (0).
        var direction = 0
        /// The first note's own direction from the note before.
        var lead = 0
        var approach = false
        var isRoot = false
        var isOctave = false
    }

    /// Pitches `notes[range]` for one slot or one group of slots.
    func resolve(_ pitch: FillPitch, notes: inout [Note], range: Range<Int>) -> Bool {
        let chord = sounding(notes[range.lowerBound].at)
        guard let line = toneLine(pitch, chord: chord) ?? runLine(
            pitch,
            chord: chord,
            count: range.count,
        ), !line.pitches.isEmpty, line.pitches.count <= range.count,
        line.pitches.count == range.count || pitch == .chromaticLine
        else { return false }
        // A shorter line takes the last slots; the ones before it are dropped.
        let first = range.upperBound - line.pitches.count
        for index in range.lowerBound ..< first {
            notes[index].dropped = true
        }
        for (offset, index) in (first ..< range.upperBound).enumerated() {
            notes[index].pitch = line.pitches[offset]
            notes[index].direction = offset == 0 ? line.lead : line.direction
            notes[index].approach = line.approach
        }
        notes[first].isRoot = line.isRoot
        notes[first].isOctave = line.isOctave
        return true
    }

    /// One-note functions: chord tones, the dominant, the landing and its steps, the half step
    /// below, a slide's start. nil for groups (and for a function the chord cannot supply, as
    /// an empty line).
    func toneLine(_ pitch: FillPitch, chord: Int) -> Line? {
        let symbol = span[chord].chord
        let bass = span[chord].bass
        switch pitch {
        case .root:
            return Line(pitches: [bass], isRoot: true)
        case .octave:
            return Line(pitches: [bass], isOctave: true)
        case .fifth, .ninth, .seventh, .third:
            guard let tone = Self.tone(pitch, of: symbol) else { return Line(pitches: []) }
            return Line(pitches: [tone], isOctave: tone == bass && pitch == .seventh)
        case .dominant:
            let fifth = span[landingIndex].chord.root.pitchClass.transposed(by: 7)
            return Line(pitches: [fifth], approach: true)
        case .target:
            return Line(pitches: [target], approach: true)
        case let .targetStep(steps):
            return targetStepLine(steps)
        case .halfStepBelow:
            return Line(pitches: [target.transposed(by: -1)], lead: 1, approach: true)
        case .slideStart:
            return slideLine(from: chord)
        case .approach, .chromaticLine, .leadIn, .pentatonicDown, .pentatonicUp, .scaleDown,
             .scaleToward, .scaleUp:
            return nil
        }
    }

    /// `steps` passing-scale steps above the landing bass (a tihai cell).
    func targetStepLine(_ steps: Int) -> Line {
        let scale = passScale(landingIndex, approach: true)
        let above = (1 ... 11).map { target.transposed(by: $0) }.filter { scale[$0] != nil }
        guard above.count >= steps else { return Line(pitches: []) }
        return Line(pitches: [above[steps - 1]], approach: true)
    }

    /// Where a slide into the landing starts: the departing bass within a whole step of the
    /// landing (its octave on the same note), else the single approach note.
    func slideLine(from chord: Int) -> Line {
        let bass = span[chord].bass
        let distance = WalkUp.signedDistance(bass, target)
        if distance == 0 {
            return Line(pitches: [bass], isOctave: true)
        }
        if abs(distance) <= 2 {
            return Line(pitches: [bass], approach: true)
        }
        guard let line = approachLine(count: 1, from: chord) else { return Line(pitches: []) }
        return Line(pitches: line.pitches, lead: line.direction, approach: true)
    }

    /// Group functions: the walk-up approach, scale runs and pentatonic runs.
    func runLine(_ pitch: FillPitch, chord: Int, count: Int) -> Line? {
        switch pitch {
        case .approach:
            guard let line = approachLine(count: count, from: chord) else { return nil }
            return Line(pitches: line.pitches, direction: line.direction, approach: true)
        case .leadIn:
            let line = leadInLine(count: count, from: chord)
            return Line(pitches: line, direction: 1, approach: true)
        case .chromaticLine:
            let bass = span[chord].bass
            let side = approachSide(from: bass)
            let distance = abs(WalkUp.signedDistance(bass, target))
            let steps = (2 ... count).contains(distance) && WalkUp
                .signedDistance(bass, target) * side > 0 ? distance - 1 : count - 1
            let line = [bass] + (1 ... steps).reversed().map { target.transposed(by: -side * $0) }
            return Line(pitches: line, direction: side, isRoot: true)
        case .scaleDown, .scaleToward, .scaleUp:
            // A scale run toward the landing takes the shorter way (up on a tritone).
            let up = pitch == .scaleToward
                ? WalkUp.signedDistance(span[chord].bass, target) >= 0 : pitch == .scaleUp
            let scale = passScale(chord, approach: true)
            var run = (1 ... 11).map { target.transposed(by: up ? -$0 : $0) }
                .filter { scale[$0] != nil }.prefix(count).reversed().map(\.self)
            if up, let last = run.last, last.semitones(to: target) == 2 {
                run[run.count - 1] = target.transposed(by: -1)
            }
            return Line(pitches: run, direction: up ? 1 : -1, approach: true)
        case .pentatonicDown:
            // Down the sounding chord's pentatonic onto its tone nearest the landing (within
            // two semitones, above first), so the run itself leads in.
            let tones = pentatonic(chord)
            let near = [1, 2, -1, -2].map { target.transposed(by: $0) }.first(where: tones.contains)
            let end = near ?? target
            let above = (0 ... 11).map { end.transposed(by: $0) }.filter(tones.contains)
            return Line(pitches: Array(above.prefix(count).reversed()), direction: -1, lead: -1)
        case .pentatonicUp:
            let tones = pentatonic(chord)
            let bass = span[chord].bass
            let up = (1 ... 11).map { bass.transposed(by: $0) }.filter(tones.contains)
            return Line(pitches: Array(up.prefix(count)), direction: 1, lead: 1)
        default:
            return nil
        }
    }

    /// The walk template: over every departing chord the root on its onset and each bar line,
    /// then the walk-up into the next chord on its last pulses (one note per pulse).
    func walk() -> [Note]? {
        var notes: [Note] = []
        for index in 0 ..< landingIndex {
            let chord = span[index]
            let pulse = chord.meter.ticksPerPulse
            let pulses = chord.length / pulse
            let start = starts[index]
            var approach: (pitches: [PitchClass], direction: Int) = ([], 0)
            if pulses >= 2,
               let line = walkUp(from: index, beats: pulses, count: nil)
            {
                approach = line
            }
            let walkStart = start + chord.length - approach.pitches.count * pulse
            var onsets = [start]
            let bar = chord.meter.ticksPerBar
            var downbeat = start + (bar - chord.onsetInBar % bar) % bar
            while downbeat < walkStart {
                if downbeat > start {
                    onsets.append(downbeat)
                }
                downbeat += bar
            }
            for (offset, onset) in onsets.enumerated() {
                let end = offset + 1 < onsets.count ? onsets[offset + 1] : walkStart
                var note = Note(at: onset, len: end - onset, pitch: chord.bass, articulations: [])
                note.isRoot = true
                note.direction = offset == 0 ? (notes.last?.direction ?? 0) : 0
                notes.append(note)
            }
            for (offset, pitch) in approach.pitches.enumerated() {
                var note = Note(
                    at: walkStart + offset * pulse,
                    len: pulse,
                    pitch: pitch,
                    articulations: [],
                )
                note.direction = approach.direction
                note.approach = index == landingIndex - 1
                notes.append(note)
            }
        }
        // A walk that never walks (every chord too short) is the hold candidate.
        return notes.contains { !$0.isRoot } ? notes : nil
    }

    /// The final fill note leads into the landing (within two semitones of its bass, or its
    /// fifth); otherwise it becomes the single approach note.
    func lead(_ notes: inout [Note]) {
        guard let index = notes.indices.last(where: { notes[$0].at < 0 }) else { return }
        let pitch = notes[index].pitch
        let fifth = span[landingIndex].chord.root.pitchClass.transposed(by: 7)
        guard abs(WalkUp.signedDistance(pitch, target)) > 2, pitch != fifth else { return }
        let chord = sounding(notes[index].at)
        if let line = approachLine(count: 1, from: chord) {
            notes[index].pitch = line.pitches[0]
            notes[index].approach = true
            notes[index].isOctave = false
            notes[index].isRoot = false
            notes[index].direction = 0
        }
    }
}
