import Diagrams
import MusicTheory
import Testing

/// Piano voicings: close root position near middle C, voice leading, left-hand bass.
struct DiagramPianoTests {
    struct Row: CustomStringConvertible {
        let name: String
        let tones: ChordTones
        let notes: [Int]
        let bass: Int

        var description: String {
            name
        }
    }

    /// Without a previous chord: root position, close, inside C3 ... C5 and as near middle
    /// C as fits; the bass (slash bass or root) is just below the right hand.
    static let table: [Row] = [
        Row(name: "C", tones: DiagramChords.tones("C"), notes: [60, 64, 67], bass: 48),
        Row(name: "G", tones: DiagramChords.tones("G"), notes: [55, 59, 62], bass: 43),
        Row(name: "F", tones: DiagramChords.tones("F"), notes: [53, 57, 60], bass: 41),
        Row(name: "Ab", tones: DiagramChords.tones("Ab"), notes: [56, 60, 63], bass: 44),
        Row(name: "B", tones: DiagramChords.tones("B"), notes: [59, 63, 66], bass: 47),
        Row(name: "Am", tones: DiagramChords.tones("A", "m"), notes: [57, 60, 64], bass: 45),
        Row(
            name: "Cmaj7",
            tones: DiagramChords.tones("C", "maj7"),
            notes: [60, 64, 67, 71],
            bass: 48,
        ),
        Row(
            name: "F#m7b5",
            tones: DiagramChords.tones("F#", "m7b5"),
            notes: [54, 57, 60, 64],
            bass: 42,
        ),
        Row(
            name: "D9",
            tones: DiagramChords.tones("D", "9"),
            notes: [50, 52, 54, 57, 60],
            bass: 38,
        ),
        // Six tones: the 5th is dropped to fit five fingers; 3rd, b7 and 13 stay.
        Row(
            name: "G13",
            tones: DiagramChords.tones("G", "13"),
            notes: [55, 57, 59, 64, 65],
            bass: 43,
        ),
        // Slash bass in the left hand, chord tone or not.
        Row(name: "G/B", tones: DiagramChords.tones("G", bass: "B"), notes: [55, 59, 62], bass: 47),
        Row(
            name: "C/Bb",
            tones: DiagramChords.tones("C", bass: "Bb"),
            notes: [60, 64, 67],
            bass: 58,
        ),
        Row(
            name: "D/F#",
            tones: DiagramChords.tones("D", bass: "F#"),
            notes: [62, 66, 69],
            bass: 54,
        ),
    ]

    @Test(arguments: table)
    func `default voicing table`(row: Row) {
        let voicing = PianoVoicingGenerator.voicing(for: row.tones, after: nil)
        #expect(voicing.notes == row.notes)
        #expect(voicing.bass == row.bass)
        #expect(voicing.root == row.tones.root)
    }

    @Test
    func `voice leading through I IV V I moves minimally`() {
        let voicings = PianoVoicingGenerator.voicings(for: [
            DiagramChords.tones("C"), DiagramChords.tones("F"), DiagramChords.tones("G"),
            DiagramChords.tones("C"),
        ])
        #expect(voicings.map(\.notes) == [[60, 64, 67], [60, 65, 69], [59, 62, 67], [60, 64, 67]])
        #expect(voicings.map(\.bass) == [48, 53, 55, 48])
    }

    @Test
    func `every chord in the broad list voices inside C3 to C5 with its essential tones`() {
        var previous: PianoVoicing?
        for chord in DiagramChords.broadList {
            for after in [nil, previous] {
                let voicing = PianoVoicingGenerator.voicing(for: chord.tones, after: after)
                let classes = Set(voicing.notes.map(PitchClass.init(midi:)))
                let essential = Set(chord.tones.formula.essential
                    .map { chord.tones.root.transposed(by: $0) })
                #expect(essential.isSubset(of: classes), "\(chord)")
                #expect(classes.isSubset(of: Set(chord.tones.pitchClasses)), "\(chord)")
                #expect(voicing.notes == voicing.notes.sorted(), "\(chord)")
                if let low = voicing.notes.first, let high = voicing.notes.last {
                    #expect(PianoVoicingGenerator.rightHandRange.contains(low), "\(chord)")
                    #expect(PianoVoicingGenerator.rightHandRange.contains(high), "\(chord)")
                    #expect(high - low < 12, "\(chord) is not a close voicing")
                    let bass = voicing.bass ?? Int.max
                    #expect(bass < low, "\(chord)")
                    #expect(PitchClass(midi: bass) == chord.tones.lowest, "\(chord)")
                }
                previous = voicing
            }
        }
    }

    @Test
    func `folded pitch classes keep display order`() {
        let voicing = PianoVoicingGenerator.voicing(for: DiagramChords.tones("C"), after: nil)
        #expect(voicing.foldedPitchClasses == [PitchClass(0), PitchClass(4), PitchClass(7)])
    }
}
