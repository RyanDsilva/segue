// P8-7c (docs/phases/8-workstreams/P8-7-time-model-and-fills.md section 11.3). The hard
// constraints a candidate must meet, its score as a sum of weighted terms (every term in the
// breakdown), and its encoding as chord-relative part events. Pure.

import Foundation
import Tonic

extension FillGenerator {
    // MARK: Hard constraints

    /// Monophonic, inside the span, no chromatic note on a strong beat but the last, no
    /// cross-relation with the sounding chord's third (R165, with R168's weak-beat chromatic
    /// run exemption), every bar starting inside the fill begins with a note, and playable at
    /// the tempo and feel.
    func fits(_ notes: [Note], template: FillTemplate) -> Bool {
        let fill = notes.filter { $0.at < 0 }
        guard let first = fill.first, first.at >= -departingLength,
              monophonic(notes, overhang: template.ownsLanding)
        else { return false }
        for (index, note) in fill.enumerated() {
            let chord = sounding(note.at)
            let tones = Set(span[chord].chord.tones.pitchClasses).union([span[chord].bass])
            let scale = passScale(chord, approach: note.approach)
            let chromatic = !tones.contains(note.pitch) && scale[note.pitch] == nil
            if index != fill.count - 1, isStrong(note.at), chromatic {
                return false
            }
            if crossRelates(note, index: index, of: fill, with: thirdOf(chord), tones: tones) {
                return false
            }
        }
        if template.id != "restPickup" {
            for downbeat in downbeats() where downbeat > first.at {
                guard fill.contains(where: { $0.at == downbeat }) else { return false }
            }
        }
        return playable(fill)
    }

    /// One note at a time, each at least a tick long; nothing before the landing sustains
    /// into it unless the template owns the landing (an anticipation, an overhang).
    func monophonic(_ notes: [Note], overhang: Bool) -> Bool {
        for (index, note) in notes.enumerated() {
            guard note.len >= 1 else { return false }
            if index + 1 < notes.count, note.at + note.len > notes[index + 1].at {
                return false
            }
            if note.at < 0, note.at + note.len > 0, !overhang {
                return false
            }
        }
        return true
    }

    /// The tempo allows it (no note shorter than `shortestNote` seconds), and Worship or a
    /// slow song keeps it to `restrainedNotes` notes (11.5).
    func playable(_ fill: [Note]) -> Bool {
        let tempo = context.tempo ?? 100
        let pulse = span[landingIndex - 1].meter.ticksPerPulse
        let seconds = 60 / (tempo * Double(pulse))
        let onsets = fill.map(\.at) + [0]
        let shortest = zip(onsets, onsets.dropFirst()).map { $1 - $0 }.min() ?? pulse
        if Double(shortest) * seconds < weights.shortestNote {
            return false
        }
        if restrained, fillNotes(fill) > weights.restrainedNotes {
            return false
        }
        return true
    }

    /// Worship, or a song below `slowTempo`.
    var restrained: Bool {
        context.genre == .worship || (context.tempo ?? 100) < weights.slowTempo
    }

    /// Fill notes, a root struck on its chord's onset not counted (the corpus `maxNotes`).
    func fillNotes(_ fill: [Note]) -> Int {
        fill.filter { note in
            !(note.isRoot && starts.contains(note.at))
        }.count
    }

    /// A note on the same letter a half step from `tone` that is not a chord tone, not the
    /// last note a half step from the landing, and not a weak-beat note inside a chromatic
    /// run into the landing (R165, R168).
    func crossRelates(
        _ note: Note,
        index: Int,
        of fill: [Note],
        with tone: NoteClass?,
        tones: Set<PitchClass>,
    ) -> Bool {
        guard let tone, !tones.contains(note.pitch) else { return false }
        // A pushed landing note sustains into its own chord.
        if note.pitch == target, note.at + note.len > 0 {
            return false
        }
        let isApproach = index == fill.count - 1
            && abs(WalkUp.signedDistance(note.pitch, target)) == 1
        if isApproach || note.chromaticRun && !isStrong(note.at) {
            return false
        }
        let gap = abs(WalkUp.signedDistance(note.pitch, tone.pitchClass))
        return gap == 1 && spelled(note, previous: index > 0 ? fill[index - 1] : nil).letter
            == tone.letter
    }

    func thirdOf(_ chord: Int) -> NoteClass? {
        ChordToneSpelling(span[chord].chord).third
    }

    /// Beat 1, and the middle pulse of an even simple bar of 4 or more; every pulse in a
    /// compound meter (11.3).
    func isStrong(_ tick: Int) -> Bool {
        let chord = sounding(tick)
        let meter = span[chord].meter
        let bar = meter.ticksPerBar
        let position = ((span[chord].onsetInBar + tick - starts[chord]) % bar + bar) % bar
        if position == 0 {
            return true
        }
        if meter.compound {
            return position.isMultiple(of: meter.ticksPerPulse)
        }
        return meter.pulses >= 4 && meter.pulses.isMultiple(of: 2) && position == bar / 2
    }

    /// Bar downbeats inside the departing chords, ticks from the landing.
    func downbeats() -> [Int] {
        var result: [Int] = []
        for index in 0 ..< landingIndex {
            let chord = span[index]
            let bar = chord.meter.ticksPerBar
            var tick = starts[index] + (bar - chord.onsetInBar % bar) % bar
            while tick < starts[index] + chord.length {
                result.append(tick)
                tick += bar
            }
        }
        return result
    }

    // MARK: Score and encoding

    func candidate(_ template: FillTemplate, notes: [Note]) -> FillCandidate? {
        let fill = notes.filter { $0.at < 0 }
        var terms: [FillTerm: Double] = [:]
        terms[.templatePrior] = templatePrior(template.corpusFamily)
        var previous: Note?
        var strong = 0
        var clashes = 0
        for (index, note) in fill.enumerated() {
            let chord = sounding(note.at)
            let tones = Set(span[chord].chord.tones.pitchClasses).union([span[chord].bass])
            if isStrong(note.at), tones.contains(note.pitch) {
                strong += 1
            }
            let symbol = ChordToneSpelling(span[chord].chord)
            if crossRelates(note, index: index, of: fill, with: symbol.fifth, tones: tones)
                || crossRelates(note, index: index, of: fill, with: symbol.seventh, tones: tones)
            {
                clashes += 1
            }
            previous = note
        }
        terms[.strongBeatTone] = Double(strong) * weights.strongBeatTone
        terms[.clash] = Double(clashes) * weights.clash
        terms[.resolution] = resolution(previous)
        terms[.density] = density(fill)
        let leaps = zip(notes, notes.dropFirst()).count { abs($1.midi - $0.midi) > 7 }
        terms[.contour] = Double(leaps) * weights.contour
        terms[.range] = Double(notes.count(where: \.folded)) * weights.range
        terms[.keyChange] = (keyChangeEnding(previous) ? weights.keyChange : 0)
            + (arpeggiatesDominant(fill) ? weights.keyChangeArpeggio : 0)
        terms[.downbeat] = 0
        terms[.walkUpAgreement] = agreesWithWalkUp(fill) ? weights.walkUpAgreement : 0
        let breakdown = terms.filter { $0.key == .templatePrior || $0.value != 0 }
        guard let encoded = encode(notes) else { return nil }
        return FillCandidate(
            family: template.family,
            template: template.id,
            events: encoded.events,
            names: encoded.names,
            score: FillTerm.sum(breakdown),
            breakdown: breakdown,
            corpus: template.corpus,
        )
    }

    /// `log(1 + count) / log(1 + most) * priorScale` for the feel (all feels when unknown).
    func templatePrior(_ family: String) -> Double {
        let counts = templates.counts
        func count(_ family: String) -> Int {
            guard let genre = context.genre else {
                return counts[family]?.values.reduce(0, +) ?? 0
            }
            return counts[family]?[genre] ?? 0
        }
        let most = counts.keys.map(count).max() ?? 0
        guard most > 0 else { return 0 }
        return log(1 + Double(count(family))) / log(1 + Double(most)) * weights.priorScale
    }

    /// The last fill note a half step from the landing bass, a whole step, or its fifth.
    func resolution(_ last: Note?) -> Double {
        guard let last else { return 0 }
        switch abs(WalkUp.signedDistance(last.pitch, target)) {
        case 1: return weights.resolutionHalfStep
        case 2: return weights.resolutionWholeStep
        default:
            let fifth = span[landingIndex].chord.root.pitchClass.transposed(by: 7)
            return last.pitch == fifth ? weights.resolutionFifth : 0
        }
    }

    /// Notes per pulse against what the tempo and feel make comfortable; a Rock feel likes
    /// two or more.
    func density(_ fill: [Note]) -> Double {
        guard let first = fill.first else { return 0 }
        let pulse = Double(span[landingIndex - 1].meter.ticksPerPulse)
        let pulses = max(1, Double(-first.at) / pulse)
        let rate = Double(fill.count) / pulses
        let tempo = context.tempo ?? 100
        let comfortable = tempo > weights.fastTempo ? weights.densityFast
            : restrained ? weights.densityRestrained : weights.densityMid
        var fit = max(0, rate - comfortable) * weights.densityOver
        if context.genre == .rock, rate >= 2 {
            fit += weights.densityRock
        }
        return fit
    }

    /// Into a new key: the last note is the landing's dominant, a half step from the new
    /// root, or the old root (11.2).
    func keyChangeEnding(_ last: Note?) -> Bool {
        guard let lift, let last else { return false }
        let fifth = span[landingIndex].chord.root.pitchClass.transposed(by: 7)
        let old = lift.newKey.tonic.pitchClass.transposed(by: -lift.semitones)
        return last.pitch == fifth || abs(WalkUp.signedDistance(last.pitch, target)) == 1
            || last.pitch == old
    }

    /// A prepared lift's V' arpeggio: every fill note a tone of V', the last its third (the new
    /// key's leading tone, R168).
    func arpeggiatesDominant(_ fill: [Note]) -> Bool {
        guard lift?.prepared == true, let last = fill.last else { return false }
        let chord = span[landingIndex - 1].chord
        let tones = Set(chord.tones.pitchClasses)
        return fill.allSatisfy { tones.contains($0.pitch) }
            && last.pitch == Self.tone(.third, of: chord)
    }

    /// The approach notes equal the walk-up the chart shows for the last change.
    func agreesWithWalkUp(_ fill: [Note]) -> Bool {
        guard let chart = chartWalkUp, !chart.isEmpty else { return false }
        let approach = fill.suffix(chart.count)
        guard approach.count == chart.count, approach.allSatisfy(\.approach) else { return false }
        let pitches = approach.map(\.pitch)
        return pitches.map { WalkUp.signedDistance(target, $0) } == chart
            || pitches.map { -$0.semitones(to: target) } == chart
            || pitches.map { target.semitones(to: $0) } == chart
    }

    /// Chord-relative events and spelled names; nil when a note sits more than two octaves
    /// from its chord's placed bass.
    func encode(_ notes: [Note]) -> (events: [PartEvent], names: [NoteClass])? {
        var events: [PartEvent] = []
        var names: [NoteClass] = []
        var previous: Note?
        for note in notes {
            let chord = note.at >= 0 ? landingIndex : sounding(note.at)
            let semitones = note.midi - span[chord].placed
            guard (-24 ... 35).contains(semitones) else { return nil }
            events.append(PartEvent.relative(
                chord: chord,
                at: note.at - starts[chord],
                len: note.len,
                semitones: semitones,
                articulations: note.articulations,
            ))
            names.append(spelled(note, previous: previous))
            previous = note
        }
        return (events, names)
    }

    /// Section 9.2: chord tones as the chord spells them, passing tones as the scale does,
    /// else sharp ascending and flat descending; across a lift in the new key (R168).
    func spelled(_ note: Note, previous: Note?) -> NoteClass {
        let chord = note.at >= 0 ? landingIndex : sounding(note.at)
        let ascending: Bool? = previous.map { note.midi != $0.midi ? note.midi > $0.midi : true }
            ?? (note.direction == 0 ? nil : note.direction > 0)
        return FillSpelling.spell(
            note.pitch,
            over: span[chord].chord,
            key: key(chord, approach: note.approach),
            mode: context.mode,
            ascending: ascending,
        )
    }
}
