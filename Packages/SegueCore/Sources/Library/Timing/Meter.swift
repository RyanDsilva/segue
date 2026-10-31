// P8-7a (docs/phases/8-workstreams/P8-7-time-model-and-fills.md sections 3, 5.2). The
// timeline's units: ticks (480 per quarter, R168 Q1) and the meter a `{time}` gives. Pure.

import ChordPro

/// The timeline's unit: 480 ticks per quarter note (MIDI export's PPQ; R168 Q1).
public enum Ticks {
    public static let perQuarter = 480
    /// A whole note.
    public static let perWhole = 4 * perQuarter
    public static let eighth = perQuarter / 2
    public static let sixteenth = perQuarter / 4
}

/// A time signature as the timeline counts it: `pulses` per bar (R118: a compound meter
/// counts the dotted quarter), each `ticksPerPulse` long.
public struct Meter: Sendable, Hashable, CustomStringConvertible {
    /// The signature's upper number (1-32).
    public var beats: Int
    /// The signature's lower number (1, 2, 4, 8, 16, 32 or 64).
    public var noteValue: Int

    public init(beats: Int, noteValue: Int) {
        self.beats = max(1, beats)
        self.noteValue = max(1, noteValue)
    }

    /// `{time}` as written; 4/4 when nil or not a time signature (as the metronome counts).
    public init(time: String?) {
        if let time, let parsed = Metadata.parseTime(time) {
            self.init(beats: parsed.beats, noteValue: parsed.noteValue)
        } else {
            self = .common
        }
    }

    /// `{time}` when it is a time signature, else nil.
    public init?(parsing time: String) {
        guard let parsed = Metadata.parseTime(time) else { return nil }
        self.init(beats: parsed.beats, noteValue: parsed.noteValue)
    }

    public static let common = Self(beats: 4, noteValue: 4)

    /// 6/8, 9/8, 12/8: eighths grouped in threes.
    public var isCompound: Bool {
        noteValue == 8 && beats > 3 && beats.isMultiple(of: 3)
    }

    /// Pulses per bar (`Metadata.pulses`, R118).
    public var pulses: Int {
        Metadata.pulses(beats: beats, noteValue: noteValue)
    }

    /// A dotted quarter in a compound meter, else the written beat.
    public var ticksPerPulse: Int {
        let beat = Ticks.perWhole / noteValue
        return isCompound ? 3 * beat : beat
    }

    public var ticksPerBar: Int {
        pulses * ticksPerPulse
    }

    /// "6/8".
    public var description: String {
        "\(beats)/\(noteValue)"
    }
}
