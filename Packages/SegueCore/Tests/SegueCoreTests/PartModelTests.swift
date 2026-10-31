import ChordPro
import Diagrams
import Editing
import Foundation
import Library
import MusicTheory
import Testing

/// A small song with a part, built the way the app builds it (P8-7 section 9).
struct PartFixture {
    static let song = """
    {key: G}
    {start_of_verse}
    [G]Hello [C]there [D]friend
    {end_of_verse}
    {start_of_chorus}
    [G]Sing [Em]it [C]loud [D]now
    {end_of_chorus}
    {chorus}

    """

    let source: String
    let document: SongDocument
    let model: RenderModel
    let units: [SongSectionUnit]
    let timeline: SongTimeline

    init(
        _ source: String = Self.song,
        options: DisplayOptions = DisplayOptions(),
        order: [PlayedPass]? = nil,
    ) {
        self.source = source
        document = ChordProParser.parse(source).0
        model = RenderModel(document: document, options: options)
        units = SongSections.units(of: document)
        timeline = SongTimeline.build(
            document: document,
            sections: model.sections,
            units: units,
            timing: ChordTiming(),
            order: order,
        )
    }

    func anchor(_ section: Int, _ chord: Int) throws -> ChordAnchor {
        try #require(ChordAnchors.anchor(
            at: ChordPosition(section: section, chord: chord),
            units: units,
            sections: model.sections,
        ))
    }

    /// A part from (section, chord) over `bass.count` written chords.
    func part(
        from start: (Int, Int),
        to end: (Int, Int),
        bass: [String],
        passes: PassFilter = .all,
        events: [PartEvent] = [PartEvent(chord: 0, at: 1440, len: 240, deg: 2)],
    ) throws -> Part {
        try Part(
            span: SpanAnchor(
                start: anchor(start.0, start.1),
                end: anchor(end.0, end.1),
                spanBass: bass,
            ),
            passes: passes,
            events: events,
        )
    }

    func resolved(_ parts: [Part]) -> ResolvedParts {
        PartAnchors.resolve(parts, timeline: timeline, units: units, sections: model.sections)
    }

    /// The first play's notes.
    func notes(
        _ part: Part,
        tuning: Tuning = .bassStandard4,
        home: Int? = nil,
    ) throws -> [ResolvedNote] {
        let play = try #require(resolved([part]).plays(in: timeline).first)
        let tonic = model.transform.concertKey?.tonic.pitchClass ?? PitchClass(7)
        return play.resolve(
            timeline: timeline,
            transform: model.transform,
            tuning: tuning,
            home: home ?? BassFretboard.homeFret(tonic: tonic, tuning: tuning),
        )
    }
}

/// Parts resolve to sounding notes (P8-7 sections 9.2, 9.4).
struct PartModelTests {
    /// D (verse, last chord) into G (chorus, first): E and F# over D, then G.
    static func intoChorus(_ fixture: PartFixture, pin: String? = nil) throws -> Part {
        try fixture.part(from: (0, 2), to: (1, 0), bass: ["D", "G"], events: [
            PartEvent(chord: 0, at: 960, len: 480, deg: 2, string: pin),
            PartEvent(chord: 0, at: 1440, len: 480, deg: 4),
            PartEvent(chord: 1, at: 0, len: 480, deg: 0),
        ])
    }

    @Test
    func `deg and oct resolve from the chord's placed bass note`() throws {
        let fixture = PartFixture()
        let notes = try fixture.notes(Self.intoChorus(fixture))
        // EADG, home 3 (G on the E string): D sits on the A string's 5th fret (D2 = 38).
        #expect(notes.map(\.midi) == [40, 42, 31])
        #expect(notes.map(\.name) == ["E", "F#", "G"])
        let departing = try #require(fixture.timeline.timed(pass: 0, chord: 2))
        let onset = departing.onset
        #expect(notes.map(\.tick) == [onset + 960, onset + 1440, onset + departing.length])
    }

    @Test
    func `transpose, capo in both modes and a slot key override move the fill with the chords`(
    ) throws {
        let plain = PartFixture()
        let up = PartFixture(options: DisplayOptions(transpose: 2))
        let lifted = try up.notes(Self.intoChorus(up))
        // E (open E) into A: F# G# then A.
        #expect(lifted.map(\.midi) == [30, 32, 33])
        #expect(lifted.map(\.name) == ["F#", "G#", "A"])
        for mode in CapoMode.allCases {
            let capo = PartFixture(
                "{capo: 2}\n" + PartFixture.song,
                options: DisplayOptions(capoMode: mode),
            )
            #expect(try capo.notes(Self.intoChorus(capo)).map(\.midi) == lifted.map(\.midi))
        }
        // The same part read without a transform is unchanged.
        #expect(try plain.notes(Self.intoChorus(plain)).map(\.midi) == [40, 42, 31])
    }

    @Test
    func `a five-string profile places the bass lower and the fill follows it`() throws {
        let fixture = PartFixture()
        let part = try Self.intoChorus(fixture)
        let notes = try fixture.notes(part, tuning: .bassStandard5)
        let departing = try #require(fixture.timeline.timed(pass: 0, chord: 2))
        let base = try PartPitch.placedBass(
            #require(ChordSymbol(parsing: departing.token)),
            tuning: .bassStandard5,
            home: 3,
        )
        #expect(notes.first?.midi == base + 2)
    }

    @Test
    func `spelling follows the key in effect at the chord`() throws {
        func names(_ key: String) throws -> [String] {
            let source = "{key: G}\n[C]a [D]b\n\n{key: \(key)}\n"
                + "{start_of_chorus}\n[\(key)]c\n{end_of_chorus}\n"
            let fixture = PartFixture(source)
            let part = try fixture.part(from: (0, 1), to: (1, 0), bass: ["D", key], events: [
                PartEvent(chord: 1, at: 0, len: 480, deg: 2),
            ])
            return try fixture.notes(part).map(\.name)
        }
        #expect(try names("A") == ["B"])
        #expect(try names("Ab") == ["Bb"])
    }

    @Test
    func `a pin is honoured on a string the tuning has and ignored on one it lacks`() throws {
        let fixture = PartFixture()
        let pinned = try fixture.notes(Self.intoChorus(fixture, pin: "A1"))
        #expect(pinned.first?.position == FretPosition(string: 1, fret: 7))
        let open = try fixture.notes(Self.intoChorus(fixture, pin: "D2"))
        #expect(open.first?.position == FretPosition(string: 2, fret: 2))
        // No B string on EADG: the hand position decides, the pitch never changes.
        let missing = try fixture.notes(Self.intoChorus(fixture, pin: "B0"))
        #expect(missing.first?.midi == 40)
        #expect(missing.first?.position == FretPosition(string: 2, fret: 2))
    }

    @Test
    func `a note outside the range folds by octaves and is flagged`() throws {
        let fixture = PartFixture()
        let part = try fixture.part(from: (0, 2), to: (1, 0), bass: ["D", "G"], events: [
            PartEvent(chord: 0, at: 0, len: 480, deg: 0, oct: -2),
            PartEvent(chord: 0, at: 480, len: 480, deg: 0, oct: 2),
            PartEvent(chord: 0, at: 960, len: 480, deg: 0),
        ])
        let notes = try fixture.notes(part)
        #expect(notes.map(\.folded) == [true, false, false])
        #expect(notes.map(\.midi) == [38, 62, 38])
    }

    @Test
    func `an event past its chord's length is flagged and clipped events stay inside`() throws {
        let fixture = PartFixture()
        let part = try fixture.part(from: (0, 2), to: (1, 0), bass: ["D", "G"], events: [
            PartEvent(chord: 0, at: 1680, len: 960, deg: 2),
            PartEvent(chord: 0, at: 2400, len: 240, deg: 4),
        ])
        let notes = try fixture.notes(part)
        #expect(notes.map(\.outside) == [false, true])
        #expect(notes.first?.len == 240)
    }

    struct Played: Sendable {
        var articulations: Set<Articulation>
        var velocity: Int
        var length: Int
    }

    static let articulationRows = [
        Played(articulations: [], velocity: 96, length: 480),
        Played(articulations: [.ghost], velocity: 40, length: 240),
        Played(articulations: [.staccato], velocity: 96, length: 240),
        Played(articulations: [.accent], velocity: 116, length: 480),
        Played(articulations: [.slide], velocity: 81, length: 480),
        Played(articulations: [.hammer, .accent], velocity: 101, length: 480),
    ]

    @Test(arguments: articulationRows)
    func `articulations set the velocity and length played`(_ row: Played) throws {
        let articulations = row.articulations
        let fixture = PartFixture()
        let part = try fixture.part(from: (0, 2), to: (1, 0), bass: ["D", "G"], events: [
            PartEvent(chord: 0, at: 0, len: 480, deg: 0, articulations: articulations),
        ])
        let note = try #require(try fixture.notes(part).first)
        #expect(Int(note.playedVelocity) == row.velocity)
        #expect(note.playedLength == row.length)
    }

    @Test
    func `relative events are canonical`() {
        #expect(PartEvent.relative(chord: 0, at: 0, len: 1, semitones: -1).deg == 11)
        #expect(PartEvent.relative(chord: 0, at: 0, len: 1, semitones: -1).oct == -1)
        #expect(PartEvent.relative(chord: 0, at: 0, len: 1, semitones: 14).semitones == 14)
        #expect(PartEvent.stringPitch("A1") == 33)
        #expect(PartEvent.stringPitch("B0") == 23)
        #expect(PartEvent.stringPitch("Eb2") == 39)
        #expect(PartEvent.stringPitch("H2") == nil)
    }
}
