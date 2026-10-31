import Diagrams
import Foundation
import Library
import MusicTheory
import Testing
import Tonic

/// `Fill.candidates` against the fill corpus (P8-7 section 11.4) and the named rows (11.5).
struct FillCandidateTests {
    // MARK: Corpus goldens

    /// The checks a row fails (corpus doc section 3), [] when it passes; nil when the row is
    /// out of the generator's scope (it needs the melody).
    static func failures(_ row: FillCorpus.Example) throws -> [String]? {
        // swiftlint:disable:previous cyclomatic_complexity function_body_length
        if row.checks.generatorScope == "out" {
            return nil
        }
        let context = try row.context()
        let candidates = Fill.candidates(context)
        let checks = row.checks
        var failed: [String] = []
        let wanted = checks.expectFamily
        guard let candidate = candidates.first(where: { candidate in
            wanted == FillCandidate.holdTemplate ? candidate.isHold
                : FillTemplates.standard.template(candidate.template)?.corpusFamily == wanted
        }) else {
            return ["family \(wanted) not in \(candidates.map(\.template))"]
        }
        let notes = PlacedFillNote.notes(candidate, context: context)
        let fill = notes.filter { $0.at < 0 }
        let pitches = Set(fill.map(\.pitch))
        func pitch(_ token: String) -> PitchClass? {
            row.pitch(token, context: context)
        }
        for token in checks.mustContain ?? [] {
            if let wanted = pitch(token), !pitches.contains(wanted) {
                failed.append("missing \(token)")
            }
        }
        for token in checks.mustNotContain ?? [] {
            if let unwanted = pitch(token), pitches.contains(unwanted) {
                failed.append("contains \(token)")
            }
        }
        if !candidate.isHold, let token = checks.landsOn, let wanted = pitch(token),
           let landing = notes.first(where: { $0.at >= 0 }) ?? notes.last,
           landing.pitch != wanted
        {
            failed.append("lands on \(landing.name.chartName), not \(token)")
        }
        let starts = Set(Self.starts(context))
        let counted = fill
            .filter { !(starts.contains($0.at) && $0.pitch == context.span[$0.chord].bass) }
        if let most = checks.maxNotes, counted.count > most {
            failed.append("\(counted.count) notes > \(most)")
        }
        if let direction = checks.direction, let first = fill.first, let last = fill.last,
           (direction == "up") != (last.midi > first.midi)
        {
            failed.append("not \(direction)")
        }
        if checks.holdRanksFirst == true, candidates.first?.isHold != true {
            failed.append("hold not first: \(candidates.map(\.template))")
        }
        if let ticks = checks.spanTicks {
            let earliest = candidates.flatMap { PlacedFillNote.notes($0, context: context) }
                .map(\.at).min() ?? 0
            if earliest < -ticks * FillCorpus.scale {
                failed.append("starts at \(earliest) before the span")
            }
        }
        if checks.overhang != nil, !notes.contains(where: { $0.at > 0 }) {
            failed.append("no overhang")
        }
        if checks.anticipates == true,
           !fill.contains(where: { $0.pitch == context.span.last?.bass })
        {
            failed.append("does not anticipate")
        }
        if checks.allowsSilence == true, !candidates.contains(where: { candidate in
            candidate.template == "stopTime"
                && PlacedFillNote.notes(candidate, context: context).count { $0.at < 0 } <= 2
        }) {
            failed.append("no stop-time candidate")
        }
        if checks.newKeySpelling == true, let key = row.newKey {
            let scale = Dictionary(
                FillSpelling.scaleNotes(key).map { ($0.pitchClass, $0) },
                uniquingKeysWith: { first, _ in first },
            )
            let last = fill.last
            if let last, let spelled = scale[last.pitch], spelled != last.name {
                failed
                    .append(
                        "\(last.name.chartName) not spelled \(spelled.chartName) in \(key.name)",
                    )
            }
        }
        for (token, name) in checks.spelling ?? [:] {
            if let wanted = pitch(token), let note = fill.first(where: { $0.pitch == wanted }),
               note.name.chartName != name
            {
                failed.append("\(token) spelled \(note.name.chartName), not \(name)")
            }
        }
        if checks.passScaleKey == "new", let key = row.newKey {
            let scale = Set(FillSpelling.scaleNotes(key).map(\.pitchClass))
            let last = context.span.count - 2
            let tones = Set(context.span[last].chord.tones.pitchClasses)
            let outside = fill.dropLast().filter { note in
                note.chord == last && !tones.contains(note.pitch) && !scale.contains(note.pitch)
            }
            if !outside.isEmpty {
                failed.append("passing tones outside \(key.name): \(outside.map(\.name.chartName))")
            }
        }
        if let before = checks.noFillBefore,
           counted.contains(where: { $0.at < before * FillCorpus.scale })
        {
            failed.append("a fill note before \(before)")
        }
        if let start = checks.minStart, let first = notes.first,
           first.at < start * FillCorpus.scale
        {
            failed.append("starts at \(first.at)")
        }
        if let cells = checks.cellRepeats,
           notes.count(where: { $0.pitch == context.span.last?.bass }) < cells
        {
            failed.append("fewer than \(cells) cells")
        }
        if let tone = checks.commonTone, let wanted = pitch(tone),
           !notes.contains(where: { $0.pitch == wanted })
        {
            failed.append("no common tone \(tone)")
        }
        return failed
    }

    static func starts(_ context: FillContext) -> [Int] {
        var result: [Int] = []
        var tick = 0
        for index in stride(from: context.span.count - 2, through: 0, by: -1) {
            tick -= context.span[index].length
            result.append(tick)
        }
        return result
    }

    /// Pass rates per category, recorded as floors: a failing golden is a tuning signal for
    /// `FillWeights` and `FillTemplates`, never a reason to edit the corpus (11.4). Raise a
    /// floor when tuning raises the rate.
    static let floors: [String: Double] = ["section": 0.39, "keyChange": 0.31, "bollywood": 0.47]

    @Test
    func `the corpus golden pass rate per category`() throws {
        var passed: [String: Int] = [:]
        var total: [String: Int] = [:]
        var report: [String] = []
        for row in FillCorpus.examples {
            guard let failed = try Self.failures(row) else { continue }
            total[row.category, default: 0] += 1
            if failed.isEmpty {
                passed[row.category, default: 0] += 1
            } else {
                report.append("\(row.id) [\(row.evidence)]: \(failed.joined(separator: "; "))")
            }
        }
        for (category, count) in total.sorted(by: { $0.key < $1.key }) {
            let rate = Double(passed[category] ?? 0) / Double(count)
            print(
                "fill corpus \(category): \(passed[category] ?? 0)/\(count) = \(Int(rate * 100))%",
            )
            #expect(rate >= Self.floors[category] ?? 1, "\(category) \(rate)")
        }
        print(report.joined(separator: "\n"))
        #expect(total.values.reduce(0, +) >= 80)
    }

    // MARK: Named rows (11.5)

    /// A span of concert chords, `pulses` each (4/4 unless `meter`), in `key` (the landing in
    /// `landingKey` when given), on `tuning`.
    static func context(
        _ chords: [String],
        key: String,
        landingKey: String? = nil,
        genre: BassGenre? = .pop,
        tempo: Double? = 96,
        pulses: [Int]? = nil,
        meter: FillMeter = .common,
        tuning: Tuning = .bassStandard4,
    ) throws -> FillContext {
        let songKey = try #require(SongKey(parsing: key))
        let home = BassFretboard.homeFret(tonic: songKey.tonic.pitchClass, tuning: tuning)
        let lengths = (pulses ?? Array(repeating: meter.pulses, count: chords.count))
            .map { $0 * meter.ticksPerPulse }
        var span: [FillSpanChord] = []
        var onset = 0
        for (index, name) in chords.enumerated() {
            let symbol = try #require(ChordSymbol(parsing: name))
            let isLanding = index == chords.count - 1
            span.append(FillSpanChord(
                chord: symbol,
                length: lengths[index],
                key: isLanding ? landingKey.flatMap(SongKey.init(parsing:)) ?? songKey : songKey,
                meter: meter,
                placed: PartPitch.placedBass(symbol, tuning: tuning, home: home),
                onsetInBar: onset % meter.ticksPerBar,
            ))
            onset += lengths[index]
        }
        return FillContext(
            span: span,
            genre: genre,
            tempo: tempo,
            range: PartPitch.range(of: tuning),
        )
    }

    static func fillNames(_ candidate: FillCandidate, _ context: FillContext) -> [String] {
        PlacedFillNote.notes(candidate, context: context).filter { $0.at < 0 }.map(\.name.chartName)
    }

    @Test
    func `from G to C: four families, the walk ends on the top walk-up, breakdowns sum`() throws {
        let context = try Self.context(["G", "C"], key: "G")
        let candidates = Fill.candidates(context)
        #expect(candidates.count == 5)
        let shown = candidates.prefix(4).map { $0.family?.rawValue ?? "hold" }
        #expect(Set(shown).count == 4, "\(shown)")
        let walk = try #require(candidates.first { $0.family == .walk })
        #expect(Self.fillNames(walk, context).suffix(2) == ["A", "B"])
        for candidate in Fill.all(context) + candidates {
            #expect(abs(candidate.breakdown.values.reduce(0, +) - candidate.score) < 1e-9)
        }
    }

    @Test
    func `a four-chord span: the walk covers every departing chord, the pickup the last bar`(
    ) throws {
        let context = try Self.context(["D", "G", "Em", "C"], key: "G")
        let all = Fill.all(context)
        let walk = try #require(all.first { $0.template == "quarterWalk" })
        #expect(Set(walk.events.map(\.chord)).isSuperset(of: [0, 1, 2]))
        let pickup = try #require(all.first { $0.family == .pickup })
        #expect(pickup.events.allSatisfy { $0.chord >= 2 })
    }

    @Test
    func `from E to Am, Bollywood: the approach walks F G#, never F G`() throws {
        let context = try Self.context(["E", "Am"], key: "Am", genre: .bollywood)
        let all = Fill.all(context)
        let pickup = try #require(all.first { $0.template == "pickup8" })
        #expect(Self.fillNames(pickup, context).suffix(2) == ["F", "G#"])
        for candidate in all {
            let names = Self.fillNames(candidate, context)
            #expect(!zip(names, names.dropFirst()).contains { $0 == "F" && $1 == "G" }, "\(names)")
        }
    }

    @Test
    func `a lift into A ends on its dominant or a half step below, and only then scores it`(
    ) throws {
        let lifted = try Self.context(["E", "A"], key: "G", landingKey: "A")
        let candidates = Fill.candidates(lifted)
        let ending = candidates.first { candidate in
            ["E", "G#"].contains(Self.fillNames(candidate, lifted).last ?? "")
                && (candidate.breakdown[.keyChange] ?? 0) > 0
        }
        #expect(ending != nil, "\(candidates.map(\.template))")
        let plain = try Self.context(["E", "A"], key: "A")
        #expect(Fill.all(plain).allSatisfy { ($0.breakdown[.keyChange] ?? 0) == 0 })
    }

    @Test
    func `from G to Ab, a half-step lift: hold and a chromatic run are the top two`() throws {
        let context = try Self.context(["G", "Ab"], key: "G", landingKey: "Ab")
        let top = Fill.candidates(context).prefix(2)
        #expect(top.contains { $0.isHold })
        let run = top.first { !$0.isHold }
        let names = try Self.fillNames(#require(run), context)
        #expect(names.last == "G", "\(names)")
    }

    @Test
    func `the tempo and feel set the density`() throws {
        let fast = try Self.context(["G", "C"], key: "G", genre: .rock, tempo: 180)
        #expect(Fill.candidates(fast).allSatisfy { $0.family != .run })
        #expect(Fill.all(fast).allSatisfy { $0.family != .run })
        let worship = try Self.context(["G", "C"], key: "G", genre: .worship, tempo: 66)
        for candidate in Fill.all(worship) {
            #expect(Self.fillNames(candidate, worship).count <= 4, "\(candidate.template)")
        }
    }

    @Test
    func `in 6/8 templates sit on dotted-quarter pulses and no triplets are offered`() throws {
        let sixEight = FillMeter(pulses: 2, ticksPerPulse: 720, compound: true)
        let context = try Self.context(["D", "G"], key: "G", meter: sixEight)
        let all = Fill.all(context)
        #expect(!all.isEmpty)
        #expect(all.allSatisfy { $0.family != .triplet })
        let walk = try #require(all.first { $0.template == "quarterWalk" })
        #expect(walk.events.allSatisfy { $0.at.isMultiple(of: 720) })
    }

    @Test
    func `a one-pulse departing chord offers only what fits, never an empty A`() throws {
        let context = try Self.context(["D", "G"], key: "G", pulses: [1, 4])
        let candidates = Fill.candidates(context)
        let first = try #require(candidates.first)
        #expect(!first.isHold)
        let templates = Set(Fill.all(context).map(\.template))
        #expect(!templates.contains("quarterWalk") && !templates.contains("chordArpeggio"))
    }

    @Test
    func `a five-string bass goes below E1 where a four-string folds and is flagged`() throws {
        let five = try Self.context(["A", "D"], key: "D", tuning: .bassStandard5)
        let four = try Self.context(["A", "D"], key: "D", tuning: .bassStandard4)
        func lowest(_ context: FillContext) -> Int {
            Fill.all(context).flatMap { PlacedFillNote.notes($0, context: context) }.map(\.midi)
                .min() ?? 0
        }
        #expect(lowest(five) < 28)
        #expect(lowest(four) >= 28)
    }
}
