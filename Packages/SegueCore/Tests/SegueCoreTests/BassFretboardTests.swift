import Diagrams
import MusicTheory
import Testing

/// The fretboard core the stage mini neck and P8-4b's strip share (P8-4 sections 7.1, 11.1).
struct BassFretboardTests {
    typealias Pos = FretPosition

    static func pc(_ name: String) -> PitchClass {
        SongKey(parsing: name)?.tonic.pitchClass ?? PitchClass(0)
    }

    @Test
    func `every position of a note on frets 0 to 12`() {
        #expect(BassFretboard.positions(of: Self.pc("G"), tuning: .bassStandard4) == [
            Pos(string: 0, fret: 3), Pos(string: 1, fret: 10), Pos(string: 2, fret: 5),
            Pos(string: 3, fret: 0), Pos(string: 3, fret: 12),
        ])
    }

    @Test(arguments: [
        (Tuning.bassStandard4, "G", 3),
        (.bassStandard4, "D", 5),
        (.bassStandard4, "E", 0),
        (.bassStandard5, "G", 3),
        (.bassStandard5, "D", 3),
    ])
    func `home fret`(tuning: Tuning, tonic: String, fret: Int) {
        #expect(BassFretboard.homeFret(tonic: Self.pc(tonic), tuning: tuning) == fret)
    }

    @Test(arguments: [
        // EADG, home 3 (key G).
        (Tuning.bassStandard4, 3, "G", 0, 3),
        (.bassStandard4, 3, "C", 1, 3),
        (.bassStandard4, 3, "D", 1, 5),
        (.bassStandard4, 3, "Em", 0, 0),
        (.bassStandard4, 3, "Am", 0, 5), // ties with the open A: the lower string wins
        (.bassStandard4, 3, "B", 1, 2),
        (.bassStandard4, 3, "F#", 0, 2),
        // EADG, home 5 (key D).
        (.bassStandard4, 5, "A", 0, 5),
        (.bassStandard4, 5, "Bm", 0, 7),
        (.bassStandard4, 5, "G", 2, 5),
        // BEADG, home 3 (key D).
        (.bassStandard5, 3, "D", 0, 3),
        (.bassStandard5, 3, "G", 1, 3),
        (.bassStandard5, 3, "B", 0, 0),
        // DADG, home 0 (key D).
        (.bassDropD, 0, "D", 0, 0),
        (.bassDropD, 0, "A", 1, 0),
        (.bassDropD, 0, "G", 3, 0),
    ])
    func `suggested position`(tuning: Tuning, home: Int, note: String, string: Int, fret: Int) {
        let suggested = BassFretboard.suggested(Self.pc(note), home: home, tuning: tuning)
        #expect(suggested == Pos(string: string, fret: fret))
    }

    @Test
    func `root fifth octave around a root`() throws {
        let root = Pos(string: 0, fret: 3) // G on the E string, key G
        let shape = BassFretboard.shape(around: root, fifth: 7, home: 3, tuning: .bassStandard4)
        // Fifth D at A5 (and the open D); no fifth below (no lower string); octave G at D5
        // and the open G string.
        #expect(shape.contains(Pos(string: 1, fret: 5)))
        #expect(shape.contains(Pos(string: 2, fret: 5)))
        #expect(shape.contains(Pos(string: 3, fret: 0)))
        #expect(shape.allSatisfy { BassFretboard.pitch($0, tuning: .bassStandard4) >= 31 })

        let bdim = try #require(ChordSymbol(parsing: "Bdim"))
        #expect(BassFretboard.fifthInterval(of: bdim.formula) == 6)
        let augmented = try #require(ChordSymbol(parsing: "Caug"))
        #expect(BassFretboard.fifthInterval(of: augmented.formula) == 8)
        let major = try #require(ChordSymbol(parsing: "Gmaj7"))
        #expect(BassFretboard.fifthInterval(of: major.formula) == 7)

        // G/B: the octave only.
        let slash = BassFretboard.shape(
            around: Pos(string: 1, fret: 2),
            fifth: nil,
            home: 3,
            tuning: .bassStandard4,
        )
        #expect(slash == [Pos(string: 3, fret: 4)])
    }

    @Test
    func `the neck window is the box and shifts to the suggested position`() {
        #expect(BassFretboard.window(home: 3, including: Pos(string: 0, fret: 3)) == 2 ... 6)
        #expect(BassFretboard.window(home: 3, including: Pos(string: 0, fret: 0)) == 0 ... 4)
        #expect(BassFretboard.window(home: 3, including: Pos(string: 0, fret: 9)) == 5 ... 9)
        #expect(BassFretboard.window(home: 0, including: nil) == 0 ... 4)
    }
}
