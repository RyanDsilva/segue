// P8-7a (docs/phases/8-workstreams/P8-7-time-model-and-fills.md section 5.2). A value that
// applies from a chord onward in source order: the meter, tempo and key maps. Pure.

import Editing
import MusicTheory

/// A value that applies from a chord onward (source order), with the initial value first.
/// Positions are written positions (render section, ordinal among its `.chord` chords; grid
/// chords included). A `{chorus}` stub has no positions of its own: read what a stub plays
/// from `SongTimeline.chords` (each `TimedChord` carries the values in effect where it plays).
public struct PositionalMap<Value: Sendable & Hashable>: Sendable, Hashable {
    public struct Change: Sendable, Hashable {
        /// The first chord the value applies to.
        public var from: ChordPosition
        public var value: Value

        public init(from: ChordPosition, value: Value) {
            self.from = from
            self.value = value
        }
    }

    public var initial: Value
    /// Sorted by position.
    public var changes: [Change]

    public init(initial: Value, changes: [Change] = []) {
        self.initial = initial
        self.changes = changes
    }

    /// The value in effect at `position`.
    public func value(at position: ChordPosition) -> Value {
        changes.last { $0.from <= position }?.value ?? initial
    }
}

public typealias MeterMap = PositionalMap<Meter>
/// BPM in pulses per minute; nil = no `{tempo}`.
public typealias TempoMap = PositionalMap<Double?>
/// Written keys (the shape key under a capo).
public typealias KeyMap = PositionalMap<SongKey?>
