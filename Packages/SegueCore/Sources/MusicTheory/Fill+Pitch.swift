// P8-7c (docs/phases/8-workstreams/P8-7-time-model-and-fills.md sections 11.2, 9.2, R168,
// R169). Where a fill's notes come from (the walk-up approach, the key a note is planned in,
// pentatonics) and how they are placed on the instrument. Pure.

import Tonic

extension FillGenerator {
    // MARK: Pitch sources

    /// The approach into the landing over `count` slots (section 11.2): the walk-up
    /// candidates in rank order, the first with exactly `count` notes; else the best shorter
    /// one led in by the sounding chord's octave; a +1 lift offers the old root first.
    func approachLine(count: Int, from chord: Int) -> (pitches: [PitchClass], direction: Int)? {
        if let lift, lift.semitones == 1, count == 1 {
            return ([target.transposed(by: -1)], 1)
        }
        if let line = walkUp(from: landingIndex - 1, beats: count + 1, count: count) {
            return (inMode(line.pitches, over: chord, direction: line.direction), line.direction)
        }
        let bass = span[chord].bass
        let side = approachSide(from: bass)
        let near = target.transposed(by: -side)
        let lead = Array(repeating: bass, count: max(0, count - 1))
        return (lead + [near], side)
    }

    /// Under a raga or pentatonic mode, each approach note outside the passing scale moves to
    /// its in-scale neighbour (D to Db in Bhairav; R168 mode-aware pass scales); the last note
    /// a half step from the landing stays.
    func inMode(_ pitches: [PitchClass], over chord: Int, direction: Int) -> [PitchClass] {
        guard let mode = context.mode, ![.major, .minor, .harmonicMinor].contains(mode) else {
            return pitches
        }
        let scale = passScale(chord, approach: true)
        return pitches.enumerated().map { index, pitch in
            let leading = index == pitches.count - 1
                && abs(WalkUp.signedDistance(pitch, target)) == 1
            guard scale[pitch] == nil, !leading else { return pitch }
            let order = direction < 0 ? [1, -1] : [-1, 1]
            return order.map { pitch.transposed(by: $0) }.first { scale[$0] != nil } ?? pitch
        }
    }

    /// Walk-up candidates from span chord `index` into the next (R169: in the next chord's
    /// key across a key change): exactly `count` notes, else the best shorter one padded with
    /// the departing bass in front; `count` nil takes the first non-hold candidate.
    func walkUp(
        from index: Int,
        beats: Int,
        count: Int?,
    ) -> (pitches: [PitchClass], direction: Int)? {
        let from = span[index]
        let into = span[index + 1]
        let candidates = WalkUp.candidates(
            from: from.bass,
            to: into.bass,
            context: Self.walkContext(context, from: index, beats: beats),
        ).filter { $0.kind != .hold && !$0.notes.isEmpty }
        func direction(_ candidate: WalkUpCandidate) -> Int {
            switch candidate.direction {
            case .up: 1
            case .down: -1
            case .neither: 0
            }
        }
        guard let count else {
            return candidates.first.map { ($0.notes.map(\.pitchClass), direction($0)) }
        }
        if let exact = candidates.first(where: { $0.notes.count == count }) {
            return (exact.notes.map(\.pitchClass), direction(exact))
        }
        if let shorter = candidates.first(where: { $0.notes.count < count }) {
            let pad = Array(repeating: from.bass, count: count - shorter.notes.count)
            return (pad + shorter.notes.map(\.pitchClass), direction(shorter))
        }
        return nil
    }

    /// The walk-up facts for span chord `index` into the next.
    static func walkContext(_ context: FillContext, from index: Int, beats: Int?) -> WalkUpContext {
        let span = context.span
        let from = span[index]
        let into = span[index + 1]
        let isLast = index + 1 == span.count - 1
        let key = into.key != nil && into.key != from.key ? into.key : from.key
        return WalkUpContext(
            key: key,
            departing: from.chord,
            arriving: into.chord,
            genre: context.genre,
            beats: beats,
            tempo: context.tempo,
            intoSection: isLast && context.intoSection,
            energyUp: isLast ? context.energyUp : nil,
            writtenLine: WalkUp.isWrittenLine(
                previous: index > 0 ? span[index - 1].bass : nil,
                from: from.bass,
                to: into.bass,
                next: index + 2 < span.count ? span[index + 2].bass : nil,
            ),
        )
    }

    /// +1 approaches from below, -1 from above: the side the departing bass comes from (a
    /// step keeps it; otherwise below into a section that raises the energy), below for the
    /// same note.
    func approachSide(from bass: PitchClass) -> Int {
        let distance = WalkUp.signedDistance(bass, target)
        if abs(distance) > 2, context.energyUp == true {
            return 1
        }
        return distance < 0 ? -1 : 1
    }

    /// A chord tone by function; nil when the chord has none (`seventh` falls back to the
    /// octave).
    static func tone(_ pitch: FillPitch, of symbol: ChordSymbol) -> PitchClass? {
        let root = symbol.root.pitchClass
        let intervals = Set(symbol.formula.intervals.map { $0 % 12 })
        func first(_ wanted: [Int]) -> PitchClass? {
            wanted.first(where: intervals.contains).map { root.transposed(by: $0) }
        }
        return switch pitch {
        case .third: first([4, 3, 5, 2])
        case .fifth: first([7, 6, 8]) ?? root.transposed(by: 7)
        case .seventh: first([10, 11, 9]) ?? (symbol.bass ?? symbol.root).pitchClass
        case .ninth: root.transposed(by: 2)
        default: nil
        }
    }

    /// The passing scale over span chord `index` (R161 `passScale`), in the new key across a
    /// lift for the landing, for approach notes and for a chord that fits the new key.
    func passScale(_ index: Int, approach: Bool) -> [PitchClass: NoteClass] {
        FillSpelling.passScale(
            span[index].chord,
            key: key(index, approach: approach),
            mode: context.mode,
        )
    }

    /// The key a note over span chord `index` is planned and spelled in (R168, R169).
    func key(_ index: Int, approach: Bool) -> SongKey? {
        if let lift,
           index == landingIndex || approach || lift.lastFitsNewKey && index == landingIndex - 1
        {
            return lift.newKey
        }
        return span[index].key
    }

    /// The sounding chord's pentatonic: the key's own under the major-pentatonic mode, else
    /// the chord's major or minor pentatonic by its third.
    func pentatonic(_ index: Int) -> Set<PitchClass> {
        let chord = span[index]
        if context.mode == .majorPentatonic, let key = chord.key, key.mode == .major {
            return Set(FillMode.majorPentatonic.degrees
                .map { key.tonic.pitchClass.transposed(by: $0) })
        }
        let root = chord.chord.root.pitchClass
        let minor = Set(chord.chord.formula.intervals.map { $0 % 12 }).contains(3)
        let degrees = minor ? [0, 3, 5, 7, 10] : [0, 2, 4, 7, 9]
        return Set(degrees.map { root.transposed(by: $0) })
    }

    /// The span chord sounding at `tick` (the landing from 0).
    func sounding(_ tick: Int) -> Int {
        guard tick < 0 else { return landingIndex }
        return (0 ..< landingIndex).last { starts[$0] <= tick } ?? 0
    }

    // MARK: Placement

    /// MIDI pitches: each note in the octave nearest the one before (or moving the way its
    /// run moves), from the first chord's placed bass; octaves an octave above the root they
    /// follow; folded into range.
    func place(_ notes: inout [Note]) {
        guard !notes.isEmpty else { return }
        var reference = span[sounding(notes[0].at)].placed
        var root = reference
        var lastChord = -1
        for index in notes.indices {
            let chord = notes[index].isLanding ? landingIndex : sounding(notes[index].at)
            if chord != lastChord {
                root = span[chord].placed
                lastChord = chord
            }
            var midi = index == 0 && notes[index].isRoot ? span[chord].placed
                : Self.midi(notes[index], reference: reference, root: root)
            if notes[index].isRoot {
                root = midi
            }
            if !context.range.contains(midi), notes[index].direction == 0, !notes[index].isOctave {
                // Nearest either way: the other octave is no fold.
                midi += midi < context.range.lowerBound ? 12 : -12
            }
            if !context.range.contains(midi) {
                notes[index].folded = true
                midi = Self.fold(midi, into: context.range)
            }
            notes[index].midi = midi
            reference = midi
        }
    }

    /// A note's MIDI pitch from the one before (`reference`) and the chord's root register.
    static func midi(_ note: Note, reference: Int, root: Int) -> Int {
        if note.isOctave {
            return nearest(note.pitch, to: root) + 12
        }
        if note.isRoot, note.direction == 0 {
            return nearest(note.pitch, to: root)
        }
        return switch note.direction {
        case 1: above(note.pitch, reference)
        case -1: below(note.pitch, reference)
        default: nearest(note.pitch, to: reference)
        }
    }

    static func fold(_ midi: Int, into range: ClosedRange<Int>) -> Int {
        var value = midi
        while value < range.lowerBound {
            value += 12
        }
        while value > range.upperBound {
            value -= 12
        }
        return value
    }

    static func nearest(_ pitch: PitchClass, to reference: Int) -> Int {
        let up = PitchClass(midi: reference).semitones(to: pitch)
        return up <= 6 ? reference + up : reference + up - 12
    }

    static func above(_ pitch: PitchClass, _ reference: Int) -> Int {
        let up = PitchClass(midi: reference).semitones(to: pitch)
        return reference + (up == 0 ? 12 : up)
    }

    static func below(_ pitch: PitchClass, _ reference: Int) -> Int {
        let down = pitch.semitones(to: PitchClass(midi: reference))
        return reference - (down == 0 ? 12 : down)
    }

    /// Marks the notes of a monotonic run of half steps that ends on the landing (R168: a
    /// weak-beat note there is exempt from the clash rule).
    func markChromaticRun(_ notes: inout [Note]) {
        guard let landing = notes.lastIndex(where: \.isLanding), landing > 0 else { return }
        let step = notes[landing].midi - notes[landing - 1].midi
        guard abs(step) == 1 else { return }
        var first = landing - 1
        while first > 0, notes[first].midi - notes[first - 1].midi == step {
            first -= 1
        }
        guard landing - first >= 2 else { return }
        for index in first ..< landing {
            notes[index].chromaticRun = true
        }
    }
}
