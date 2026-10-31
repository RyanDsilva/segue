import ChordPro
import Editing
import Foundation
import Library
import Support
import Testing

/// A slot's time from the timeline (P8-8 section 5.2, R172, R173): tempo times the bars of
/// the played passes, pass modes honoured, unknown without a tempo or chords, never a guess.
struct SlotTimeTests {
    /// Verse 1 (4 bars), Chorus (2), Verse 2 (2) and a `{chorus}` repeat (2): 10 bars.
    static let song = """
    {title: Timed}
    {tempo: 96}

    {start_of_verse: Verse 1}
    [G]a [C]b
    [D]c [G]d
    {end_of_verse}

    {start_of_chorus}
    [C]e [G]f
    {end_of_chorus}

    {start_of_verse: Verse 2}
    [G]g [D]h
    {end_of_verse}

    {chorus}
    """

    static func record(_ source: String, timing: ChordTiming = ChordTiming()) throws
        -> SongRecord
    {
        var record = try TestSongs.record(
            source: source,
            id: SongID(ULID(milliseconds: 1, randomness: Array(repeating: 0, count: 10))),
        )
        record.sidecar.bass.timing = timing
        return record
    }

    /// "seconds/bars/tempo/estimated", or the unknown reason.
    static func summary(_ time: SlotTime) -> String {
        switch time {
        case let .known(seconds, bars, tempo, estimated):
            "\(SlotTime.clock(seconds)) \(bars) bars \(Int(tempo)) BPM\(estimated ? " ~" : "")"
        case let .unknown(reason):
            reason.rawValue
        }
    }

    struct Row: Sendable, CustomTestStringConvertible {
        var name: String
        var source: String
        var expected: String

        var testDescription: String {
            name
        }
    }

    @Test(arguments: [
        Row(
            name: "64 one-bar chords in 4/4 at 96 BPM",
            source: "{tempo: 96}\n" + String(repeating: "[G]x ", count: 64) + "\n",
            expected: "2:40 64 bars 96 BPM ~",
        ),
        Row(
            name: "3/4 at 90 BPM",
            source: "{tempo: 90}\n{time: 3/4}\n[G]a [C]b [D]c [G]d\n",
            expected: "0:08 4 bars 90 BPM ~",
        ),
        Row(
            name: "a mid-song tempo change",
            source: "{tempo: 96}\n[G]a [C]b [D]c [G]d\n{tempo: 120}\n[C]e [G]f\n",
            expected: "0:14 6 bars 96 BPM ~",
        ),
        Row(
            name: "a {chorus} stub counted in written order",
            source: song,
            expected: "0:25 10 bars 96 BPM ~",
        ),
        Row(name: "no tempo", source: "[G]a [C]b\n", expected: "noTempo"),
        Row(name: "lyrics only", source: "{tempo: 96}\nJust words\n", expected: "noChords"),
        Row(name: "an empty song", source: "{title: Empty}\n", expected: "noChords"),
    ])
    func `the whole song in written order`(row: Row) throws {
        #expect(try Self.summary(SlotTimes.song(Self.record(row.source))) == row.expected)
    }

    @Test
    func `a song without a tempo never yields seconds`() throws {
        let time = try SlotTimes.song(Self.record("[G]a [C]b [D]c\n"))
        #expect(time.seconds == nil)
        #expect(time.unknown == .noTempo)
        #expect(time.clock == "--:--")
        #expect(time.help == "No tempo")
        #expect(time.spoken == "Unknown, no tempo")
    }

    @Test
    func `pass modes: Skip adds nothing, x2 counts twice, other modes count fully`() throws {
        let record = try Self.record(Self.song)
        let units = SongSections.units(of: record.document)
        func time(_ passes: [(String, PassMode)]) -> String {
            let arrangement = SlotArrangement(passes: passes.map { name, mode in
                SlotArrangementTests.pass(units, name, mode)
            })
            return Self.summary(SlotTimes.slot(record, arrangement: arrangement))
        }
        // Verse 1 (4) + Chorus x2 (2 + 2), Verse 2 skipped: 8 bars.
        #expect(time([
            ("Verse 1", .full), ("Chorus 1st", .full), ("Chorus 1st", .full),
            ("Verse 2", .skip),
        ]) == "0:20 8 bars 96 BPM ~")
        // Chords only and First line passes are played: they count their full chords.
        #expect(time([("Verse 1", .chordsOnly), ("Verse 2", .firstLine)])
            == "0:15 6 bars 96 BPM ~")
        // No arrangement: the full song.
        #expect(Self.summary(SlotTimes.slot(record, arrangement: nil)) == "0:25 10 bars 96 BPM ~")
    }

    @Test
    func `an out-of-date arrangement times the full song`() throws {
        let record = try Self.record(Self.song)
        let stale = SlotArrangement(passes: [ArrangementPass(
            anchor: .section(SectionRef(label: "Coda", occurrence: 1)),
        )])
        #expect(Self.summary(SlotTimes.slot(record, arrangement: stale))
            == "0:25 10 bars 96 BPM ~")
    }

    @Test
    func `user corrections change the time and clear the estimate`() throws {
        let source = "{tempo: 120}\n[G]a [C]b\n"
        let song = SongTimelineTests.Song(source)
        let first = try song.override(ChordPosition(section: 0, chord: 0), beats: 2)
        let second = try song.override(ChordPosition(section: 0, chord: 1), beats: 2)
        // Rule-timed: two bars of 4/4 at 120 BPM.
        #expect(try Self.summary(SlotTimes.song(Self.record(source))) == "0:04 2 bars 120 BPM ~")
        // Both corrected to two beats: one bar, nothing estimated.
        let corrected = try Self.record(source, timing: ChordTiming(chords: [first, second]))
        #expect(Self.summary(SlotTimes.song(corrected)) == "0:02 1 bars 120 BPM")
        // One rule-timed chord among corrected ones sets `estimated`.
        let mixed = try Self.record(source, timing: ChordTiming(chords: [first]))
        #expect(SlotTimes.song(mixed).isEstimated)
    }

    @Test
    func `display text`() {
        let known = SlotTime.known(seconds: 219.6, bars: 72, tempo: 96, estimated: false)
        #expect(known.clock == "3:40")
        #expect(known.help == "96 BPM, 72 bars")
        #expect(known.spoken == "3 minutes 40 seconds")
        let estimated = SlotTime.known(seconds: 220, bars: 72, tempo: 96, estimated: true)
        #expect(estimated.clock == "~3:40")
        #expect(estimated.help == "96 BPM, 72 bars, chord lengths estimated")
        #expect(estimated.spoken == "About 3 minutes 40 seconds")
        #expect(SlotTime.unknown(.noChords).help == "No chords to time")
    }
}
