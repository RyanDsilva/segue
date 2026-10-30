import ChordPro
import Editing
import Library
import Shows
import Testing

/// Beat estimates per chord (P8-4 section 8.5).
struct ChordBeatsTests {
    static func estimates(_ body: String, time: String? = nil) -> [ChordBeats.Estimate] {
        let header = time.map { "{time: \($0)}\n" } ?? ""
        let (document, _) = ChordProParser.parse(header + body + "\n")
        let model = RenderModel(document: document, options: DisplayOptions())
        let result = ChordBeats.estimate(model.sections, time: model.header.time)
        return result.keys.sorted().compactMap { result[$0] }
    }

    struct BarRow: Sendable, CustomTestStringConvertible {
        var line: String
        var time: String?
        var beats: [Int]

        var testDescription: String {
            "\(line) \(time ?? "")"
        }
    }

    @Test(arguments: [
        BarRow(line: "| [G] . . . | [C] . . . |", beats: [4, 4]),
        BarRow(line: "| [G] [D] | [C] |", beats: [2, 2, 4]),
        BarRow(line: "| [G] | % | [C] |", beats: [8, 4]),
        BarRow(line: "[|] [G] [|] [C] [|]", beats: [4, 4]),
        BarRow(line: "| [G] | [C] |", time: "3/4", beats: [3, 3]),
        BarRow(line: "| [G] | [C] |", time: "6/8", beats: [2, 2]),
    ])
    func `bar lines`(_ row: BarRow) {
        let result = Self.estimates(row.line, time: row.time)
        #expect(result.map(\.beats) == row.beats.map(Optional.some))
        #expect(result.allSatisfy { $0.source == .barLines })
    }

    @Test
    func `beat marks`() {
        let result = Self.estimates("[G] / / / [C] / /")
        #expect(result.map(\.beats) == [4, 3])
        #expect(result.allSatisfy { $0.source == .beatMarks })
    }

    @Test
    func `one chord on a lyric line with a time signature is a bar`() {
        let result = Self.estimates("[G]Hello there my friend", time: "4/4")
        #expect(result == [ChordBeats.Estimate(beats: 4, source: .meterLine)])
    }

    @Test
    func `two chords on a lyric line without marks are unknown`() {
        let result = Self.estimates("[G]Hello [C]there", time: "4/4")
        #expect(result == [.unknown, .unknown])
    }

    @Test
    func `no time and no marks is unknown`() {
        #expect(Self.estimates("[G]Hello there") == [.unknown])
    }

    @Test
    func `a grid section contributes nothing`() {
        let result = Self.estimates("{start_of_grid}\n| G . . . | C . . . |\n{end_of_grid}")
        #expect(result.isEmpty)
    }

    @Test
    func `keys are section and chord ordinal`() {
        let (document, _) = ChordProParser.parse("""
        {start_of_verse}
        | [G] . . . | [C] . . . |
        {end_of_verse}
        {start_of_chorus}
        [D] / / / [G] /
        {end_of_chorus}

        """)
        let model = RenderModel(document: document, options: DisplayOptions())
        let result = ChordBeats.estimate(model.sections, time: nil)
        #expect(result[ChordPosition(section: 0, chord: 1)]?.beats == 4)
        #expect(result[ChordPosition(section: 1, chord: 0)]?.beats == 4)
        #expect(result[ChordPosition(section: 1, chord: 1)]?.beats == 2)
    }

    @Test(arguments: ["2/4", "3/4", "4/4", "6/8", "9/8", "12/8", "5/4"])
    func `the metronome and the beat estimate share one pulses rule`(time: String) {
        #expect(Metadata.pulses(ofTime: time) == MetronomeMeter(time: time).pulses)
    }

    @Test
    func `pulses of common meters`() {
        #expect(Metadata.pulses(ofTime: nil) == 4)
        #expect(Metadata.pulses(ofTime: "6/8") == 2)
        #expect(Metadata.pulses(ofTime: "12/8") == 4)
        #expect(Metadata.pulses(ofTime: "3/4") == 3)
    }
}
