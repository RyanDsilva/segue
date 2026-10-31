import Diagrams
import Foundation
import Library
import MusicTheory
import Testing
import Tonic

/// Properties every fill candidate holds over generated spans (P8-7 section 11.6). Fast and
/// pure: a deterministic sample of roots x modes x feels x lengths x meters x key changes.
struct FillPropertyTests {
    struct Case: Sendable, CustomTestStringConvertible {
        var key: SongKey
        var degrees: [Int]
        var genre: BassGenre?
        var pulses: [Int]
        var meter: FillMeter
        var lift: Int?

        var testDescription: String {
            let meter = "\(meter.pulses)x\(meter.ticksPerPulse)"
            let feel = genre?.rawValue ?? "nil"
            return "\(key.name) \(degrees) \(feel) \(pulses) \(meter) lift \(lift ?? 0)"
        }
    }

    static let meters = [
        FillMeter.common,
        FillMeter(pulses: 3, ticksPerPulse: 480, compound: false),
        FillMeter(pulses: 2, ticksPerPulse: 720, compound: true),
    ]
    static let progressions = [[0, 3], [4, 0], [1, 4, 0], [5, 3, 4, 0], [0, 5], [3, 4]]
    static let lengths: [[Int]] = [[1], [2], [4], [8], [4, 2, 1, 3]]
    static let genres: [BassGenre?] = BassGenre.allCases + [nil]

    /// About 200 cases, every root and mode, each other dimension cycled.
    static let cases: [Case] = {
        var result: [Case] = []
        var index = 0
        for tonic in 0 ..< 12 {
            for mode in KeyMode.allCases {
                for variant in 0 ..< 8 {
                    let key = SongKey(canonical: PitchClass(tonic), mode: mode)
                    let degrees = progressions[(index + variant) % progressions.count]
                    let pulses = lengths[(index / 2 + variant) % lengths.count]
                    let meter = meters[(index + variant / 3) % meters.count]
                    result.append(Case(
                        key: key,
                        degrees: degrees,
                        genre: genres[(index + variant * 5) % genres.count],
                        pulses: degrees.indices.map { pulses[$0 % pulses.count] } + [meter.pulses],
                        meter: meter,
                        lift: variant % 4 == 3 ? [1, 2][variant % 2] : nil,
                    ))
                    index += 1
                }
            }
        }
        return result
    }()

    static func context(_ row: Case) throws -> FillContext {
        let tuning = Tuning.bassStandard4
        let home = BassFretboard.homeFret(tonic: row.key.tonic.pitchClass, tuning: tuning)
        let names = row.key.diatonicChordSymbols
        var chords = try row.degrees
            .map { try #require(ChordSymbol(parsing: names[$0 % names.count])) }
        var landingKey = row.key
        if let lift = row.lift {
            landingKey = row.key.transposed(by: lift)
            chords[chords.count - 1] = try #require(ChordSymbol(
                parsing: landingKey.diatonicChordSymbols[0],
            ))
        }
        var span: [FillSpanChord] = []
        var onset = 0
        for (index, chord) in chords.enumerated() {
            let length = row.pulses[index] * row.meter.ticksPerPulse
            span.append(FillSpanChord(
                chord: chord,
                length: length,
                key: index == chords.count - 1 ? landingKey : row.key,
                meter: row.meter,
                placed: PartPitch.placedBass(chord, tuning: tuning, home: home),
                onsetInBar: onset % row.meter.ticksPerBar,
            ))
            onset += length
        }
        let total = span.dropLast().map(\.length).reduce(0, +)
        // Land on a downbeat.
        let shift = (row.meter.ticksPerBar - total % row.meter.ticksPerBar) % row.meter.ticksPerBar
        for index in span.indices {
            span[index].onsetInBar = (span[index].onsetInBar + shift) % row.meter.ticksPerBar
        }
        return FillContext(
            span: span,
            genre: row.genre,
            tempo: 100,
            range: PartPitch.range(of: tuning),
        )
    }

    @Test(arguments: cases)
    func `every candidate holds the fill properties`(_ row: Case) throws {
        let context = try Self.context(row)
        let candidates = Fill.candidates(context)
        #expect(candidates == Fill.candidates(context))
        #expect(candidates.count <= 5)
        // At most one per corpus pattern family (R170).
        let families = candidates.map { candidate in
            FillTemplates.standard.template(candidate.template)?.corpusFamily ?? "hold"
        }
        #expect(Set(families).count == families.count)
        for candidate in Fill.all(context) + candidates {
            try Self.check(candidate, context: context)
        }
    }

    // swiftlint:disable:next function_body_length
    static func check(_ candidate: FillCandidate, context: FillContext) throws {
        let departing = context.span.dropLast().map(\.length).reduce(0, +)
        let landing = try #require(context.span.last)
        let fifth = landing.chord.root.pitchClass.transposed(by: 7)
        #expect(abs(candidate.breakdown.values.reduce(0, +) - candidate.score) < 1e-9)
        let template = FillTemplates.standard.template(candidate.template)
        let notes = PlacedFillNote.notes(candidate, context: context)
        let fill = notes.filter { $0.at < 0 }
        for (note, next) in zip(notes, notes.dropFirst()) {
            #expect(note.at + note.len <= next.at, "\(candidate.template) overlaps")
        }
        for note in notes {
            #expect(note.at >= -departing, "\(candidate.template) starts before the span")
            #expect(context.range.contains(note.midi), "\(candidate.template) out of range")
            if note.at < 0, template?.ownsLanding != true {
                #expect(note.at + note.len <= 0, "\(candidate.template) crosses the landing")
            }
        }
        // A break-stop's last note is the band's hit before the silence (R170).
        if let last = fill.last, template?.leads != false {
            let close = abs(WalkUp.signedDistance(last.pitch, landing.bass)) <= 2
                || last.pitch == fifth
            #expect(close, "\(candidate.template) ends on \(last.name.chartName)")
        }
        for (index, note) in fill.enumerated() where index < fill.count - 1 {
            let chord = context.span[note.chord]
            let tones = Set(chord.chord.tones.pitchClasses).union([chord.bass])
            let thirdInterval = chord.chord.formula.intervals.first { [3, 4].contains($0 % 12) }
            guard let interval = thirdInterval, !tones.contains(note.pitch) else { continue }
            let third = chord.chord.root.pitchClass.transposed(by: interval)
            let letter = (chord.chord.root.letter.rawValue + 2) % 7
            let crossRelation = abs(WalkUp.signedDistance(note.pitch, third)) == 1
                && note.name.letter.rawValue == letter
            let chromaticRun = Self.inChromaticRun(index, notes: notes)
            // The last note before a chord inside a walk, a half step from its bass.
            let next = notes[index + 1]
            let approaches = next.chord != note.chord
                && abs(WalkUp.signedDistance(note.pitch, context.span[next.chord].bass)) == 1
            #expect(!crossRelation || chromaticRun || approaches, "\(candidate.template) clashes")
        }
        let part = try Part(
            span: SpanAnchor(
                start: ChordAnchor(
                    section: .section(SectionRef(label: "A", occurrence: 1)),
                    fingerprint: "x",
                    chord: 0,
                    from: "C",
                ),
                end: ChordAnchor(
                    section: .section(SectionRef(label: "A", occurrence: 1)),
                    fingerprint: "x",
                    chord: 1,
                    from: "C",
                ),
                spanBass: Array(repeating: "C", count: context.span.count),
            ),
            events: #require(candidate
                .isHold ? [PartEvent(chord: 0, at: 0, len: 1, deg: 0)] : candidate.events),
        )
        #expect(try JSONDecoder().decode(Part.self, from: JSONEncoder().encode(part)) == part)
    }

    /// Inside a monotonic run of half steps that ends on the landing note.
    static func inChromaticRun(_ index: Int, notes: [PlacedFillNote]) -> Bool {
        guard let landing = notes.firstIndex(where: { $0.at >= 0 }),
              index < landing else { return false }
        let step = notes[landing].midi - notes[landing - 1].midi
        guard abs(step) == 1 else { return false }
        var first = landing - 1
        while first > 0, notes[first].midi - notes[first - 1].midi == step {
            first -= 1
        }
        return index >= first
    }
}
