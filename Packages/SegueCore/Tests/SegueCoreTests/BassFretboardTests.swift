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
    func `every chord tone in the window with its degree`() throws {
        let tones = { (chord: String, frets: ClosedRange<Int>) throws -> Set<String> in
            let symbol = try #require(ChordSymbol(parsing: chord))
            return Set(BassFretboard.tones(of: symbol, frets: frets, tuning: .bassStandard4)
                .map { "\($0.position) \($0.degree) \($0.role)" })
        }
        // G in key G, the window 2 ... 6: the two Gs, both Bs and the D on the A string.
        #expect(try tones("G", 2 ... 6) == [
            "0:3 R bass", "2:5 R bass", "1:2 3 tone", "3:4 3 tone", "1:5 5 tone",
        ])
        // G/B: B is the note to play (the third), G is the root.
        #expect(try tones("G/B", 2 ... 6) == [
            "0:3 R root", "2:5 R root", "1:2 3 bass", "3:4 3 bass", "1:5 5 tone",
        ])
        // Am7 in the open position: R, b3, 5, b7.
        #expect(try tones("Am7", 0 ... 4) == [
            "0:0 5 tone", "0:3 b7 tone", "1:0 R bass", "1:3 b3 tone", "2:2 5 tone",
            "3:0 b7 tone", "3:2 R bass",
        ])
        // A slash bass outside the chord is named from the root (C/D: 9 as "2").
        #expect(try tones("C/D", 0 ... 0).contains("2:0 2 bass"))
        #expect(BassFretboard.degree(14) == "9")
        #expect(BassFretboard.degree(10) == "b7")
        #expect(BassFretboard.degree(6) == "b5")
    }

    @Test
    func `a walk-up path falls on the window near the chord`() {
        let start = Pos(string: 0, fret: 3) // G, key G
        // G walks up A B into C: A on the E string, B on the A string.
        #expect(BassFretboard.walkPath(
            [Self.pc("A"), Self.pc("B")],
            ascending: true,
            from: start,
            frets: 2 ... 6,
            tuning: .bassStandard4,
        ) == [Pos(string: 0, fret: 5), Pos(string: 1, fret: 2)])
        // G walks down F# E into D: E is the open string, outside frets 2 ... 6.
        #expect(BassFretboard.walkPath(
            [Self.pc("F#"), Self.pc("E")],
            ascending: false,
            from: start,
            frets: 2 ... 6,
            tuning: .bassStandard4,
        ) == [Pos(string: 0, fret: 2), nil])
        #expect(BassFretboard.walkPath(
            [Self.pc("F#"), Self.pc("E")],
            ascending: false,
            from: start,
            frets: 0 ... 4,
            tuning: .bassStandard4,
        ) == [Pos(string: 0, fret: 2), Pos(string: 0, fret: 0)])
    }

    @Test
    func `the neck window is the box and shifts to the suggested position`() {
        #expect(BassFretboard.window(home: 3, including: Pos(string: 0, fret: 3)) == 2 ... 6)
        #expect(BassFretboard.window(home: 3, including: Pos(string: 0, fret: 0)) == 0 ... 4)
        #expect(BassFretboard.window(home: 3, including: Pos(string: 0, fret: 9)) == 5 ... 9)
        #expect(BassFretboard.window(home: 0, including: nil) == 0 ... 4)
    }
}
