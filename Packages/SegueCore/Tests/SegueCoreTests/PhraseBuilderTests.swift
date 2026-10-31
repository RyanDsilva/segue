import ChordPro
import Diagrams
import Editing
import Library
import MusicTheory
@testable import Playback
import Shows
import Testing

/// Heard chords and walk-up auditions as note events (P8-6 sections 6.3, 15.1).
struct PhraseBuilderTests {
    static let placementG = BassPlacement(tuning: .bassStandard4, home: 3)
    static let voices = PlaybackVoices(sound: .piano, style: .block, placement: placementG)

    /// The first change (G to C) of a song in G, through the real bass line.
    static func change(_ source: String = "{key: G}\n[G]Hello [C]there\n") throws -> ChordChange {
        let (document, _) = ChordProParser.parse(source)
        let options = DisplayOptions()
            .withBass(InstrumentProfile(bassNotes: true, walkUps: .everyChange))
        let model = RenderModel(document: document, options: options)
        return try #require(BassLine.changes(model, document: document, prefs: BassPrefs()).first)
    }

    static func candidate(_ offsets: [Int], kind: WalkUpKind = .scaleWalk) -> WalkUpCandidate {
        WalkUpCandidate(
            kind: kind,
            notes: [],
            offsets: offsets,
            direction: .up,
            chromatic: offsets.map { _ in false },
            degrees: [],
            score: 0,
            breakdown: [:],
        )
    }

    static func bass(_ phrase: Phrase) -> [String] {
        phrase.events.filter { $0.voice == .bass }.map { event in
            "\(event.note)@\(String(format: "%.3f", event.onset))"
        }
    }

    static func rounded(_ value: Double) -> Double {
        (value * 1000).rounded() / 1000
    }

    @Test
    func `a block chord strikes every note at once over its bass`() throws {
        let chord = try #require(ChordSymbol(parsing: "G"))
        let phrase = PhraseBuilder.chord(chord, sound: .piano, style: .block, bass: 31)
        #expect(phrase.events.map(\.onset).allSatisfy { $0 == 0 })
        #expect(phrase.events.filter { $0.voice == .bass }.map(\.note) == [31])
        #expect(phrase.events.filter { $0.voice == .chord }.map(\.velocity) == [80, 80, 80])
        #expect(phrase.length == 1.6)
    }

    @Test
    func `a strum goes low to high 25 ms apart`() throws {
        let chord = try #require(ChordSymbol(parsing: "G"))
        let phrase = PhraseBuilder.chord(chord, sound: .piano, style: .strum, bass: 31)
        let chordOnsets = phrase.events.filter { $0.voice == .chord }.map { Self.rounded($0.onset) }
        #expect(chordOnsets == [0, 0.025, 0.05])
        #expect(phrase.events.first { $0.voice == .bass }?.onset == 0)
    }

    @Test
    func `audition G to C with A B at 90 in four four`() throws {
        let phrase = try PhraseBuilder.audition(
            Self.change(),
            candidate: Self.candidate([-3, -1]),
            tempo: 90,
            meter: .common,
            voices: Self.voices,
        )
        #expect(Self.bass(phrase) == ["31@0.000", "33@1.333", "35@2.000", "36@2.667"])
        let chords = phrase.events.filter { $0.voice == .chord }
        #expect(chords.filter { $0.onset == 0 }.map(\.note) == [55, 59, 62])
        #expect(chords.filter { Self.rounded($0.onset) == 2.667 }.map(\.note) == [48, 52, 55])
        #expect(Self.rounded(phrase.length) == 5.333)
    }

    @Test
    func `with no walk-up the root also sounds on beat 3`() throws {
        for candidate in [nil, Self.candidate([], kind: .hold)] {
            let phrase = try PhraseBuilder.audition(
                Self.change(),
                candidate: candidate,
                tempo: nil,
                meter: .common,
                voices: Self.voices,
            )
            #expect(Self.bass(phrase) == ["31@0.000", "31@1.333", "36@2.667"])
        }
    }

    @Test(arguments: [
        (MetronomeMeter.common, 3, [1.0, 2.0, 3.0]),
        (MetronomeMeter.common, 4, [1.0, 2.0, 3.0, 3.5]),
        (MetronomeMeter(beats: 3, noteValue: 4), 2, [1.0, 2.0]),
        (MetronomeMeter(beats: 6, noteValue: 8), 2, [4.0 / 3, 5.0 / 3]),
    ])
    func `walk notes sit on the last beats`(meter: MetronomeMeter, count: Int, beats: [Double]) {
        let slots = PhraseBuilder.walkSlots(
            count: count,
            pulses: meter.pulses,
            compound: meter.isCompound,
        )
        #expect(slots.map(Self.rounded) == beats.map(Self.rounded))
    }

    @Test
    func `a walk down to E stays stepwise across E1`() throws {
        // G to Em in G walking down F# F: the target E sits a step below the last walk note.
        let change = try Self.change("{key: G}\n[G]Hello [Em]there\n")
        let phrase = PhraseBuilder.audition(
            change,
            candidate: Self.candidate([2, 1]),
            tempo: 90,
            meter: .common,
            voices: Self.voices,
        )
        let notes = phrase.events.filter { $0.voice == .bass }.map { Int($0.note) }
        #expect(notes == [31, 30, 29, 28])
    }

    @Test
    func `beat notes convert at the tempo`() {
        let phrase = Phrase(
            beats: [BeatNote(voice: .bass, note: 40, velocity: 90, startBeat: 1, beats: 0.5)],
            tempo: 120,
            lengthBeats: 4,
        )
        #expect(phrase.events.first?.onset == 0.5)
        #expect(phrase.events.first?.duration == 0.25)
        #expect(phrase.length == 2)
    }
}

/// The fill editor's audition phrase (P8-7 section 12.3): its bounds and its voices.
extension PhraseBuilderTests {
    static let fillSong = "{key: G}\n{tempo: 60}\n[G]Hello [C]there [D]friend\n"

    /// The song's timeline, and a fill over C -> D: D and E on beats 3 and 4 of C.
    static func fillPlay(
        _ events: [PartEvent] = [
            PartEvent(chord: 0, at: 960, len: 480, deg: 2),
            PartEvent(chord: 0, at: 1440, len: 480, deg: 4),
        ],
    ) throws -> FillPlay {
        let (document, _) = ChordProParser.parse(fillSong)
        let model = RenderModel(document: document, options: DisplayOptions())
        let units = SongSections.units(of: document)
        let timeline = SongTimeline.build(
            document: document,
            sections: model.sections,
            units: units,
            timing: ChordTiming(),
            order: nil,
        )
        let anchor = try #require(FillSpan.anchor(
            timeline: timeline,
            chords: 1 ... 2,
            units: units,
            sections: model.sections,
        ))
        let part = Part(span: anchor, events: events)
        let parts = PartAnchors.resolve(
            [part],
            timeline: timeline,
            units: units,
            sections: model.sections,
        )
        let play = try #require(parts.plays(in: timeline).first)
        let notes = play.resolve(
            timeline: timeline,
            transform: model.transform,
            tuning: placementG.tuning,
            home: placementG.home,
        )
        return FillPlay(timeline: timeline, model: model, notes: notes)
    }

    struct FillPlay {
        var timeline: SongTimeline
        var model: RenderModel
        var notes: [ResolvedNote]
    }

    @Test
    func `a fill audition runs from the span start through the landing bar`() throws {
        let play = try Self.fillPlay()
        let (timeline, model, notes) = (play.timeline, play.model, play.notes)
        let audition = PhraseBuilder.fill(
            span: timeline,
            chords: 1 ... 2,
            notes: notes,
            voices: Self.voices,
            transform: model.transform,
            click: false,
        )
        // The first note is in bar 2, so one bar before it would be bar 1: clamped to the span
        // start (C, bar 2); through the end of D's bar.
        #expect(audition.ticks == 1920 ..< 5760)
        #expect(abs(audition.phrase.length - 8) < 1e-9)
        // Roots until the fill, the fill's D and E, then D's root on 1 and 3.
        #expect(Self.bass(audition.phrase) == [
            "36@0.000",
            "38@2.000",
            "40@3.000",
            "38@4.000",
            "38@6.000",
        ])
        #expect(audition.phrase.events.contains { $0.voice == .chord && abs($0.onset) < 1e-9 })
        #expect(!audition.phrase.events.contains {
            if case .click = $0.voice {
                true
            } else {
                false
            }
        })
        #expect(audition.tick(atSeconds: 2) == 2880)
    }

    @Test
    func `the audition starts one bar before a late first note and clicks when asked`() throws {
        let play = try Self.fillPlay([PartEvent(chord: 1, at: 0, len: 480, deg: 0)])
        let (timeline, model, notes) = (play.timeline, play.model, play.notes)
        let window = PhraseBuilder.fillWindow(timeline: timeline, chords: 0 ... 2, notes: notes)
        // The only note is on D (bar 3): one bar before it is bar 2, after the span start.
        #expect(window == 1920 ..< 5760)
        let audition = PhraseBuilder.fill(
            span: timeline,
            chords: 1 ... 2,
            notes: notes,
            voices: Self.voices,
            transform: model.transform,
            click: true,
        )
        #expect(audition.phrase.events.contains {
            if case .click = $0.voice {
                true
            } else {
                false
            }
        })
    }

    @Test
    func `an empty fill plays the span's roots`() throws {
        let play = try Self.fillPlay()
        let (timeline, model) = (play.timeline, play.model)
        let audition = PhraseBuilder.fill(
            span: timeline,
            chords: 1 ... 2,
            notes: [],
            voices: Self.voices,
            transform: model.transform,
            click: false,
        )
        #expect(Self.bass(audition.phrase) == ["36@0.000", "36@2.000", "38@4.000", "38@6.000"])
    }
}
