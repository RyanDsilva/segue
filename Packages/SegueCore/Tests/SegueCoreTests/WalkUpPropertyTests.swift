import MusicTheory
import Testing
import Tonic

/// Walk-up invariants (P8-4 section 8.13 item 2) over every bass pair, both modes, every
/// feel (and none) and beats {unknown, 1, 2, 4, 8}. Fast and pure.
struct WalkUpPropertyTests {
    static let keys = [
        SongKey(tonic: .init(.C), mode: .major),
        SongKey(tonic: .init(.A), mode: .minor),
    ]
    static let genres: [BassGenre?] = [nil] + BassGenre.allCases
    static let beats: [Int?] = [nil, 1, 2, 4, 8]

    /// The key's diatonic triad on `root`, else a major triad.
    static func triad(_ root: PitchClass, in key: SongKey) -> ChordSymbol {
        let scale = Set(key.scaleNotes.map(\.pitchClass))
        let name = KeySpelling.spell(root, in: key).chartName
        let minor = scale.contains(root) && !scale.contains(root.transposed(by: 4))
        let diminished = minor && !scale.contains(root.transposed(by: 7))
        let suffix = minor ? (diminished ? "dim" : "m") : ""
        return ChordSymbol(parsing: name + suffix) ?? ChordSymbol(
            root: KeySpelling.spell(root, in: key),
            suffix: "",
            formula: ChordFormula(intervals: [0, 4, 7], essential: [0, 4]),
        )
    }

    static func forEachMove(_ body: (PitchClass, PitchClass, WalkUpContext) -> Void) {
        for key in keys {
            for source in 0 ..< 12 {
                for target in 0 ..< 12 {
                    let from = PitchClass(source)
                    let to = PitchClass(target)
                    for genre in genres {
                        for beat in beats {
                            body(from, to, WalkUpContext(
                                key: key,
                                departing: triad(from, in: key),
                                arriving: triad(to, in: key),
                                genre: genre,
                                beats: beat,
                            ))
                        }
                    }
                }
            }
        }
    }

    @Test
    func `invariants hold for every move`() {
        var failures: [String] = []
        Self.forEachMove { source, target, context in
            let first = WalkUp.candidates(from: source, to: target, context: context)
            let label = "\(source)->\(target) \(context.key?.name ?? "-")"
                + " \(context.genre?.rawValue ?? "nil") n=\(context.beats.map(String.init) ?? "-")"
            if WalkUp.candidates(from: source, to: target, context: context) != first {
                failures.append("not deterministic: \(label)")
            }
            if first.count > 4 {
                failures.append("more than 4: \(label)")
            }
            let maxNotes = WalkUp.maxNotes(beats: context.beats)
            let third = Self.third(of: context.departing)
            let tones = Set(context.departing.tones.pitchClasses)
            for candidate in first {
                let pitches = candidate.notes.map(\.pitchClass)
                if candidate.kind == .hold {
                    failures.append("hold outside S2: \(label)")
                }
                if pitches.count > maxNotes + 1 {
                    failures.append("too long: \(label)")
                }
                if let last = pitches.last, candidate.kind != .fifth,
                   abs(WalkUp.signedDistance(last, target)) > 2
                {
                    failures.append("last note far from the target: \(label)")
                }
                if candidate.kind != .octavePickup,
                   pitches.contains(source) || pitches.contains(target)
                {
                    failures.append("contains source or target: \(label)")
                }
                // A clash is a cross-relation: the third's letter a half step away.
                for (index, note) in candidate.notes.enumerated() {
                    let pitch = note.pitchClass
                    let approach = index == pitches.count - 1
                        && abs(WalkUp.signedDistance(pitch, target)) == 1
                    if !approach, !tones.contains(pitch), note.letter == third.letter,
                       abs(WalkUp.signedDistance(pitch, third.pitchClass)) == 1
                    {
                        failures.append("clashes with the third: \(label)")
                    }
                }
                let sum = candidate.breakdown.values.reduce(0, +)
                if abs(sum - candidate.score) > 1e-9 {
                    failures.append("breakdown does not sum: \(label)")
                }
            }
        }
        #expect(failures.isEmpty, "\(failures.prefix(10))")
    }

    /// The triad's third, spelled a third above the root's letter.
    static func third(of chord: ChordSymbol) -> NoteClass {
        let interval = chord.formula.intervals.first { [3, 4].contains($0) } ?? 4
        let letter = Letter(rawValue: (chord.root.letter.rawValue + 2) % 7) ?? .C
        let natural = NoteClass(letter)
        let accidental: Accidental = switch natural.pitchClass.semitones(
            to: chord.root.pitchClass.transposed(by: interval),
        ) {
        case 1: .sharp
        case 11: .flat
        default: .natural
        }
        return NoteClass(letter, accidental: accidental)
    }

    @Test
    func `hold appears only under source written line`() {
        let key = Self.keys[0]
        for source in 0 ..< 12 {
            for target in 0 ..< 12 {
                let context = WalkUpContext(
                    key: key,
                    departing: Self.triad(PitchClass(source), in: key),
                    arriving: Self.triad(PitchClass(target), in: key),
                    writtenLine: true,
                )
                let result = WalkUp.candidates(
                    from: PitchClass(source),
                    to: PitchClass(target),
                    context: context,
                )
                let distance = abs(WalkUp.signedDistance(PitchClass(source), PitchClass(target)))
                if distance == 2 {
                    #expect(result.map(\.kind).first == .hold)
                    #expect(result.count == 2)
                }
            }
        }
    }

    /// The pre-research rule for diatonic moves: |d| <= 1 none; |d| = 2 the note between;
    /// 3 ... 5 the (up to) two scale notes nearest the target, the short way; a tritone a
    /// half step below.
    static func legacy(_ source: PitchClass, _ target: PitchClass, key: SongKey) -> [PitchClass] {
        let distance = WalkUp.signedDistance(source, target)
        switch abs(distance) {
        case 0, 1: return []
        case 2: return [distance > 0 ? target.transposed(by: -1) : target.transposed(by: 1)]
        case 6: return [target.transposed(by: -1)]
        default:
            let scale = Set(key.scaleNotes.map(\.pitchClass))
            let step = distance > 0 ? 1 : -1
            let between = (1 ..< abs(distance)).map { source.transposed(by: $0 * step) }
                .filter(scale.contains)
            return Array(between.suffix(2))
        }
    }

    @Test
    func `the legacy context keeps the old rule's top-1 for diatonic moves`() {
        var failures: [String] = []
        for key in Self.keys {
            let scale = key.scaleNotes.map(\.pitchClass)
            for source in scale {
                for target in scale {
                    let notes = WalkUp.notes(from: source, to: target, key: key).map(\.pitchClass)
                    let expected = Self.legacy(source, target, key: key)
                    if notes != expected {
                        failures
                            .append("\(key.name) \(source)->\(target): \(notes) not \(expected)")
                    }
                }
            }
        }
        #expect(failures.isEmpty, "\(failures)")
    }
}
