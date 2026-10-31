import Diagrams
import Foundation
import Library
import MusicTheory
import Testing
import Tonic

/// The fill corpus fixture (`Fixtures/fills/fill-corpus.json`, schema 1; the canonical
/// description is docs/research/phase8-fill-corpus.md section 3), loaded for tests only.
///
/// Mapping to the generator (P8-7 section 11.4; the corpus is canonical, this loader adapts):
/// - ticks are 24 per quarter in the corpus, 480 in the timeline (x 20);
/// - `span[].beats` are quarters in 4/4 and eighths in 6/8 (the corpus's R118 note);
/// - `family` is a corpus pattern family, which the generator calls a template's
///   `corpusFamily`; each maps onto one of the six rhythm families (`FillTemplates.standard`);
/// - `tempoBand` slow / mid / fast plays at 70 / 105 / 150 BPM (the corpus doc's test tempi);
/// - `mode` major / minor picks the key's quality; harmonicMinor, bhairav and
///   majorPentatonic also set `FillContext.mode`;
/// - departing chords are in `key`, the landing in `modulation.newKey` when there is one;
/// - `transition` with ">" lands in a new section; chorus, bridge and mukhda raise the energy,
///   verse and antara settle it;
/// - note tokens resolve to pitch classes: degrees over the last departing chord's bass,
///   `T`-tokens over the landing, `NK:n` the new key's degree n; S, C, CT, X and M have none.
struct FillCorpus: Decodable {
    var schema: Int
    var ticksPerQuarter: Int
    var families: [String]
    var examples: [Example]

    struct Example: Decodable, Sendable, CustomTestStringConvertible {
        var id: String
        var category: String
        var generatorGenre: BassGenre?
        var feel: String
        var tempoBand: String
        var meter: String
        var key: String
        var mode: String
        var transition: String
        var span: [Chord]
        var landing: Chord
        var modulation: Modulation?
        var events: [Event]
        var family: String
        var evidence: String
        var checks: Checks

        var testDescription: String {
            id
        }
    }

    struct Chord: Decodable, Sendable {
        var chord: String
        var fn: String
        var beats: Int
    }

    struct Modulation: Decodable, Sendable {
        var semitones: Int
        var kind: String
        var newKey: String
    }

    struct Event: Decodable, Sendable {
        var at: Int
        var len: Int
        /// "n": a note token.
        var note: String
        var art: [String]?

        private enum CodingKeys: String, CodingKey {
            case at
            case len
            case note = "n"
            case art
        }
    }

    struct Checks: Decodable, Sendable {
        var expectFamily: String
        var mustContain: [String]?
        var mustNotContain: [String]?
        var landsOn: String?
        var maxNotes: Int?
        var direction: String?
        var holdRanksFirst: Bool?
        var spanTicks: Int?
        var overhang: Int?
        var anticipates: Bool?
        var allowsSilence: Bool?
        var newKeySpelling: Bool?
        var spelling: [String: String]?
        var passScaleKey: String?
        var noFillBefore: Int?
        var minStart: Int?
        var cellRepeats: Int?
        var commonTone: String?
        var generatorScope: String?
    }

    static let shared: Self? = {
        guard let url = Bundle.module.url(
            forResource: "Fixtures/fills/fill-corpus",
            withExtension: "json",
        ), let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(Self.self, from: data)
    }()

    static var examples: [Example] {
        shared?.examples ?? []
    }

    /// Corpus ticks to timeline ticks.
    static let scale = 20
}

extension FillCorpus.Example {
    var songKey: SongKey? {
        let minor = ["minor", "harmonicMinor"].contains(mode)
        return SongKey(parsing: key.hasSuffix("m") || !minor ? key : key + "m")
    }

    var fillMode: FillMode? {
        FillMode(rawValue: mode)
            .flatMap { [.harmonicMinor, .bhairav, .majorPentatonic].contains($0) ? $0 : nil }
    }

    var newKey: SongKey? {
        modulation.flatMap { SongKey(parsing: $0.newKey) }
    }

    var tempo: Double {
        switch tempoBand {
        case "slow": 70
        case "fast": 150
        default: 105
        }
    }

    var fillMeter: FillMeter {
        meter == "6/8" ? FillMeter(pulses: 2, ticksPerPulse: 720, compound: true) : .common
    }

    /// The generator's context for this example, on a 4-string EADG bass.
    func context(tuning: Tuning = .bassStandard4) throws -> FillContext {
        let key = try #require(songKey)
        let home = BassFretboard.homeFret(tonic: key.tonic.pitchClass, tuning: tuning)
        let unit = meter == "6/8" ? 240 : 480
        let chords = span + [landing]
        let lengths = chords.map { $0.beats * unit }
        let bar = fillMeter.ticksPerBar
        var start = -lengths.dropLast().reduce(0, +)
        var result: [FillSpanChord] = []
        for (index, chord) in chords.enumerated() {
            let symbol = try #require(ChordSymbol(parsing: chord.chord), "\(chord.chord)")
            let isLanding = index == chords.count - 1
            result.append(FillSpanChord(
                chord: symbol,
                length: lengths[index],
                key: isLanding ? newKey ?? key : key,
                meter: fillMeter,
                placed: PartPitch.placedBass(symbol, tuning: tuning, home: home),
                onsetInBar: ((start % bar) + bar) % bar,
            ))
            start += lengths[index]
        }
        let parts = transition.lowercased().components(separatedBy: ">")
        let into = parts.count > 1
        let section = parts.last ?? ""
        let energy: Bool? = if ["chorus", "bridge", "mukhda", "prechorus"]
            .contains(where: section.contains)
        {
            true
        } else if ["verse", "antara"].contains(where: section.contains) {
            false
        } else {
            nil
        }
        return FillContext(
            span: result,
            genre: generatorGenre,
            tempo: tempo,
            mode: fillMode,
            range: PartPitch.range(of: tuning),
            intoSection: into,
            energyUp: into ? energy : nil,
        )
    }

    /// A note token's pitch class (corpus doc section 3); nil for S, C, CT, X, M.
    func pitch(_ token: String, context: FillContext) -> PitchClass? {
        let landing = context.span[context.span.count - 1]
        let target = landing.bass
        let sounding = context.span[context.span.count - 2].bass
        let degrees = [
            "R": 0, "b2": 1, "2": 2, "b3": 3, "3": 4, "4": 5, "#4": 6, "b5": 6, "5": 7, "#5": 8,
            "b6": 8, "6": 9, "b7": 10, "7": 11, "8": 0, "b9": 1, "9": 2,
        ]
        if let degree = degrees[token] {
            return sounding.transposed(by: degree)
        }
        if token == "T" {
            return target
        }
        if token == "T:5" {
            return landing.chord.root.pitchClass.transposed(by: 7)
        }
        if token == "T:3" {
            let third = landing.chord.formula.intervals.first { [3, 4].contains($0 % 12) } ?? 4
            return landing.chord.root.pitchClass.transposed(by: third)
        }
        if token.hasPrefix("T+") || token.hasPrefix("T-"), let steps = Int(token.dropFirst(1)) {
            return target.transposed(by: steps)
        }
        if token.hasPrefix("NK:"), let degree = Int(token.dropFirst(3)), let key = newKey {
            let scale = FillSpelling.scaleNotes(key)
            return scale.indices.contains(degree - 1) ? scale[degree - 1].pitchClass : nil
        }
        if let note = ChordSymbol(parsing: token), note.suffix.isEmpty {
            return note.root.pitchClass
        }
        return nil
    }
}

/// A candidate's notes relative to the landing onset (absolute ticks, MIDI).
struct PlacedFillNote {
    var at: Int
    var len: Int
    var midi: Int
    var name: NoteClass
    var chord: Int
    var event: PartEvent

    var pitch: PitchClass {
        PitchClass(midi: midi)
    }

    static func notes(_ candidate: FillCandidate, context: FillContext) -> [Self] {
        var starts = Array(repeating: 0, count: context.span.count)
        var tick = 0
        for index in stride(from: context.span.count - 2, through: 0, by: -1) {
            tick -= context.span[index].length
            starts[index] = tick
        }
        return zip(candidate.events, candidate.names).map { event, name in
            Self(
                at: starts[event.chord] + event.at,
                len: event.len,
                midi: context.span[event.chord].placed + event.semitones,
                name: name,
                chord: event.chord,
                event: event,
            )
        }
    }
}
