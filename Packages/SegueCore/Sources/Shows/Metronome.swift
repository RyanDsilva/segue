// Phase 3 (R90, R108, P3-14): the stage metronome's beat model. Pure: a tempo, a time
// signature and a start instant in, the beat at any instant out.

import ChordPro
import Foundation

/// A song's time signature as the metronome counts it: `pulses` per bar, the first
/// accented. `{time}` absent or unreadable counts 4/4.
public struct MetronomeMeter: Sendable, Hashable {
    /// The signature's upper number (1-32).
    public var beats: Int
    /// The signature's lower number.
    public var noteValue: Int

    public static let common = Self(beats: 4, noteValue: 4)

    public init(beats: Int, noteValue: Int) {
        self.beats = max(1, beats)
        self.noteValue = noteValue
    }

    /// `{time}` as written ("3/4", "6/8"); 4/4 when nil or not a time signature.
    public init(time: String?) {
        if let time, let parsed = Metadata.parseTime(time) {
            self.init(beats: parsed.beats, noteValue: parsed.noteValue)
        } else {
            self = .common
        }
    }

    /// Whether this is a compound meter (6/8, 9/8, 12/8): eighths grouped in threes.
    public var isCompound: Bool {
        noteValue == 8 && beats > 3 && beats.isMultiple(of: 3)
    }

    /// Pulses per bar (R118, `Metadata.pulses`): a compound meter counts the dotted quarter,
    /// so 6/8 is 2 pulses, 9/8 is 3 and 12/8 is 4, and `{tempo}` is per dotted quarter. Any
    /// other meter pulses on every written beat.
    public var pulses: Int {
        Metadata.pulses(beats: beats, noteValue: noteValue)
    }
}

/// How strongly a beat is marked.
public enum MetronomeAccent: Sendable, Hashable {
    /// Beat 1 of the bar.
    case downbeat
    /// Any other beat.
    case plain
}

/// One beat as the overlay shows it.
public struct MetronomeBeat: Sendable, Hashable {
    /// Pulses since the start instant (0 is the first downbeat).
    public var index: Int
    /// 1-based pulse in the bar.
    public var beatInBar: Int
    /// How far through this beat, in 0..<1 (0 is the click).
    public var phase: Double
    public var accent: MetronomeAccent

    public var isDownbeat: Bool {
        accent == .downbeat
    }
}

/// The metronome for one song: pulses every `60 / bpm` seconds from `start`, beat 1 of the
/// bar at `start`. Every value is computed from the start instant, never accumulated, so a
/// 10-minute song ends on the same grid it began on; drive it from a monotonic clock.
public struct MetronomeTrack: Sendable, Hashable {
    /// Tempo in pulses per minute (`{tempo}`; per dotted quarter in a compound meter).
    public var bpm: Double
    public var meter: MetronomeMeter
    /// The instant of beat 1 (the song became current, or the metronome was switched on).
    public var start: Date

    /// The tempos the metronome runs at; others (a typo like `{tempo: 2000}`) are refused.
    public static let bpmRange: ClosedRange<Double> = 20 ... 400

    /// Nil for a tempo outside `bpmRange` (no metronome for that song).
    public init?(bpm: Double, meter: MetronomeMeter = .common, start: Date) {
        guard bpm.isFinite, Self.bpmRange.contains(bpm) else { return nil }
        self.bpm = bpm
        self.meter = meter
        self.start = start
    }

    /// The track for a song's metadata: nil without a usable `{tempo}` (R108: the overlay
    /// hides). `{time}` sets the meter (4/4 when absent).
    public init?(metadata: Metadata, start: Date) {
        guard let tempo = metadata.tempo else { return nil }
        self.init(bpm: tempo, meter: MetronomeMeter(time: metadata.time), start: start)
    }

    /// Tolerance, in beats, for an instant computed from a beat's own time.
    private static let slack = 1e-6

    /// Seconds per pulse.
    public var interval: TimeInterval {
        60 / bpm
    }

    /// Seconds per bar: `pulses x 60 / bpm` (the rehearsal loop's count-in, P8-2).
    public var barDuration: TimeInterval {
        Double(meter.pulses) * interval
    }

    /// The beat sounding at `now`. Before `start` this is beat 1 at phase 0 (the count-in
    /// has not begun).
    public func beat(at now: Date) -> MetronomeBeat {
        let beats = max(0, now.timeIntervalSince(start)) / interval
        // A beat's own instant (`time(ofBeat:)`) reads as that beat, not the end of the
        // previous one: `Date` keeps about 0.2 µs, so allow a microsecond of slack.
        let index = Int((beats + Self.slack).rounded(.down))
        return beat(index: index, phase: min(max(beats - Double(index), 0), 0.999_999))
    }

    /// The instant beat `index` falls on.
    public func time(ofBeat index: Int) -> Date {
        start.addingTimeInterval(Double(index) * interval)
    }

    /// Beat `index` (at its click, phase 0).
    public func beat(_ index: Int) -> MetronomeBeat {
        beat(index: max(0, index), phase: 0)
    }

    /// The first beat at or after `now` (the next click to schedule) and its instant.
    public func nextBeat(atOrAfter now: Date) -> (beat: MetronomeBeat, time: Date) {
        let beats = now.timeIntervalSince(start) / interval
        let index = max(0, Int((beats - Self.slack).rounded(.up)))
        return (beat(index: index, phase: 0), time(ofBeat: index))
    }

    private func beat(index: Int, phase: Double) -> MetronomeBeat {
        let position = index % meter.pulses
        return MetronomeBeat(
            index: index,
            beatInBar: position + 1,
            phase: phase,
            accent: position == 0 ? .downbeat : .plain,
        )
    }
}
