import Diagrams
import MusicTheory
import Testing

/// A note on `string` (nil: no playable position) at `fret`.
private func note(
    _ tick: Int,
    _ string: Int?,
    _ fret: Int = 7,
    _ articulations: Set<Articulation> = [],
    name: String = "E",
    landing: Bool = false,
) -> TabNote {
    TabNote(
        tick: tick,
        length: 240,
        position: string.map { FretPosition(string: $0, fret: fret) },
        articulations: articulations,
        name: name,
        isLanding: landing,
    )
}

/// The mini tab's layout (P8-7 sections 12.6, 12.8): columns in proportion to ticks, lines
/// per string, articulations, bar lines, chord names, collisions and the spoken text.
struct TabLayoutTests {
    /// Every character 5 pt wide, so widths are exact.
    static func measure(_ text: String) -> Double {
        Double(text.count) * 5
    }

    static func layout(
        _ notes: [TabNote],
        chords: [(tick: Int, name: String)] = [],
        ticks: Range<Int> = 0 ..< 1920,
        pulses: [Int] = [],
        bars: [Int] = [],
        tuning: Tuning = .bassStandard4,
        width: Double = 200,
    ) -> TabLayout {
        TabLayout.layout(
            notes: notes,
            chords: chords,
            ticks: ticks,
            pulses: pulses,
            bars: bars,
            tuning: tuning,
            width: width,
            measure: measure,
        )
    }

    /// Where a glyph at `tick` starts, read off bar lines at 0 and 1920.
    static func onset(_ tick: Int, _ tab: TabLayout) -> Double {
        let start = tab.barLines[0]
        return start + (tab.barLines[1] - start) * Double(tick) / 1920
            + TabLayout.Metrics().onsetInset
    }

    static func line(_ layout: TabLayout, _ string: Int) throws -> TabLayout.Line {
        try #require(layout.lines.first { $0.string == string })
    }

    @Test(arguments: [
        [0, 480, 960, 1440],
        [0, 240, 1200, 1680],
        [120, 600, 1800],
    ])
    func `glyphs sit in proportion to their ticks`(ticks: [Int]) throws {
        let tab = Self.layout(ticks.enumerated().map { note($1, $0 % 4) })
        let xs = tab.glyphs.map(\.x)
        let first = try #require(xs.first)
        let last = try #require(xs.last)
        for (tick, x) in zip(ticks, xs) {
            let fraction = Double(tick - ticks[0]) / Double(ticks[ticks.count - 1] - ticks[0])
            #expect(abs((x - first) / (last - first) - fraction) < 1e-9)
        }
        // A note on the first tick starts just right of the label column and its bar line.
        let start = Self.layout([note(0, 0)], bars: [0])
        #expect(start.glyphs[0].x > start.barLines[0])
        #expect(start.barLines[0] > start.lines[0].labelX + Self.measure("G"))
    }

    @Test(arguments: [
        (Tuning.bassStandard4, ["G", "D", "A", "E"]),
        (.bassStandard5, ["G", "D", "A", "E", "B"]),
        (.bassHighC5, ["C", "G", "D", "A", "E"]),
        (.bassHalfDown4, ["F#", "C#", "G#", "D#"]),
    ])
    func `one line per string, the highest on top, labelled with its open letter`(
        tuning: Tuning,
        labels: [String],
    ) {
        let tab = Self.layout([], tuning: tuning)
        #expect(tab.lines.map(\.label) == labels)
        #expect(tab.lines.map(\.string) == Array((0 ..< labels.count).reversed()))
        #expect(zip(tab.lines, tab.lines.dropFirst()).allSatisfy { $0.y < $1.y })
        // Labels right-align in their column.
        let ends = Set(tab.lines.map { $0.labelX + Self.measure($0.label) })
        #expect(ends.count == 1)
    }

    @Test
    func `five strings are taller than four by one line`() {
        let four = Self.layout([], tuning: .bassStandard4)
        let five = Self.layout([], tuning: .bassStandard5)
        #expect(five.height - four.height == TabLayout.Metrics().lineGap)
    }

    @Test(arguments: [
        (Tuning.bassStandard4, 0), (.bassStandard4, 1), (.bassStandard4, 3),
        (.bassStandard5, 0), (.bassStandard5, 4),
    ])
    func `a note pinned to a string lands on that string's line`(
        tuning: Tuning,
        string: Int,
    ) throws {
        let tab = Self.layout([note(480, string, 5)], tuning: tuning)
        #expect(try tab.glyphs[0].y == Self.line(tab, string).y)
        #expect(tab.glyphs[0].string == string)
    }

    /// Rows: the articulations, then the glyph's text and any mark drawn with it.
    @Test(arguments: [
        ([], ["7"]),
        ([.slide], ["s7"]),
        ([.hammer], ["h7"]),
        ([.pull], ["p7"]),
        ([.ghost], ["x"]),
        ([.accent], ["7", ">"]),
        ([.staccato], ["7", "."]),
        ([.slide, .accent], ["s7", ">"]),
    ] as [(Set<Articulation>, [String])])
    func `articulations prefix the fret or mark it above or below the staff`(
        articulations: Set<Articulation>,
        drawn: [String],
    ) throws {
        let tab = Self.layout([note(480, 1, 7, articulations)])
        let glyph = tab.glyphs[0]
        #expect([glyph.text] + tab.marks.map(\.text) == drawn)
        guard let placed = tab.marks.first else { return }
        // Centred over the glyph: accents above the top line, staccato below the bottom.
        #expect(abs(placed.x + placed.width / 2 - (glyph.x + glyph.width / 2)) < 1e-9)
        let top = try #require(tab.lines.first).y
        let bottom = try #require(tab.lines.last).y
        #expect(placed.text == ">" ? placed.y < top : placed.y > bottom)
    }

    @Test
    func `a note with no playable position draws as a question mark mid-staff`() throws {
        let tab = Self.layout([note(480, nil)])
        #expect(tab.glyphs.map(\.text) == ["?"])
        #expect(tab.glyphs[0].string == nil)
        let top = try #require(tab.lines.first).y
        let bottom = try #require(tab.lines.last).y
        #expect(tab.glyphs[0].y == (top + bottom) / 2)
    }

    @Test(arguments: [
        ([0, 1920, 3840], 3), ([0, 1920], 2), ([-1920, 1920, 5760], 1), ([], 0),
    ])
    func `a bar line at each bar in the range, either end included`(
        bars: [Int],
        count: Int,
    ) {
        let tab = Self.layout([], ticks: 0 ..< 3840, bars: bars)
        #expect(tab.barLines.count == count)
        #expect(zip(tab.barLines, tab.barLines.dropFirst()).allSatisfy { $0 < $1 })
    }

    @Test
    func `bar lines and beat ticks share the glyphs' proportional columns`() {
        let pulses = Array(stride(from: 0, to: 3840, by: 480))
        let tab = Self.layout(
            [note(1920, 0)],
            ticks: 0 ..< 3840,
            pulses: pulses + [3840],
            bars: [0, 1920, 3840],
        )
        #expect(tab.beatTicks.count == 8)
        let gaps = zip(tab.beatTicks, tab.beatTicks.dropFirst()).map { $1 - $0 }
        #expect(gaps.allSatisfy { abs($0 - gaps[0]) < 1e-9 })
        // The middle bar line is half way; the note on it starts just after it.
        #expect(abs(tab.barLines[1] - (tab.barLines[0] + tab.barLines[2]) / 2) < 1e-9)
        #expect(tab.glyphs[0].x == tab.barLines[1] + TabLayout.Metrics().onsetInset)
        #expect(tab.rulerY > tab.lines.last?.y ?? 0)
    }

    @Test
    func `chord names sit above the staff at their onsets and outside ones are dropped`() {
        let tab = Self.layout(
            [note(0, 0), note(960, 1)],
            chords: [(960, "A"), (0, "E"), (1920, "B"), (-480, "D")],
        )
        #expect(tab.chords.map(\.text) == ["E", "A"])
        #expect(tab.chords.map(\.x) == tab.glyphs.map(\.x))
        #expect(tab.chords.allSatisfy { $0.y < (tab.lines.first?.y ?? 0) })
    }

    @Test(arguments: [
        ([(0, "E"), (1, "F#m7")], true),
        ([(0, "Cmaj7"), (100, "D")], true),
        ([(0, "E"), (960, "A")], false),
    ] as [([(Int, String)], Bool)])
    func `chord names that would collide are nudged right`(
        chords: [(Int, String)],
        nudged: Bool,
    ) {
        let tab = Self.layout([], chords: chords.map { (tick: $0.0, name: $0.1) }, bars: [0, 1920])
        let first = tab.chords[0]
        let second = tab.chords[1]
        #expect(second.x >= first.x + first.width + TabLayout.Metrics().glyphGap)
        #expect((second.x == Self.onset(chords[1].0, tab)) == !nudged)
    }

    /// Rows: the notes, then whether any glyph had to move.
    @Test(arguments: [
        ([note(0, 1, 12, [.slide]), note(1, 1, 10, [.slide]), note(2, 1, 9, [.slide])], true),
        ([note(0, 1, 12, [.slide]), note(1, 2, 10, [.slide])], false),
        ([note(0, nil), note(1, nil)], true),
        ([note(0, 1, 7, [.slide]), note(960, 1, 9, [.slide])], false),
    ] as [([TabNote], Bool)])
    func `glyphs that would collide on one line are nudged right, never overlapping`(
        notes: [TabNote],
        nudged: Bool,
    ) {
        let tab = Self.layout(notes, bars: [0, 1920])
        #expect(tab.glyphs.count == notes.count)
        for (left, right) in zip(tab.glyphs, tab.glyphs.dropFirst()) where left.y == right.y {
            #expect(right.x >= left.maxX + TabLayout.Metrics().glyphGap)
        }
        let unmoved = tab.glyphs.allSatisfy { abs($0.x - Self.onset($0.tick, tab)) < 1e-9 }
        #expect(unmoved == !nudged)
    }

    @Test
    func `lines are broken behind the glyphs on them only`() throws {
        let tab = Self.layout([note(480, 1, 12), note(1440, 1, 3)])
        let aString = try Self.line(tab, 1)
        #expect(aString.segments.count == 3)
        for glyph in tab.glyphs {
            let clear = aString.segments.allSatisfy {
                $0.upperBound <= glyph.x || $0.lowerBound >= glyph.maxX
            }
            #expect(clear)
        }
        #expect(try Self.line(tab, 0).segments.count == 1)
        #expect(try Self.line(tab, 0).segments.first?.upperBound == 200)
    }

    @Test(arguments: [
        (
            [note(0, 1, 7), note(480, 1, 9), note(960, 2, 7), note(
                1920,
                1,
                0,
                name: "A",
                landing: true,
            )],
            "Tab: A string 7, 9, D string 7, then A",
        ),
        (
            [note(0, 0, 2, [.slide]), note(240, 0, 4, [.ghost]), note(480, 1, 5, [.accent])],
            "Tab: E string slide 2, ghost, A string accented 5",
        ),
        (
            [note(0, nil, name: "F#"), note(480, 1, 9, name: "F#", landing: true)],
            "Tab: F sharp with no position, then F sharp",
        ),
        ([note(480, 3, 3), note(0, 3, 1, [.hammer])], "Tab: G string hammer-on 1, 3"),
        ([], "Tab: no notes"),
    ] as [([TabNote], String)])
    func `the spoken text reads the tab string by string, the landing last`(
        notes: [TabNote],
        spoken: String,
    ) {
        #expect(Self.layout(notes).spoken == spoken)
        #expect(TabLayout.spoken(notes, tuning: .bassStandard4) == spoken)
    }

    @Test
    func `the landing note is drawn in the landing bar and flagged`() {
        let tab = Self.layout(
            [note(0, 1, 7), note(1920, 1, 0, name: "A", landing: true)],
            ticks: 0 ..< 2400,
            bars: [0, 1920],
        )
        #expect(tab.glyphs.map(\.isLanding) == [false, true])
        #expect(tab.glyphs[1].x > tab.barLines[1])
        #expect(tab.glyphs[1].text == "0")
    }
}
