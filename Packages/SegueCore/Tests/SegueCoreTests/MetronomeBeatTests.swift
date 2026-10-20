import ChordPro
import Foundation
import Shows
import Support
import Testing

/// The stage metronome's beat model (R90, R108): pure timing logic, so unit tests.
struct MetronomeBeatTests {
    private static let start = Date(timeIntervalSince1970: 1_792_400_000)

    private static func track(_ bpm: Double, _ time: String? = nil) throws -> MetronomeTrack {
        try #require(MetronomeTrack(
            bpm: bpm,
            meter: MetronomeMeter(time: time),
            start: start,
        ))
    }

    @Test
    func `beats fall every 60 over bpm seconds with beat 1 accented in 4 4`() throws {
        let track = try Self.track(120)
        #expect(track.interval == 0.5)
        let clock = ManualClock(start: Self.start)
        var seen: [(Int, MetronomeAccent)] = []
        for _ in 0 ..< 8 {
            let beat = track.beat(at: clock.now())
            seen.append((beat.beatInBar, beat.accent))
            #expect(beat.phase < 1e-9)
            clock.advance(by: 0.5)
        }
        #expect(seen.map(\.0) == [1, 2, 3, 4, 1, 2, 3, 4])
        #expect(seen.map(\.1) == [
            .downbeat, .plain, .plain, .plain, .downbeat, .plain, .plain, .plain,
        ])
        // Halfway through beat 2.
        let mid = track.beat(at: Self.start.addingTimeInterval(0.75))
        #expect(mid.index == 1)
        #expect(abs(mid.phase - 0.5) < 1e-9)
    }

    /// A `{time}` and the bar positions and accents of its first beats.
    struct MeterCase: Sendable, CustomTestStringConvertible {
        var time: String?
        var bars: [Int]
        var accents: [MetronomeAccent]

        var testDescription: String {
            time ?? "no time"
        }
    }

    @Test(arguments: [
        MeterCase(
            time: "3/4",
            bars: [1, 2, 3, 1, 2, 3],
            accents: [.downbeat, .plain, .plain, .downbeat, .plain, .plain],
        ),
        // Compound meters count the dotted quarter (R118).
        MeterCase(time: "6/8", bars: [1, 2, 1, 2], accents: [.downbeat, .plain, .downbeat, .plain]),
        MeterCase(time: "9/8", bars: [1, 2, 3, 1], accents: [.downbeat, .plain, .plain, .downbeat]),
        MeterCase(
            time: "12/8",
            bars: [1, 2, 3, 4, 1],
            accents: [.downbeat, .plain, .plain, .plain, .downbeat],
        ),
        MeterCase(time: "3/8", bars: [1, 2, 3, 1], accents: [.downbeat, .plain, .plain, .downbeat]),
        MeterCase(time: "2/2", bars: [1, 2, 1, 2], accents: [.downbeat, .plain, .downbeat, .plain]),
        MeterCase(
            time: nil,
            bars: [1, 2, 3, 4, 1],
            accents: [.downbeat, .plain, .plain, .plain, .downbeat],
        ),
        MeterCase(
            time: "not a meter",
            bars: [1, 2, 3, 4, 1],
            accents: [.downbeat, .plain, .plain, .plain, .downbeat],
        ),
    ])
    func `the time signature sets the bar and its accents`(meter: MeterCase) throws {
        let track = try Self.track(90, meter.time)
        let beats = (0 ..< meter.bars.count).map { track.beat(at: track.time(ofBeat: $0)) }
        #expect(beats.map(\.beatInBar) == meter.bars)
        #expect(beats.map(\.accent) == meter.accents)
    }

    @Test
    func `a song's metadata gives the track, and no tempo gives none`() throws {
        let song = ChordProParser.parse("{title: A}\n{tempo: 96}\n{time: 3/4}\n").0
        let track = try #require(MetronomeTrack(metadata: song.metadata, start: Self.start))
        #expect(track.bpm == 96)
        #expect(track.meter == MetronomeMeter(beats: 3, noteValue: 4))
        let none = ChordProParser.parse("{title: B}\n{time: 3/4}\n").0
        #expect(MetronomeTrack(metadata: none.metadata, start: Self.start) == nil)
        // An implausible tempo is a typo, not a metronome.
        #expect(MetronomeTrack(bpm: 2000, start: Self.start) == nil)
        #expect(MetronomeTrack(bpm: 0, start: Self.start) == nil)
    }

    @Test
    func `ten minutes in the grid has not drifted`() throws {
        let track = try Self.track(97)
        // Sampled every display frame for ten minutes, the way the overlay reads it: each
        // frame's beat is where the grid says, wherever the frame falls.
        let clock = ManualClock(start: Self.start)
        let frame = 1.0 / 120
        for step in stride(from: 0, through: Int(600 / frame), by: 997) {
            let elapsed = Double(step) * frame
            clock.set(Self.start.addingTimeInterval(elapsed))
            let beat = track.beat(at: clock.now())
            let exact = elapsed / track.interval
            #expect(abs(Double(beat.index) + beat.phase - exact) < 1e-5)
        }
        clock.set(Self.start.addingTimeInterval(600))
        let late = track.beat(at: clock.now())
        #expect(late.index == 970)
        #expect(late.phase < 1e-5)
        // Beat 970 lands exactly 600 s after the start.
        #expect(abs(track.time(ofBeat: 970).timeIntervalSince(Self.start) - 600) < 1e-9)
    }

    @Test
    func `a new start instant restarts the phase on beat 1`() throws {
        var track = try Self.track(100)
        let later = Self.start.addingTimeInterval(7.3)
        #expect(track.beat(at: later).beatInBar != 1 || track.beat(at: later).phase > 0)
        track.start = later
        let beat = track.beat(at: later)
        #expect(beat.index == 0)
        #expect(beat.isDownbeat)
        #expect(beat.phase == 0)
        // Before the start there is no negative beat.
        #expect(track.beat(at: Self.start).index == 0)
    }

    @Test
    func `the next beat to schedule is on the grid`() throws {
        let track = try Self.track(120)
        let next = track.nextBeat(atOrAfter: Self.start.addingTimeInterval(1.2))
        #expect(next.beat.index == 3)
        #expect(next.beat.beatInBar == 4)
        #expect(next.time == Self.start.addingTimeInterval(1.5))
        let onBeat = track.nextBeat(atOrAfter: Self.start.addingTimeInterval(2))
        #expect(onBeat.beat.index == 4)
        #expect(onBeat.beat.isDownbeat)
        #expect(track.nextBeat(atOrAfter: Self.start.addingTimeInterval(-3)).beat.index == 0)
    }
}
