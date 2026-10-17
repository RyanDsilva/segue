import Diagrams
import MusicTheory
import Testing
import Tonic

/// Guitar shapes: the generator across tunings, the curated table, fingering and barres.
struct DiagramGuitarTests {
    @Test(arguments: Tuning.presets)
    func `generator yields playable shapes for a broad chord list`(tuning: Tuning) {
        var failures: [String] = []
        for chord in DiagramChords.broadList {
            let shapes = GuitarShapeGenerator.shapes(for: chord.tones, tuning: tuning)
            if shapes.isEmpty {
                failures.append("\(chord): no shape")
            }
            for shape in shapes {
                let problems = ShapeCheck.problems(shape, tones: chord.tones, tuning: tuning)
                if !problems.isEmpty {
                    failures.append("\(chord) \(ShapeCheck.text(shape)): \(problems)")
                }
            }
        }
        #expect(failures.isEmpty, "\(tuning.name):\n\(failures.joined(separator: "\n"))")
    }

    @Test
    func `generator ranks the familiar open shapes first in standard tuning`() {
        // Root letter + suffix -> expected frets.
        let expected: [String: String] = [
            "C": "x32010", "D": "xx0232", "E": "022100", "G": "320003", "A": "x02220",
            "Am": "x02210", "Em": "022000", "Dm": "xx0231", "E7": "020100", "F": "133211",
        ]
        for (name, frets) in expected {
            let tones = DiagramChords.tones(String(name.prefix(1)), String(name.dropFirst()))
            let best = GuitarShapeGenerator.shapes(for: tones, tuning: .standard, limit: 1).first
            #expect(best.map(ShapeCheck.text) == frets, "\(name)")
        }
    }

    @Test
    func `generator detects barres`() throws {
        let fMajor = try #require(
            GuitarShapeGenerator.shapes(for: DiagramChords.tones("F"), tuning: .standard).first,
        )
        #expect(fMajor.barres == [Barre(fret: 1, strings: 0 ... 5, finger: 1)])
        #expect(fMajor.fingers == [1, 3, 4, 2, 1, 1])

        let fSharp = try #require(
            GuitarShapeGenerator.shapes(for: DiagramChords.tones("F#"), tuning: .standard).first,
        )
        #expect(ShapeCheck.text(fSharp) == "244322")
        #expect(fSharp.barres == [Barre(fret: 2, strings: 0 ... 5, finger: 1)])
    }

    @Test
    func `shapes above the nut window carry a base fret`() throws {
        // C7(#9) has no open shape: the best one sits up the neck with a base fret label.
        let shape = try #require(
            GuitarShapeGenerator.shapes(for: DiagramChords.tones("C", "7(#9)"), tuning: .standard)
                .first,
        )
        #expect(shape.baseFret > 1)
        #expect(shape.frets.compactMap(\.self).allSatisfy { $0 <= 4 })
    }

    @Test
    func `drop D and open G use their low open strings`() throws {
        let dropD = try #require(
            GuitarShapeGenerator.shapes(for: DiagramChords.tones("D"), tuning: .dropD).first,
        )
        #expect(dropD.frets.first == 0, "\(ShapeCheck.text(dropD))")

        let openG = try #require(
            GuitarShapeGenerator.shapes(for: DiagramChords.tones("G"), tuning: .openG).first,
        )
        #expect(ShapeCheck.text(openG) == "x00000" || ShapeCheck.text(openG) == "000000")
    }

    @Test
    func `slash chords put the bass lowest`() throws {
        for (root, bass) in [("G", "B"), ("D", "F#"), ("C", "E"), ("A", "G")] {
            let tones = DiagramChords.tones(root, bass: bass)
            for tuning in Tuning.presets {
                let shape = try #require(
                    GuitarShapeGenerator.shapes(for: tones, tuning: tuning).first,
                    "\(root)/\(bass) in \(tuning.name)",
                )
                let lowest = try #require(shape.pitches(in: tuning).min())
                #expect(PitchClass(midi: lowest) == DiagramChords.pitchClass(bass))
            }
        }
    }

    @Test
    func `generator works for a custom seven-string tuning`() throws {
        let sevenString = try #require(Tuning(metaValue: "B1 E2 A2 D3 G3 B3 E4"))
        for chord in DiagramChords.broadList.prefix(60) {
            let shape = try #require(
                GuitarShapeGenerator.shapes(for: chord.tones, tuning: sevenString).first,
                "\(chord)",
            )
            #expect(ShapeCheck.problems(shape, tones: chord.tones, tuning: sevenString).isEmpty)
        }
    }

    @Test
    func `results are ranked distinct and limited`() {
        let shapes = GuitarShapeGenerator.shapes(
            for: DiagramChords.tones("A", "m7"),
            tuning: .standard,
            limit: 3,
        )
        #expect(shapes.count == 3)
        #expect(Set(shapes.map(\.absoluteFrets)).count == 3)
        #expect(GuitarShapeGenerator.shapes(
            for: DiagramChords.tones("A"),
            tuning: .standard,
            limit: 0,
        )
        .isEmpty)
    }

    // MARK: - Curated shapes

    @Test
    func `every curated shape sounds its chord and is playable`() {
        for entry in CuratedShapes.all {
            let problems = ShapeCheck.problems(entry.shape, tones: entry.tones, tuning: .standard)
            #expect(problems.isEmpty, "\(entry.name) \(ShapeCheck.text(entry.shape)): \(problems)")
            #expect(CuratedShapes.shape(for: entry.tones, tuning: .standard) == entry.shape)
            #expect(entry.shape.fingers.count == 6, "\(entry.name)")
        }
    }

    @Test
    func `curated shapes cover the common chords and only standard tuning`() {
        let names = Set(CuratedShapes.all.map(\.name))
        for name in ["C", "D", "E", "F", "G", "A", "B", "Am", "Bm", "Dm", "Em", "G/B", "D/F#"] {
            #expect(names.contains(name), "\(name)")
        }
        let cMajor = DiagramChords.tones("C")
        #expect(CuratedShapes.shape(for: cMajor, tuning: .standard) != nil)
        for tuning in [Tuning.dropD, .dadgad, .openG] {
            #expect(CuratedShapes.shape(for: cMajor, tuning: tuning) == nil)
        }
    }

    @Test
    func `curated matching ignores extension numbering`() {
        // add2 and add9 have the same pitch classes; both find the curated Cadd9.
        let add2 = ChordTones(
            root: PitchClass(0),
            formula: ChordFormula(intervals: [0, 2, 4, 7], essential: [0, 2, 4]),
        )
        #expect(CuratedShapes.shape(for: add2, tuning: .standard).map(ShapeCheck.text) == "x32030")
    }

    @Test
    func `curated barre shapes read their barre from the fingers`() throws {
        let bMinor = try #require(CuratedShapes.all.first { $0.name == "Bm" })
        #expect(bMinor.shape.baseFret == 1)
        #expect(bMinor.shape.barres == [Barre(fret: 2, strings: 1 ... 5, finger: 1)])
        let eFlat = try #require(CuratedShapes.all.first { $0.name == "Eb" })
        #expect(eFlat.shape.baseFret == 6)
        #expect(eFlat.shape.frets == [nil, 1, 3, 3, 3, 1])
        #expect(eFlat.shape.barres == [Barre(fret: 1, strings: 1 ... 5, finger: 1)])
    }

    // MARK: - Fingering

    @Test
    func `fingering assigns fingers in fret order and barres five or more notes`() throws {
        let cMajor = try #require(GuitarFingering.assign(absoluteFrets: [nil, 3, 2, 0, 1, 0]))
        #expect(cMajor.fingers == [nil, 3, 2, nil, 1, nil])
        #expect(cMajor.barre == nil)
        #expect(cMajor.fingerCount == 3)

        let bMinor = try #require(GuitarFingering.assign(absoluteFrets: [nil, 2, 4, 4, 3, 2]))
        #expect(bMinor.barre == Barre(fret: 2, strings: 1 ... 5, finger: 1))
        #expect(bMinor.fingers == [nil, 1, 3, 4, 2, 1])
        #expect(bMinor.fingerCount == 4)
    }

    @Test
    func `fingering rejects impossible hands`() {
        // Five fretted notes with an open string under the would-be barre.
        #expect(GuitarFingering.assign(absoluteFrets: [1, 3, 0, 2, 1, 1]) == nil)
        // Barre plus four more fingers.
        #expect(GuitarFingering.assign(absoluteFrets: [1, 2, 3, 4, 2, 1]) == nil)
    }
}
