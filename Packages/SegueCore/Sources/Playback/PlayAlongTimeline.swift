// P8-6b (docs/phases/8-workstreams/P8-6-audio.md section 7.5 as amended by P8-7, R167 Q1).
// What play-along plays: a range slice of P8-7a's `SongTimeline` (which owns every chord
// length, onset, meter, tempo and key) plus the voices: each chord at concert pitch with its
// bass note, the shown walk-up into the next chord, and any fill that replaces the bass line.
// No length is computed here. Pure.

import Editing
import Library
import MusicTheory

/// Which passes play: the whole song, one pass, or one pass to the end. Indices are
/// `SongTimeline.passes` indices (render sections in written order; P8-2's played passes on
/// the Rehearsal stage).
public enum PlayAlongRange: Sendable, Hashable {
    case whole
    case section(Int)
    case from(Int)

    /// The pass indices among `count` passes (empty when out of range).
    public func passes(in count: Int) -> Range<Int> {
        switch self {
        case .whole: 0 ..< count
        case let .section(index): index >= 0 && index < count ? index ..< index + 1 : 0 ..< 0
        case let .from(index): index >= 0 && index < count ? index ..< count : 0 ..< 0
        }
    }
}

/// A play-along voice toggle (the bar's Bass, Chords, Click and Walk-ups switches).
public enum VoiceToggle: String, Sendable, Hashable, Codable, CaseIterable {
    case bass
    case chords
    case click
    case walkUps
}

/// A fill that replaces the bass voice over part of the range (P8-7 section 13; R167 Q8, R168
/// Q4): from its first chord's onset up to its landing, its notes play instead of the roots
/// and the walk-up. P8-7c resolves its `Part`s against the sliced timeline into these.
public struct PlayAlongFill: Sendable, Hashable {
    /// One resolved note, in the slice's ticks, at sounding pitch.
    public struct Note: Sendable, Hashable {
        public var tick: Int
        public var length: Int
        public var midi: UInt8
        public var velocity: UInt8

        public init(tick: Int, length: Int, midi: UInt8, velocity: UInt8 = 96) {
            self.tick = tick
            self.length = max(1, length)
            self.midi = midi
            self.velocity = velocity
        }
    }

    /// Ticks where the fill replaces the bass line.
    public var region: Range<Int>
    public var notes: [Note]

    public init(region: Range<Int>, notes: [Note]) {
        self.region = region
        self.notes = notes
    }
}

/// One chord as play-along voices it.
public struct PlayAlongChord: Sendable, Hashable {
    public var timed: TimedChord
    /// At concert pitch; nil for `N.C.` (a timed silence).
    public var concert: ChordSymbol?
    /// The bass voice's note (`Voicing.bassNote`); nil for `N.C.`.
    public var bass: UInt8?
    /// The walk-up the chart shows into the next chord (the pick, else the top candidate):
    /// semitones from that chord's bass, in played order; [] for none or hold.
    public var walk: [Int]

    public init(timed: TimedChord, concert: ChordSymbol?, bass: UInt8?, walk: [Int] = []) {
        self.timed = timed
        self.concert = concert
        self.bass = bass
        self.walk = walk
    }
}

/// The play-along's chords for a range: the timeline slice (ticks from 0, rounded up to whole
/// bars) with each chord voiced.
public struct PlayAlongTimeline: Sendable, Hashable {
    /// The slice: chords, passes and the bar grid, ticks from the range's start.
    public var timeline: SongTimeline
    /// The passes played, as indices into the full timeline's passes.
    public var passes: Range<Int>
    /// Parallel to `timeline.chords`.
    public var chords: [PlayAlongChord]
    public var fills: [PlayAlongFill]

    public init(
        timeline: SongTimeline,
        passes: Range<Int>,
        chords: [PlayAlongChord],
        fills: [PlayAlongFill] = [],
    ) {
        self.timeline = timeline
        self.passes = passes
        self.chords = chords
        self.fills = fills
    }

    /// Whether the range has a `{tempo}` to play at. Play-along never starts without one
    /// (R192): there is no default tempo.
    public var hasTempo: Bool {
        startTempo != nil
    }

    /// `range` of `timeline` (built in the order being played) voiced: chords at concert
    /// pitch through `transform`, bass notes placed by `placement`, and the walk-up each
    /// change shows. `changes` are `BassLine`'s changes in the same order (a change's
    /// `section` is the pass it departs in); `fills` are in the slice's ticks.
    public static func make(
        timeline: SongTimeline,
        range: PlayAlongRange,
        changes: [ChordChange],
        fills: [PlayAlongFill] = [],
        transform: DisplayTransform,
        placement: BassPlacement,
    ) -> Self {
        let passes = range.passes(in: timeline.passes.count)
        guard !passes.isEmpty else {
            return Self(timeline: .empty, passes: passes, chords: [], fills: [])
        }
        let slice = timeline.slice(passes: passes)
        var chords = slice.chords.map { timed in
            let concert = timed.isSilent ? nil
                : transform.concert(ChordToken(parsing: timed.token)).chord?.symbol
            return PlayAlongChord(
                timed: timed,
                concert: concert,
                bass: concert.map { Voicing.bassNote(of: $0, placement: placement) },
            )
        }
        for index in chords.indices.dropLast() {
            guard chords[index].concert != nil, chords[index + 1].concert != nil else { continue }
            chords[index].walk = walk(
                from: chords[index].timed,
                to: chords[index + 1].timed,
                pass: slice.passes[safe: chords[index].timed.pass],
                offset: passes.lowerBound,
                changes: changes,
            ) ?? []
        }
        return Self(timeline: slice, passes: passes, chords: chords, fills: fills)
    }

    /// The shown walk-up's offsets on the change from `from` into `to`: the change departing
    /// that chord in its own pass; a `{chorus}` stub's pass (written order) borrows its
    /// chorus's change into the same bass.
    private static func walk(
        from: TimedChord,
        to: TimedChord,
        pass: TimedPass?,
        offset: Int,
        changes: [ChordChange],
    ) -> [Int]? {
        guard let target = ChordAnchors.writtenBass(to.token)?.pitch else { return nil }
        let matching = changes.filter { $0.id.from == from.position && $0.id.toBass == target }
        let section = from.pass + offset
        let change = matching.first { $0.section == section }
            ?? (pass.map { $0.section != $0.content } == true ? matching.first : nil)
        return change?.shown?.offsets
    }

    // MARK: Time

    /// Seconds at `tick` with every `{tempo}` scaled by `factor` (`SongTimeline.seconds`).
    public func seconds(at tick: Int, factor: Double = 1) -> Double {
        // A range without a tempo is never played (R192); 1 BPM only keeps this total.
        timeline.seconds(at: tick, factor: factor, fallback: startTempo ?? 1)
    }

    /// The length in seconds.
    public func duration(factor: Double = 1) -> Double {
        seconds(at: timeline.totalTicks, factor: factor)
    }

    /// The tempo the range starts at (its first chord's `{tempo}`), nil without one.
    public var startTempo: Double? {
        timeline.chords.first?.tempo ?? timeline.passes.first?.tempo
    }

    /// The meter the range starts in.
    public var startMeter: Meter {
        timeline.chords.first?.meter ?? timeline.passes.first?.meter ?? .common
    }

    /// A converter between ticks and seconds at `factor`, for building events and the
    /// playhead.
    public func clock(factor: Double = 1) -> TickClock {
        TickClock(self, factor: factor)
    }
}

/// Ticks to seconds and back over one play-along timeline: each chord's onset and end in
/// seconds come from `SongTimeline.seconds`, and the tempo is constant inside a chord, so a
/// tick between them is a straight line.
public struct TickClock: Sendable {
    private let onsets: [Int]
    private let ends: [Int]
    private let starts: [Double]
    private let stops: [Double]
    /// Seconds per tick past the last chord.
    private let tailRate: Double
    public let total: Double

    init(_ timeline: PlayAlongTimeline, factor: Double) {
        let chords = timeline.timeline.chords
        onsets = chords.map(\.onset)
        ends = chords.map { $0.onset + $0.length }
        starts = onsets.map { timeline.seconds(at: $0, factor: factor) }
        stops = ends.map { timeline.seconds(at: $0, factor: factor) }
        let last = chords.last
        let bpm = max(1, (last?.tempo ?? timeline.startTempo ?? 1) * factor)
        tailRate = 60 / bpm / Double(last?.meter.ticksPerPulse ?? 480)
        total = timeline.duration(factor: factor)
    }

    /// Seconds from the range's start at `tick`.
    public func seconds(_ tick: Int) -> Double {
        guard let index = chord(containing: tick) else {
            guard let last = ends.last, tick > last else { return 0 }
            return (stops.last ?? 0) + Double(tick - last) * tailRate
        }
        let span = ends[index] - onsets[index]
        guard span > 0 else { return starts[index] }
        let fraction = Double(tick - onsets[index]) / Double(span)
        return starts[index] + fraction * (stops[index] - starts[index])
    }

    /// The tick at `seconds` from the range's start (the playhead), clamped to the range.
    public func tick(atSeconds seconds: Double) -> Int {
        guard !starts.isEmpty, seconds > 0 else { return 0 }
        var low = 0
        var high = starts.count - 1
        var found = 0
        while low <= high {
            let mid = (low + high) / 2
            if starts[mid] <= seconds {
                found = mid
                low = mid + 1
            } else {
                high = mid - 1
            }
        }
        let span = stops[found] - starts[found]
        guard span > 0 else { return onsets[found] }
        let fraction = min(max((seconds - starts[found]) / span, 0), 1)
        return onsets[found] + Int((fraction * Double(ends[found] - onsets[found])).rounded(.down))
    }

    private func chord(containing tick: Int) -> Int? {
        guard let first = onsets.first, tick >= first, let last = ends.last, tick <= last else {
            return nil
        }
        var low = 0
        var high = onsets.count - 1
        var found = 0
        while low <= high {
            let mid = (low + high) / 2
            if onsets[mid] <= tick {
                found = mid
                low = mid + 1
            } else {
                high = mid - 1
            }
        }
        return found
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
