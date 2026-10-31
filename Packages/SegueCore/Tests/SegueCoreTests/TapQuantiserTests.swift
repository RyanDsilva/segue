import Foundation
@testable import Library
import Support
import Testing

/// Tap capture's arithmetic (P8-7 sections 7, 16.1): taps on a scripted clock become chord
/// lengths on the click's grid or at a tempo derived from the taps; Tab skips; a zero length
/// is dropped and marked skipped; lengths clamp to 32 pulses.
struct TapQuantiserTests {
    /// Four 4/4 chords of one bar each (the song's rule).
    static let bars = Array(
        repeating: TapQuantiser.Chord(ticks: 1920, ticksPerPulse: 480),
        count: 4,
    )

    /// Taps `gaps` seconds apart on a manual clock, from `start` seconds after the origin
    /// (`option` marks the taps held with ⌥, by number).
    static func taps(
        _ gaps: [Double],
        start: Double = 0,
        option: Set<Int> = [],
        skips: Set<Int> = [],
    ) -> [TapEvent] {
        let clock = ManualClock()
        let watch = TapStopwatch(clock: clock)
        clock.advance(by: start)
        var events: [TapEvent] = []
        for (index, gap) in ([0] + gaps).enumerated() {
            clock.advance(by: gap)
            if skips.contains(index) {
                events.append(.skip)
            }
            events.append(.tap(seconds: watch.seconds(), half: option.contains(index)))
        }
        return events
    }

    static func click(
        _ events: [TapEvent],
        chords: [TapQuantiser.Chord] = bars,
        tempo: Double = 120,
        halfBeats: Bool = false,
    ) -> TapProposal {
        TapQuantiser.propose(
            events,
            chords: chords,
            options: .init(mode: .click, tempo: tempo, halfBeats: halfBeats),
        )
    }

    // MARK: Click mode

    @Test(arguments: [
        // (seconds between taps at 120 BPM, half beats, new lengths in ticks)
        ([2.0, 1.5, 2.0, 2.0], false, [1920, 1440, 1920, 1920]),
        // Late and early by up to 0.2 s still lands on the beat.
        ([2.1, 1.35, 2.05, 1.9], false, [1920, 1440, 1920, 1920]),
        // Half beats: 1.25 s is two and a half beats.
        ([1.25, 2.0, 2.0, 2.0], true, [1200, 1920, 1920, 1920]),
        ([1.25, 2.0, 2.0, 2.0], false, [1440, 1920, 1920, 1920]),
    ])
    func `click mode quantises each tap to the click's beats`(
        gaps: [Double], halfBeats: Bool, lengths: [Int],
    ) {
        let result = Self.click(Self.taps(gaps), halfBeats: halfBeats)
        #expect(result.chords.map(\.new) == lengths)
        #expect(result.taps == 5)
        #expect(result.tempo == 120)
    }

    @Test
    func `option held at a tap snaps that tap to an eighth`() {
        // The second chord's start at 2.25 s is half a beat late; with ⌥ it stays there.
        let held = Self.click(Self.taps([2.25, 1.75, 2, 2], option: [1]))
        #expect(held.chords.map(\.new).prefix(2) == [2160, 1680])
        let plain = Self.click(Self.taps([2.25, 1.75, 2, 2]))
        #expect(plain.chords.map(\.new).prefix(2) != [2160, 1680])
    }

    @Test
    func `the grid is the click's, so a tap during the count-in counts from beat one`() {
        // The first tap a little before the downbeat (in the count-in) still starts on 1.
        let result = Self.click(Self.taps([2.1, 2, 2, 2], start: -0.1))
        #expect(result.chords.map(\.new) == [1920, 1920, 1920, 1920])
        #expect(result.changed.isEmpty)
        #expect(result.chords.allSatisfy { $0.outcome == .unchanged })
    }

    @Test
    func `the last chord tapped keeps its length without a tap after it`() {
        let result = Self.click(Self.taps([1, 1]))
        #expect(result.chords.map(\.outcome) == [.changed, .changed, .untapped, .untapped])
        #expect(result.chords.map(\.new) == [960, 960, 1920, 1920])
    }

    @Test
    func `tab skips a chord, which keeps its length out of the interval`() {
        // G is tapped, C skipped (4 beats), D tapped 6 s after G: G lasted 2 beats.
        let events: [TapEvent] = [
            .tap(seconds: 0, half: false), .skip, .tap(seconds: 3, half: false),
            .tap(seconds: 5, half: false), .tap(seconds: 7, half: false),
        ]
        let result = Self.click(events)
        #expect(result.chords.map(\.outcome) == [.changed, .skipped, .unchanged, .unchanged])
        #expect(result.chords.map(\.new) == [960, 1920, 1920, 1920])
        #expect(result.skipped == 1)
        #expect(result.taps == 4)
    }

    @Test
    func `a tap that leaves a chord no length drops it and marks it skipped`() {
        // Two taps on the same beat: the first chord would last nothing.
        let events: [TapEvent] = [
            .tap(seconds: 0, half: false), .tap(seconds: 0.1, half: false),
            .tap(seconds: 2.1, half: false),
        ]
        let result = Self.click(events)
        #expect(result.chords.map(\.outcome).prefix(2) == [.skipped, .unchanged])
        #expect(result.chords[0].new == 1920)
        // A skipped chord longer than the interval it falls in leaves nothing either.
        let squeezed = Self.click([
            .tap(seconds: 0, half: false), .skip, .tap(seconds: 1, half: false),
        ])
        #expect(squeezed.chords.map(\.outcome).prefix(2) == [.skipped, .skipped])
    }

    @Test
    func `lengths clamp to 32 beats and taps after the end are ignored`() {
        let result = Self.click(Self.taps([20, 2, 2, 2, 2, 2]))
        #expect(result.chords[0].new == 32 * 480)
        #expect(result.chords.count == 4)
        #expect(result.taps == 7)
    }

    @Test
    func `compound meters count dotted quarters`() {
        // Two dotted-quarter pulses a bar: at 60 BPM a bar is 2 s.
        let chords = Array(repeating: TapQuantiser.Chord(ticks: 1440, ticksPerPulse: 720), count: 3)
        let result = Self.click(Self.taps([2, 1, 2]), chords: chords, tempo: 60)
        #expect(result.chords.map(\.new) == [1440, 720, 1440])
    }

    // MARK: Free mode

    /// Bars of four at 96 BPM (2.5 s) with +-30 ms of jitter.
    static let jittered = [2.53, 2.47, 2.52, 2.48, 2.51, 2.49]

    /// One derivation: the taps' intervals, the song's `{tempo}`, the chords' typical length
    /// in pulses, and the tempo expected.
    struct Derivation: Sendable, CustomTestStringConvertible {
        var intervals: [Double]
        var hint: Double?
        var expected: Double
        var bpm: Double

        var testDescription: String {
            "\(intervals) hint \(hint.map { "\($0)" } ?? "none") expect \(expected) -> \(bpm)"
        }
    }

    @Test(arguments: [
        Derivation(intervals: jittered, hint: nil, expected: 4, bpm: 96),
        // The song's {tempo} within 2% wins.
        Derivation(intervals: jittered, hint: 97, expected: 4, bpm: 97),
        Derivation(intervals: jittered, hint: 95, expected: 4, bpm: 95),
        // A {tempo} the taps do not fit does not.
        Derivation(intervals: jittered, hint: 110, expected: 4, bpm: 96),
        // One that fits as five beats a chord does: the song's tempo comes first.
        Derivation(intervals: jittered, hint: 120, expected: 4, bpm: 120),
        // Whether a tap is a bar of 4 or of 2 is settled by the chords' own lengths.
        Derivation(intervals: jittered, hint: nil, expected: 2, bpm: 48),
        Derivation(intervals: jittered, hint: nil, expected: 8, bpm: 192),
        // Exact two-beat taps at 100 BPM.
        Derivation(intervals: [1.2, 1.2, 1.2, 1.2], hint: nil, expected: 2, bpm: 100),
        // A mixed rhythm: 4, 2, 2, 4 beats at 120.
        Derivation(intervals: [2.0, 1.0, 1.0, 2.0], hint: nil, expected: 4, bpm: 120),
    ])
    func `free mode derives the tempo from the taps`(row: Derivation) {
        let derived = TapQuantiser.tempo(
            intervals: row.intervals,
            hint: row.hint,
            expected: row.expected,
        )
        #expect(derived == row.bpm)
    }

    @Test
    func `ties go to the slower tempo`() {
        // One 2 s interval, no expectation: 60, 90, 120 ... fit exactly. Whole bars of 4
        // leave 120 and 240, and the slower wins; with bars of one beat, 60 does.
        #expect(TapQuantiser.tempo(intervals: [2.0]) == 120)
        #expect(TapQuantiser.tempo(intervals: [2.0], pulsesPerBar: 1) == 60)
        #expect(TapQuantiser.tempo(intervals: [], hint: nil) == 90)
        #expect(TapQuantiser.tempo(intervals: [], hint: 104) == 104)
    }

    @Test
    func `free mode counts from the first tap at the derived tempo`() {
        let events = Self.taps(Self.jittered.prefix(4).map(\.self), start: 7.3)
        let result = TapQuantiser.propose(
            events,
            chords: Self.bars,
            options: .init(mode: .free),
        )
        #expect(result.tempo == 96)
        #expect(result.chords.map(\.new) == [1920, 1920, 1920, 1920])
        // The review's -/+ re-quantises at the tempo given.
        let halved = TapQuantiser.propose(
            events,
            chords: Self.bars,
            options: .init(mode: .free, tempo: 48),
        )
        #expect(halved.chords.map(\.new) == [960, 960, 960, 960])
    }

    @Test
    func `the stopwatch reads the injected clock`() {
        let clock = ManualClock()
        let watch = TapStopwatch(clock: clock, startingIn: 2)
        #expect(watch.seconds() == -2)
        clock.advance(by: 3.5)
        #expect(watch.seconds() == 1.5)
    }
}
