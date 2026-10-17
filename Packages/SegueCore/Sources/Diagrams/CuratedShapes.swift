// Owner: unit B (Diagrams).
//
// Hand-authored standard-tuning shapes (E2 A2 D3 G3 B3 E4): the open and barre shapes most
// charts use. Authored by us from first principles, so there is no licence question. A test
// checks every row sounds exactly its chord, with the right bass and four fingers at most.

import MusicTheory

/// One curated row: a chord and its fingering in absolute frets.
struct CuratedRow {
    let name: String
    let tones: ChordTones
    let shape: GuitarShape

    /// - Parameters:
    ///   - frets: one character per string, low E first: `x` muted, `0` open, `1`-`9` the
    ///     absolute fret.
    ///   - fingers: one character per string: `-` or `0` none, `1`-`4` the finger. A finger
    ///     on several strings at one fret is a barre.
    init(
        _ name: String,
        root: String,
        bass: String? = nil,
        _ quality: Quality,
        _ frets: String,
        _ fingers: String,
    ) {
        self.name = name
        tones = ChordTones(
            root: Self.pitchClass(root),
            bass: bass.map(Self.pitchClass),
            formula: quality.formula,
        )
        shape = GuitarShape(
            absoluteFrets: frets.map(\.wholeNumberValue),
            fingers: fingers.map { character in
                character.wholeNumberValue.flatMap { $0 == 0 ? nil : $0 }
            },
        )
    }

    /// Pitch class of a note name used in the table (a test checks every row's content).
    private static func pitchClass(_ name: String) -> PitchClass {
        let names = [
            "C": 0, "C#": 1, "D": 2, "Eb": 3, "E": 4, "F": 5, "F#": 6, "G": 7, "Ab": 8, "A": 9,
            "Bb": 10, "B": 11,
        ]
        return PitchClass(names[name] ?? 0)
    }

    /// Chord qualities used by the table, with the generator's notion of essential tones.
    enum Quality {
        case major
        case minor
        case dominant7
        case major7
        case minor7
        case sus2
        case sus4
        case add9
        case major6

        var formula: ChordFormula {
            switch self {
            case .major: ChordFormula(intervals: [0, 4, 7], essential: [0, 4])
            case .minor: ChordFormula(intervals: [0, 3, 7], essential: [0, 3])
            case .dominant7: ChordFormula(intervals: [0, 4, 7, 10], essential: [0, 4, 10])
            case .major7: ChordFormula(intervals: [0, 4, 7, 11], essential: [0, 4, 11])
            case .minor7: ChordFormula(intervals: [0, 3, 7, 10], essential: [0, 3, 10])
            case .sus2: ChordFormula(intervals: [0, 2, 7], essential: [0, 2])
            case .sus4: ChordFormula(intervals: [0, 5, 7], essential: [0, 5])
            case .add9: ChordFormula(intervals: [0, 4, 7, 14], essential: [0, 4, 14])
            case .major6: ChordFormula(intervals: [0, 4, 7, 9], essential: [0, 4, 9])
            }
        }
    }
}

enum CuratedTable {
    // swiftformat:disable all
    static let rows: [CuratedRow] = [
        // Major
        CuratedRow("C", root: "C", .major, "x32010", "-32010"),
        CuratedRow("D", root: "D", .major, "xx0232", "--0132"),
        CuratedRow("E", root: "E", .major, "022100", "023100"),
        CuratedRow("F", root: "F", .major, "133211", "134211"),
        CuratedRow("G", root: "G", .major, "320003", "210003"),
        CuratedRow("A", root: "A", .major, "x02220", "-01230"),
        CuratedRow("B", root: "B", .major, "x24442", "-12341"),
        CuratedRow("Bb", root: "Bb", .major, "x13331", "-12341"),
        CuratedRow("F#", root: "F#", .major, "244322", "134211"),
        CuratedRow("C#", root: "C#", .major, "x46664", "-12341"),
        CuratedRow("Eb", root: "Eb", .major, "x68886", "-12341"),
        CuratedRow("Ab", root: "Ab", .major, "466544", "134211"),
        // Minor
        CuratedRow("Am", root: "A", .minor, "x02210", "-02310"),
        CuratedRow("Dm", root: "D", .minor, "xx0231", "--0231"),
        CuratedRow("Em", root: "E", .minor, "022000", "023000"),
        CuratedRow("Bm", root: "B", .minor, "x24432", "-13421"),
        CuratedRow("F#m", root: "F#", .minor, "244222", "134111"),
        CuratedRow("C#m", root: "C#", .minor, "x46654", "-13421"),
        CuratedRow("Fm", root: "F", .minor, "133111", "134111"),
        CuratedRow("Gm", root: "G", .minor, "355333", "134111"),
        CuratedRow("Cm", root: "C", .minor, "x35543", "-13421"),
        CuratedRow("Bbm", root: "Bb", .minor, "x13321", "-13421"),
        CuratedRow("Ebm", root: "Eb", .minor, "x68876", "-13421"),
        CuratedRow("G#m", root: "Ab", .minor, "466444", "134111"),
        // Dominant 7th
        CuratedRow("A7", root: "A", .dominant7, "x02020", "-01020"),
        CuratedRow("B7", root: "B", .dominant7, "x21202", "-21304"),
        CuratedRow("C7", root: "C", .dominant7, "x32310", "-32410"),
        CuratedRow("D7", root: "D", .dominant7, "xx0212", "--0213"),
        CuratedRow("E7", root: "E", .dominant7, "020100", "020100"),
        CuratedRow("F7", root: "F", .dominant7, "131211", "131211"),
        CuratedRow("G7", root: "G", .dominant7, "320001", "320001"),
        // Minor 7th
        CuratedRow("Am7", root: "A", .minor7, "x02010", "-02010"),
        CuratedRow("Bm7", root: "B", .minor7, "x20202", "-10203"),
        CuratedRow("Dm7", root: "D", .minor7, "xx0211", "--0211"),
        CuratedRow("Em7", root: "E", .minor7, "020000", "020000"),
        CuratedRow("F#m7", root: "F#", .minor7, "242222", "131111"),
        // Major 7th
        CuratedRow("Cmaj7", root: "C", .major7, "x32000", "-32000"),
        CuratedRow("Dmaj7", root: "D", .major7, "xx0222", "--0111"),
        CuratedRow("Emaj7", root: "E", .major7, "021100", "031200"),
        CuratedRow("Fmaj7", root: "F", .major7, "xx3210", "--3210"),
        CuratedRow("Gmaj7", root: "G", .major7, "320002", "320001"),
        CuratedRow("Amaj7", root: "A", .major7, "x02120", "-02130"),
        // Suspended, added and sixth
        CuratedRow("Asus2", root: "A", .sus2, "x02200", "-01200"),
        CuratedRow("Asus4", root: "A", .sus4, "x02230", "-01230"),
        CuratedRow("Dsus2", root: "D", .sus2, "xx0230", "--0130"),
        CuratedRow("Dsus4", root: "D", .sus4, "xx0233", "--0134"),
        CuratedRow("Esus4", root: "E", .sus4, "022200", "023400"),
        CuratedRow("Cadd9", root: "C", .add9, "x32030", "-21030"),
        CuratedRow("Gadd9", root: "G", .add9, "320203", "210304"),
        CuratedRow("A6", root: "A", .major6, "x02222", "-01111"),
        CuratedRow("D6", root: "D", .major6, "xx0202", "--0102"),
        // Slash chords
        CuratedRow("G/B", root: "G", bass: "B", .major, "x20003", "-10002"),
        CuratedRow("D/F#", root: "D", bass: "F#", .major, "200232", "100243"),
        CuratedRow("D/A", root: "D", bass: "A", .major, "x00232", "-00132"),
        CuratedRow("C/E", root: "C", bass: "E", .major, "032010", "032010"),
        CuratedRow("C/G", root: "C", bass: "G", .major, "332010", "342010"),
        CuratedRow("F/C", root: "F", bass: "C", .major, "x33211", "-34211"),
        CuratedRow("Am/G", root: "A", bass: "G", .minor, "3x2210", "4-2310"),
    ]
    // swiftformat:enable all
}
