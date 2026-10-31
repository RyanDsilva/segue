import ChordPro
import Editing
import Foundation
import Library
import MusicTheory
import Testing

/// The one timing system (P8-7 section 5, R167 Q1): layers, pushes, sub-beat lengths,
/// passes, slices and the bar grid, through real render models.
struct SongTimelineTests {
    struct Song {
        var document: SongDocument
        var model: RenderModel
        var units: [SongSectionUnit]

        init(_ source: String) {
            (document, _) = ChordProParser.parse(source)
            model = RenderModel(document: document, options: DisplayOptions())
            units = SongSections.units(of: document)
        }

        func timeline(_ timing: ChordTiming = ChordTiming(), order: [PlayedPass]? = nil)
            -> SongTimeline
        {
            SongTimeline.build(
                document: document,
                sections: model.sections,
                units: units,
                timing: timing,
                order: order,
            )
        }

        /// A correction for the chord at `position`.
        func override(
            _ position: ChordPosition,
            beats: Int,
            ticks: Int? = nil,
            push: Push? = nil,
            source: ChordBeatsOverride.Source? = nil,
        ) throws -> ChordBeatsOverride {
            let anchor = try #require(ChordAnchors.anchor(
                at: position,
                units: units,
                sections: model.sections,
            ))
            return ChordBeatsOverride(
                anchor: anchor,
                beats: beats,
                ticks: ticks,
                push: push,
                source: source,
            )
        }
    }

    /// "G 4" per chord: the token and its length in pulses (fractions as decimals).
    static func lengths(_ timeline: SongTimeline) -> [String] {
        timeline.chords.map { chord in
            let pulses = Double(chord.length) / Double(chord.meter.ticksPerPulse)
            let text = pulses == pulses.rounded() ? String(Int(pulses)) : String(pulses)
            return "\(chord.token) \(text)"
        }
    }

    struct RuleRow: Sendable, CustomTestStringConvertible {
        var name: String
        var source: String
        var rule: TimingRule?
        var expected: [String]

        var testDescription: String {
            name
        }
    }

    @Test(arguments: [
        RuleRow(name: "a bar per chord in 4/4", source: "[G]a [C]b\n", expected: ["G 4", "C 4"]),
        RuleRow(
            name: "a bar per chord in 3/4",
            source: "{time: 3/4}\n[G]a [C]b\n",
            expected: ["G 3", "C 3"],
        ),
        RuleRow(
            name: "6/8 counts dotted quarters",
            source: "{time: 6/8}\n[G]a [C]b\n",
            expected: ["G 2", "C 2"],
        ),
        RuleRow(
            name: "half bars",
            source: "[G]a [C]b\n",
            rule: .each(.halfBar),
            expected: ["G 2", "C 2"],
        ),
        RuleRow(
            name: "two bars",
            source: "{time: 3/4}\n[G]a [C]b\n",
            rule: .each(.twoBars),
            expected: ["G 6", "C 6"],
        ),
        RuleRow(name: "n beats", source: "[G]a [C]b\n", rule: .beats(3), expected: ["G 3", "C 3"]),
        RuleRow(
            name: "a line shared evenly, the remainder to the first",
            source: "{time: 3/4}\n[G]a [C]b\n",
            rule: .line(1),
            expected: ["G 2", "C 1"],
        ),
        RuleRow(
            name: "a chordless lyric line extends the chord before",
            source: "[G]a\nno chords here\n[C]b\n",
            expected: ["G 8", "C 4"],
        ),
        RuleRow(
            name: "under a line rule it extends by n bars",
            source: "[G]a\nno chords here\n",
            rule: .line(2),
            expected: ["G 16"],
        ),
        RuleRow(name: "N.C. is a timed silence", source: "[G]a [N.C.]b\n", expected: [
            "G 4", "N.C. 4",
        ]),
        RuleRow(name: "unknown chords are skipped", source: "[G]a [Hx9]b [C]c\n", expected: [
            "G 4", "C 4",
        ]),
        RuleRow(
            name: "chart marks beat the rule",
            source: "| [G] [D] | [C] |\n",
            rule: .beats(1),
            expected: ["G 2", "D 2", "C 4"],
        ),
    ])
    func `the rule and the chart`(_ row: RuleRow) {
        let timeline = Song(row.source).timeline(ChordTiming(rule: row.rule))
        #expect(Self.lengths(timeline) == row.expected)
    }

    @Test
    func `a correction beats the chart, ticks beat beats, the source is kept`() throws {
        let song = Song("| [G] [D] | [C] |\n[E]x [A]y\n")
        let timing = try ChordTiming(chords: [
            song.override(ChordPosition(section: 0, chord: 0), beats: 3),
            song.override(ChordPosition(section: 0, chord: 1), beats: 3, ticks: 1200),
            song.override(ChordPosition(section: 0, chord: 3), beats: 2, source: .tap),
        ])
        let timeline = song.timeline(timing)
        #expect(Self.lengths(timeline) == ["G 3", "D 2.5", "C 4", "E 2", "A 4"])
        #expect(timeline.chords.map(\.source) == [.user, .user, .chart, .tap, .rule])
        #expect(timeline.chords.map(\.onset) == [0, 1440, 2640, 4560, 5520])
        #expect(timeline.length(of: ChordPosition(section: 0, chord: 1))?.ticks == 1200)
        #expect(timeline.unmatched.isEmpty)
    }

    @Test
    func `a push moves the onset and shortens the chord before, the grid stays`() throws {
        let song = Song("[G]a [C]b [D]c\n")
        let timing = try ChordTiming(chords: [
            song.override(ChordPosition(section: 0, chord: 0), beats: 4, push: .eighth),
            song.override(ChordPosition(section: 0, chord: 1), beats: 4, push: .eighth),
            song.override(ChordPosition(section: 0, chord: 2), beats: 4, push: .sixteenth),
        ])
        let timeline = song.timeline(timing)
        // The first chord's push is ignored.
        #expect(timeline.chords.map(\.push) == [nil, .eighth, .sixteenth])
        #expect(timeline.chords.map(\.onset) == [0, 1920 - 240, 3840 - 120])
        #expect(timeline.chords.map(\.length) == [1680, 1920 + 240 - 120, 1920 + 120])
        // The bar grid does not move.
        #expect(timeline.barBeat(at: 1920) == BarBeat(bar: 2, beat: 1, tick: 0))
        #expect(timeline.totalTicks == 3 * 1920)
    }

    @Test
    func `lengths are clamped to a sixteenth and 32 pulses`() throws {
        let song = Song("[G]a [C]b\n")
        let timing = try ChordTiming(chords: [
            song.override(ChordPosition(section: 0, chord: 0), beats: 1, ticks: 10),
            song.override(ChordPosition(section: 0, chord: 1), beats: 32, ticks: 50000),
        ])
        #expect(song.timeline(timing).chords.map(\.length) == [120, 32 * 480])
    }

    static let song = """
    {start_of_verse: Verse}
    [G]Hello [C]there
    {end_of_verse}
    {start_of_chorus}
    [D]Sing [G]it
    {end_of_chorus}
    {start_of_bridge}
    [Em]Bridge
    {end_of_bridge}
    {chorus}

    """

    @Test
    func `written order writes out a chorus stub and counts it as another play`() {
        let song = Song(Self.song)
        let timeline = song.timeline()
        #expect(timeline.chords.map(\.token) == ["G", "C", "D", "G", "Em", "D", "G"])
        #expect(timeline.chords.map(\.pass) == [0, 0, 1, 1, 2, 3, 3])
        #expect(timeline.chords.map(\.occurrence) == [1, 1, 1, 1, 1, 2, 2])
        // The stub's chords keep the chorus's positions, so one correction covers both.
        #expect(timeline.chords[5].position == ChordPosition(section: 1, chord: 0))
        #expect(timeline.passes.map(\.content) == [0, 1, 2, 1])
        #expect(timeline.timed(pass: 3, chord: 1)?.token == "G")
    }

    @Test
    func `played passes skip, repeat and share one correction`() throws {
        let song = Song(Self.song)
        let timing = try ChordTiming(chords: [
            song.override(ChordPosition(section: 1, chord: 0), beats: 2),
        ])
        let order = [
            PlayedPass(index: 1),
            PlayedPass(index: 0, mode: .skip),
            PlayedPass(index: 2, mode: .chordsOnly),
            PlayedPass(index: 1),
        ]
        let timeline = song.timeline(timing, order: order)
        #expect(Self.lengths(timeline) == ["D 2", "G 4", "Em 4", "D 2", "G 4"])
        #expect(timeline.passes.map(\.section) == [1, 2, 1])
        #expect(timeline.passes.map(\.occurrence) == [1, 1, 2])
        #expect(timeline.passes.map(\.start) == [0, 2880, 4800])
    }

    @Test
    func `an unmatched correction is listed and ignored`() throws {
        let song = Song(Self.song)
        let override = try song.override(ChordPosition(section: 0, chord: 1), beats: 2)
        let edited = Song(Self.song.replacingOccurrences(of: "[C]there", with: "[A]there"))
        let timeline = edited.timeline(ChordTiming(chords: [override]))
        #expect(timeline.unmatched == [override])
        #expect(timeline.chords[1].source == .rule)
    }

    @Test
    func `grid chords are timed and corrected like lyric chords`() throws {
        let song = Song("[E]intro\n\n{start_of_grid}\n| G . . . | C . D . |\n{end_of_grid}\n")
        let timing = try ChordTiming(chords: [
            song.override(ChordPosition(section: 1, chord: 1), beats: 3),
        ])
        let timeline = song.timeline(timing)
        #expect(Self.lengths(timeline) == ["E 4", "G 4", "C 3", "D 2"])
        #expect(timeline.chords.map(\.source) == [.rule, .grid, .user, .grid])
    }

    @Test
    func `bar and beat round-trip through a meter change`() {
        let song = Song("{time: 4/4}\n[G]a [C]b\n\n{time: 3/4}\n[D]c [E]d\n")
        let timeline = song.timeline()
        #expect(timeline.chords.map(\.onset) == [0, 1920, 3840, 3840 + 1440])
        #expect(timeline.barBeat(at: 3840) == BarBeat(bar: 3, beat: 1, tick: 0))
        let late = timeline.barBeat(at: 3840 + 1440 + 480 + 100)
        #expect(late == BarBeat(bar: 4, beat: 2, tick: 100))
        for tick in [0, 100, 1920, 2400, 3840, 4000, 5900] {
            #expect(timeline.tick(of: timeline.barBeat(at: tick)) == tick)
        }
        #expect(timeline.chord(atTick: 0) == 0)
        #expect(timeline.chord(atTick: 1919) == 0)
        #expect(timeline.chord(atTick: 1920) == 1)
        #expect(timeline.chord(atTick: 3840 + 1440) == 3)
        #expect(timeline.chord(atTick: timeline.totalTicks) == nil)
    }

    @Test
    func `a line's onset in a pass`() throws {
        let song = Song(Self.song)
        let timeline = song.timeline()
        let chorusLine = try #require(timeline.chords.first { $0.token == "D" }?.line)
        #expect(timeline.lineOnset(chorusLine, pass: 1) == 2 * 1920)
        #expect(timeline.lineOnset(chorusLine, pass: 3) == 5 * 1920)
        #expect(timeline.lineOnset(chorusLine, pass: 0) == nil)
    }

    @Test
    func `a slice starts at zero and rounds up to whole bars`() throws {
        let song = Song(Self.song)
        let timing = try ChordTiming(chords: [
            song.override(ChordPosition(section: 1, chord: 1), beats: 3),
        ])
        let slice = song.timeline(timing).slice(passes: 1 ..< 2)
        #expect(slice.chords.map(\.token) == ["D", "G"])
        #expect(slice.chords.map(\.onset) == [0, 1920])
        // 4 + 3 beats round up to two bars: the last chord takes the beat.
        #expect(slice.chords.map(\.length) == [1920, 1920])
        #expect(slice.totalTicks == 3840)
        #expect(slice.chords.map(\.pass) == [0, 0])
        #expect(slice.passes.map(\.content) == [1])
        #expect(slice.timed(pass: 0, chord: 0)?.token == "D")
    }

    @Test
    func `seconds follow the tempo in effect`() {
        let song = Song("{tempo: 120}\n[G]a\n\n{tempo: 60}\n[C]b\n")
        let timeline = song.timeline()
        #expect(timeline.seconds(at: 1920) == 2)
        #expect(timeline.seconds(at: 3840) == 6)
        #expect(timeline.seconds(at: 3840, factor: 0.5) == 12)
    }
}

/// The 2 ms budget (P8-7 section 5.8): matched by the timing-budget run, so it runs with
/// nothing else in parallel.
struct SongTimelinePerformanceTests {
    @Test
    func `the longest corpus song builds 100 times within budget`() throws {
        let source = try EditingFixtures.load("live-very-long.cho")
        let song = SongTimelineTests.Song(source)
        let clock = ContinuousClock()
        var count = 0
        let elapsed = clock.measure {
            for _ in 0 ..< 100 {
                count += song.timeline().chords.count
            }
        }
        #expect(count > 0)
        #expect(elapsed / 100 < .milliseconds(2), "\(elapsed / 100) per build")
    }
}
