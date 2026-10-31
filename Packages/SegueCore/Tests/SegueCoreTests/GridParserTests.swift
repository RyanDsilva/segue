import ChordPro
import Editing
import Library
import Testing

/// ChordPro grids read as timed chords (P8-7 section 5.5, R167 Q4).
struct GridParserTests {
    /// "G 2", "C 2": each chord and its length in cells of `cell` ticks.
    static func chart(_ body: String, header: String? = nil, time: String? = nil) -> [String] {
        let start = header.map { "{start_of_grid: \($0)}" } ?? "{start_of_grid}"
        let (document, _) = ChordProParser.parse(start + "\n" + body + "\n{end_of_grid}\n")
        let model = RenderModel(document: document, options: DisplayOptions())
        guard let section = model.sections.first else { return [] }
        let meter = Meter(time: time)
        return GridParser.parse(section, header: section.label, meter: meter).chords.map { chord in
            let beats = Double(chord.length) / Double(meter.ticksPerPulse)
            let text = beats == beats.rounded() ? String(Int(beats)) : String(beats)
            return "\(chord.token) \(text)"
        }
    }

    struct Row: Sendable, CustomTestStringConvertible {
        var name: String
        var body: String
        var header: String?
        var expected: [String]

        var testDescription: String {
            name
        }
    }

    @Test(arguments: [
        Row(name: "shape cells", body: "| G . | C . |", header: "1+4x2+4", expected: [
            "G 4", "C 4",
        ]),
        Row(name: "tokens are cells", body: "| G . . . | C . D . |", expected: [
            "G 4", "C 2", "D 2",
        ]),
        Row(name: "a slash restrikes", body: "| G / / / |", expected: ["G 4"]),
        Row(name: "a tilde shares a cell", body: "| G~C . |", header: "1x2", expected: [
            "G 1", "C 3",
        ]),
        Row(name: "percent repeats a measure", body: "| G . C . | % |", expected: [
            "G 2", "C 2", "G 2", "C 2",
        ]),
        Row(name: "double percent repeats two", body: "| G | C | %% | . |", expected: [
            "G 4", "C 4", "G 4", "C 4",
        ]),
        Row(name: "a repeat plays twice", body: "|: G | C :|", expected: [
            "G 4", "C 4", "G 4", "C 4",
        ]),
        Row(name: "voltas", body: "|: G | C |1 D :|2 E |", expected: [
            "G 4", "C 4", "D 4", "G 4", "C 4", "E 4",
        ]),
        Row(name: "margin text is ignored", body: "A || G . . . | C . . . | x2", expected: [
            "G 4", "C 4",
        ]),
        Row(name: "a strum line is ignored", body: "| G . . . |\n|S dn . up . |", expected: [
            "G 4",
        ]),
        Row(name: "an unknown token is text", body: "| G riff . . |", expected: ["G 4"]),
        Row(name: "legacy shape", body: "| G . | C . |", header: "4x2", expected: [
            "G 4", "C 4",
        ]),
        Row(name: "N.C. is a timed silence", body: "| N.C. . | G . |", expected: [
            "N.C. 4", "G 4",
        ]),
    ])
    func `grids`(_ row: Row) {
        #expect(Self.chart(row.body, header: row.header) == row.expected)
    }

    @Test
    func `a grid bar is the meter's bar`() {
        #expect(Self.chart("| G . . | C . . |", time: "3/4") == ["G 3", "C 3"])
        #expect(Self.chart("| G . | C . |", time: "6/8") == ["G 2", "C 2"])
    }

    @Test
    func `ordinals count written chords, repeats keep them`() throws {
        let (document, _) = ChordProParser.parse("{sog}\n|: G | C~D :|\n{eog}\n")
        let model = RenderModel(document: document, options: DisplayOptions())
        let section = try #require(model.sections.first)
        #expect(GridParser.writtenChords(section).map(\.token) == ["G", "C", "D"])
        let chart = GridParser.parse(section, header: nil, meter: .common)
        #expect(chart.chords.map(\.ordinal) == [0, 1, 2, 0, 1, 2])
    }

    @Test
    func `the shape is read from its attribute form`() {
        #expect(GridParser.shapeCells("shape=\"1+4x2+4\" label=\"Intro\"") == 2)
        #expect(GridParser.shapeCells("1+4x2+4") == 2)
        #expect(GridParser.shapeCells("Intro") == nil)
    }

    @Test
    func `a grid's section fingerprint counts its lines`() throws {
        let (document, _) = ChordProParser.parse("{sog}\n| G . . . |\n{eog}\n")
        let model = RenderModel(document: document, options: DisplayOptions())
        let one = try #require(SongSections.units(of: document).first)
        let (other, _) = ChordProParser.parse("{sog}\n| C . . . |\n{eog}\n")
        let two = try #require(SongSections.units(of: other).first)
        #expect(one.fingerprint != two.fingerprint)
        #expect(GridParser.isGrid(model.sections[0]))
    }
}
