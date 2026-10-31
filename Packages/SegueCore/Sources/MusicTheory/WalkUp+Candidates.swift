// P8-4b (docs/phases/8-workstreams/P8-4-bass.md section 8.3). Generating walk-up candidates
// [R3.3], and building and scoring them [R3.4].

import Tonic

extension WalkUpMove {
    // MARK: Generation

    /// Every candidate the rules generate, scored, unranked and unfiltered; a candidate
    /// clashing with chord A's third, or containing `source` or `target`, is left out.
    func all() -> [WalkUpCandidate] {
        // Tritone: no idiomatic walk, a half step below only.
        let generated = distance == 6
            ? [single(.chromBelow, target.transposed(by: -1), direction: .up)]
            : scaleCandidates() + chromaticCandidates() + chordCandidates()
        return generated.compactMap { candidate in
            var candidate = candidate
            let pitches = candidate.notes.map(\.pitchClass)
            guard !pitches.isEmpty, !pitches.contains(target),
                  candidate.kind == .octavePickup || !pitches.contains(source),
                  !clashes(candidate.notes, with: third)
            else { return nil }
            score(&candidate)
            return candidate
        }
    }

    /// Scale walks both ways, the scale walk with a half step, and the neighbour (key only).
    func scaleCandidates() -> [WalkUpCandidate] {
        guard context.key != nil else { return [] }
        var result: [WalkUpCandidate] = []
        for direction in [WalkUpCandidate.Direction.up, .down] {
            let walks = scaleWalks(direction)
            result += walks
            if direction == .up, let walk = walks.first, let chrom = scaleChrom(from: walk) {
                result.append(chrom)
            }
        }
        if let neighbour = diatonicNeighbour() {
            result.append(neighbour)
        }
        return result
    }

    /// A half step below; above when descending or in a Rock or Country feel; two half
    /// steps from above in those feels.
    func chromaticCandidates() -> [WalkUpCandidate] {
        var result = [single(.chromBelow, target.transposed(by: -1), direction: .up)]
        let edgy = [.rock, .country].contains(context.genre)
        if distance < 0 || edgy {
            result.append(single(.chromAbove, target.transposed(by: 1), direction: .down))
        }
        if context.key != nil, edgy, maxNotes >= 2 {
            result.append(make(
                .doubleChromAbove,
                [target.transposed(by: 2), target.transposed(by: 1)],
                offsets: [2, 1],
                direction: .down,
                scale: scale(melodic: false),
            ))
        }
        return result
    }

    /// The fifth of B (not under a slash chord) and A's octave into a section.
    func chordCandidates() -> [WalkUpCandidate] {
        var result: [WalkUpCandidate] = []
        let arriving = context.arriving
        if arriving.bass == nil || arriving.bass?.pitchClass == arriving.root.pitchClass {
            result.append(make(
                .fifth,
                [target.transposed(by: 7)],
                offsets: [-5],
                direction: .neither,
                scale: scale(melodic: false),
            ))
        }
        if context.key != nil, context.intoSection {
            result.append(make(
                .octavePickup,
                [source],
                offsets: [-distance],
                direction: .neither,
                scale: scale(melodic: false),
            ))
        }
        return result
    }

    /// One note, offset from `target`.
    func single(
        _ kind: WalkUpKind,
        _ pitch: PitchClass,
        direction: WalkUpCandidate.Direction,
    ) -> WalkUpCandidate {
        let offset = WalkUp.signedDistance(target, pitch)
        return make(
            kind,
            [pitch],
            offsets: [offset],
            direction: direction,
            scale: scale(melodic: direction == .up),
        )
    }

    /// The passing-scale notes strictly between `source` and `target` in `direction`, the ones
    /// nearest `target`, at most `maxNotes` (2 ... 7 semitones that way). A Bollywood feel walking
    /// up to a minor tonic also gets the harmonic form.
    func scaleWalks(_ direction: WalkUpCandidate.Direction) -> [WalkUpCandidate] {
        let span = direction == .up ? dUp : 12 - dUp
        guard (2 ... 7).contains(span), maxNotes > 0 else { return [] }
        var scales = [scale(melodic: direction == .up)]
        if direction == .up, context.genre == .bollywood, raisesSixth {
            scales.append(scale(melodic: false))
        }
        return scales.compactMap { scale in
            let step = direction == .up ? 1 : -1
            let between = (1 ..< span).map { source.transposed(by: $0 * step) }
                .filter(scale.contains)
            let notes = Array(between.suffix(maxNotes))
            guard let last = notes.last else { return nil }
            let gap = direction == .up ? last.semitones(to: target) : target.semitones(to: last)
            guard gap <= 2 else { return nil }
            return make(
                .scaleWalk,
                notes,
                offsets: notes
                    .map { direction == .up ? -$0.semitones(to: target) : target.semitones(to: $0)
                    },
                direction: direction,
                scale: scale,
            )
        }
    }

    /// `scaleWalk` up with its last note replaced by `target - 1`, when its last step into `target`
    /// is
    /// a whole step (3-#4-5).
    func scaleChrom(from walk: WalkUpCandidate) -> WalkUpCandidate? {
        guard walk.direction == .up, walk.offsets.last == -2 else { return nil }
        var offsets = walk.offsets
        offsets[offsets.count - 1] = -1
        return make(
            .scaleChrom,
            offsets.map { target.transposed(by: $0) },
            offsets: offsets,
            direction: .up,
            scale: scale(melodic: true),
        )
    }

    /// The one passing-scale note next to `target` on the side `source` approaches from.
    func diatonicNeighbour() -> WalkUpCandidate? {
        let up = distance > 0
        let scale = scale(melodic: up)
        let steps = up ? [-1, -2] : [1, 2]
        guard let offset = steps.first(where: { scale.contains(target.transposed(by: $0)) }) else {
            return nil
        }
        return make(
            .diatonicNeighbour,
            [target.transposed(by: offset)],
            offsets: [offset],
            direction: up ? .up : .down,
            scale: scale,
        )
    }

    // MARK: Building and scoring

    func make(
        _ kind: WalkUpKind,
        _ pitches: [PitchClass],
        offsets: [Int],
        direction: WalkUpCandidate.Direction,
        scale: PassingScale,
    ) -> WalkUpCandidate {
        let notes = pitches.map { pitch -> NoteClass in
            if let spelled = scale.notes[pitch] {
                return spelled
            }
            let (sharp, flat) = NoteClass.spellings(of: pitch)
            if sharp == flat {
                return sharp
            }
            switch direction {
            case .up: return sharp
            case .down: return flat
            case .neither: return KeySpelling.spell(pitch, in: context.key)
            }
        }
        return WalkUpCandidate(
            kind: kind,
            notes: notes,
            offsets: offsets,
            direction: direction,
            chromatic: pitches.map { !scale.contains($0) },
            degrees: context.key.map { key in
                pitches.map { Nashville.degree(of: $0, in: key) }
            } ?? [],
            score: 0,
            breakdown: [:],
        )
    }

    /// Whether a note other than the target-side approach (the last note, a half step from
    /// `target`) cross-relates with `tone`: the same letter a half step away, so it contradicts
    /// chord A (G over E major's G#, C over A7's C#). A neighbour on another letter (B under
    /// Am's C) is a passing tone, not a clash.
    ///
    /// R168: a note inside a stepwise chromatic run into the target, on a weak beat, is
    /// exempt (E Eb into D over Cm in a three-beat bar).
    func clashes(_ notes: [NoteClass], with tone: NoteClass?) -> Bool {
        guard let tone else { return false }
        return notes.enumerated().contains { index, note in
            let pitch = note.pitchClass
            let isLast = index == notes.count - 1
            let approach = isLast && abs(WalkUp.signedDistance(pitch, target)) == 1
            let gap = abs(WalkUp.signedDistance(pitch, tone.pitchClass))
            return !approach && !departingTones.contains(pitch) && gap == 1
                && note.letter == tone.letter && !exempt(index, of: notes)
        }
    }

    /// Note `index` sits inside a monotonic run of half steps that ends on the target, on a
    /// weak pulse: the walk-up's notes fill the last pulses of chord A (unknown beats count
    /// as a four-beat bar), and beat 1 and the middle of a four-beat bar are strong.
    func exempt(_ index: Int, of notes: [NoteClass]) -> Bool {
        let pitches = notes.map(\.pitchClass) + [target]
        let steps = zip(pitches, pitches.dropFirst()).map { WalkUp.signedDistance($0, $1) }
        guard let step = steps.last, abs(step) == 1,
              steps[index...].allSatisfy({ $0 == step })
        else { return false }
        let beats = context.beats ?? 4
        let pulse = beats - notes.count + index
        let bar = beats.isMultiple(of: 3) && beats < 6 ? 3 : 4
        return !pulse.isMultiple(of: bar) && !(bar == 4 && pulse % bar == 2)
    }

    func score(_ candidate: inout WalkUpCandidate) {
        let pitches = candidate.notes.map(\.pitchClass)
        var terms: [WalkUpTerm: Double] = [:]
        terms[.genrePrior] = weights.prior(candidate.kind, genre: context.genre)
        if clashes(candidate.notes, with: fifth) || clashes(candidate.notes, with: seventh) {
            terms[.clash] = weights.clash
        }
        terms[.resolution] = resolution(candidate.kind, pitches)
        terms[.direction] = directionFit(candidate.direction)
        terms[.length] = lengthFit(pitches)
        terms[.minorTonic] = minorTonic(pitches)
        if context.intoSection, [.scaleWalk, .scaleChrom].contains(candidate.kind) {
            terms[.intoSection] = weights.intoSection
        }
        candidate.breakdown = terms.filter { $0.key == .genrePrior || $0.value != 0 }
        candidate.score = candidate.breakdown.values.reduce(0, +)
    }

    /// The last note a half step (or whole step) from the target, or the fifth.
    func resolution(_ kind: WalkUpKind, _ pitches: [PitchClass]) -> Double {
        if kind == .fifth {
            return weights.resolutionFifth
        }
        guard let last = pitches.last else { return 0 }
        switch abs(WalkUp.signedDistance(last, target)) {
        case 1: return weights.resolutionHalfStep
        case 2: return weights.resolutionWholeStep
        default: return 0
        }
    }

    /// Up into a chorus, down into a verse; with no section energy, the short way. Country
    /// adds the walk up a fourth.
    func directionFit(_ direction: WalkUpCandidate.Direction) -> Double {
        guard direction != .neither else { return 0 }
        let up = direction == .up
        var fit = 0.0
        if let energyUp = context.energyUp {
            fit += up == energyUp ? weights.directionEnergy : 0
        } else if up == (distance > 0) {
            fit += weights.directionShortest
        }
        if context.genre == .country, up, dUp == 5 {
            fit += weights.directionCountryFourth
        }
        return fit
    }

    /// Notes beyond `maxNotes` cost; exactly filling a 4-beat chord's slots earns a little.
    func lengthFit(_ pitches: [PitchClass]) -> Double {
        var fit = 0.0
        if pitches.count > maxNotes {
            fit += weights.lengthOver * Double(pitches.count - maxNotes)
        }
        if let beats = context.beats, beats >= 4, pitches.count == maxNotes {
            fit += weights.lengthExact
        }
        return fit
    }

    /// Ending on the leading tone into i from a chord that holds it, plus the feel's form:
    /// `F G#` (harmonic) for Bollywood, `F# G#` (melodic) otherwise.
    func minorTonic(_ pitches: [PitchClass]) -> Double {
        guard leadsToMinorTonic, let last = pitches.last, last == target.transposed(by: -1)
        else { return 0 }
        guard pitches.count >= 2 else { return weights.minorTonic }
        let before = pitches[pitches.count - 2]
        let harmonic = before == target.transposed(by: 8)
        let melodic = before == target.transposed(by: 9)
        let form = context.genre == .bollywood ? harmonic : melodic
        return weights.minorTonic + (form ? weights.minorTonicForm : 0)
    }
}
