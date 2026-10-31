// P8-7a (docs/phases/8-workstreams/P8-7-time-model-and-fills.md sections 5.2, 5.4, R167 Q1).
// The one timing system: every chord's length, onset, meter, tempo and key in played
// order, layered over the `.cho` (the song's rule, then the chart's own marks and grids, then
// the user's corrections). Walk-ups, play-along and fills read it; nothing else computes a
// chord's length. Pure.

import ChordPro
import Editing
import MusicTheory

/// Where a chord's length came from. A chord whose source is `.rule` is estimated.
public enum TimingSource: String, Sendable, Hashable {
    /// The song's timing rule (`bass.timing.rule`; one bar per chord when absent).
    case rule
    /// Bar lines, beat marks, or one chord on a line under `{time}`.
    case chart
    /// A ChordPro grid.
    case grid
    /// The user's correction.
    case user
    /// A correction written by tap capture.
    case tap
}

/// A chord played early, ahead of the beat (the bar grid does not move).
public enum Push: String, Sendable, Hashable, Codable, CaseIterable {
    case eighth = "8"
    case sixteenth = "16"

    public var ticks: Int {
        switch self {
        case .eighth: Ticks.eighth
        case .sixteenth: Ticks.sixteenth
        }
    }
}

/// A position on the bar grid.
public struct BarBeat: Sendable, Hashable, CustomStringConvertible {
    /// 1-based.
    public var bar: Int
    /// 1-based pulse in the bar.
    public var beat: Int
    /// Ticks into the beat.
    public var tick: Int

    public init(bar: Int, beat: Int, tick: Int) {
        self.bar = bar
        self.beat = beat
        self.tick = tick
    }

    /// "3:2" or "3:2+240".
    public var description: String {
        tick == 0 ? "\(bar):\(beat)" : "\(bar):\(beat)+\(tick)"
    }
}

/// One chord as played.
public struct TimedChord: Sendable, Hashable {
    /// The written section and ordinal among its `.chord` chords (grid chords included); a
    /// `{chorus}` stub's chords keep their chorus's positions. For `N.C.` (`isSilent`), the
    /// ordinal the section's next chord has; never matched by `length(of:)`.
    public var position: ChordPosition
    /// Index into `SongTimeline.passes`: the played order, or one pass per render section in
    /// written order.
    public var pass: Int
    /// 1-based: which play of this content section this is (a `{chorus}` stub plays its
    /// chorus again).
    public var occurrence: Int
    /// The chord as written ("G/B", "N.C.").
    public var token: String
    /// The line it is written on (a grid line for a grid chord).
    public var line: BlockPath
    /// Ticks from the timeline's start, after any push.
    public var onset: Int
    /// Ticks until the next chord's onset.
    public var length: Int
    /// The push that applied (nil when none, or when it was ignored).
    public var push: Push?
    public var source: TimingSource
    /// In effect here.
    public var meter: Meter
    /// Pulses per minute; nil without `{tempo}`.
    public var tempo: Double?
    /// The written key (the shape key under a capo).
    public var key: SongKey?
    /// `N.C.`: a timed silence.
    public var isSilent: Bool

    /// Whether the length is estimated (the song's rule).
    public var isEstimated: Bool {
        source == .rule
    }

    /// The length in whole pulses, at least 1.
    public var pulses: Int {
        max(1, length / meter.ticksPerPulse)
    }
}

/// One played pass (written order: one per render section).
public struct TimedPass: Sendable, Hashable {
    /// The render section played (a `{chorus}` stub's own index for a stub).
    public var section: Int
    /// The render section whose chords it plays (a stub's chorus).
    public var content: Int
    /// 1-based play of `content`.
    public var occurrence: Int
    public var mode: PassMode
    /// Index into `SlotArrangement.passes`; nil in written order or the full song.
    public var position: Int?
    /// Ticks from the timeline's start (the bar grid, before any push).
    public var start: Int
    public var end: Int
    /// In effect at the pass's first chord (else its start).
    public var meter: Meter
    public var tempo: Double?
    public var key: SongKey?
}

/// The song's chords in played order, timed in ticks (480 per quarter).
public struct SongTimeline: Sendable, Hashable {
    public var meters: MeterMap
    public var tempos: TempoMap
    public var keys: KeyMap
    /// In played order.
    public var chords: [TimedChord]
    public var passes: [TimedPass]
    public var totalTicks: Int
    /// Corrections that no longer match the song (kept in the sidecar, ignored here).
    public var unmatched: [ChordBeatsOverride]
    /// The layered lengths before pushes and bar rounding (what a slice is cut from).
    var entries: [Entry]
    /// Bar grid segments, one per meter change.
    var bars: [BarSegment]
    /// (pass, ordinal) to the index of its first chord, for `timed(pass:chord:)`.
    var lookup: [ChordPosition: Int]

    struct Entry: Sendable, Hashable {
        var chord: TimedChord
        /// The grid length (before a push).
        var length: Int
        var push: Push?
        /// A chordless lyric line or a grid's lead-in may extend it.
        var extendable: Bool
    }

    struct BarSegment: Sendable, Hashable {
        var start: Int
        var meter: Meter
        var firstBar: Int
    }

    /// Every chord shorter than a sixteenth is lengthened to one.
    public static let minimumLength = Ticks.sixteenth
    /// At most 32 pulses.
    public static let maximumPulses = 32

    public static let empty = Self(
        meters: MeterMap(initial: .common),
        tempos: TempoMap(initial: nil),
        keys: KeyMap(initial: nil),
        chords: [],
        passes: [],
        totalTicks: 0,
        unmatched: [],
        entries: [],
        bars: [BarSegment(start: 0, meter: .common, firstBar: 1)],
        lookup: [:],
    )

    // MARK: Queries

    /// The length and source of the chord at a written position (its first play).
    public func length(of position: ChordPosition) -> (ticks: Int, source: TimingSource)? {
        chords.first { !$0.isSilent && $0.position == position }.map { ($0.length, $0.source) }
    }

    /// The chord with ordinal `chord` played in pass `pass` (silent chords excluded). In
    /// written order the pass is the render section index, a stub's included.
    public func timed(pass: Int, chord: Int) -> TimedChord? {
        lookup[ChordPosition(section: pass, chord: chord)].map { chords[$0] }
    }

    /// Bar and beat at `tick` on the bar grid (a meter change starts a new bar).
    public func barBeat(at tick: Int) -> BarBeat {
        let segment = bars.last { $0.start <= tick } ?? bars[0]
        let offset = max(0, tick - segment.start)
        let bar = segment.meter.ticksPerBar
        let within = offset % bar
        return BarBeat(
            bar: segment.firstBar + offset / bar,
            beat: within / segment.meter.ticksPerPulse + 1,
            tick: within % segment.meter.ticksPerPulse,
        )
    }

    /// The tick of a bar and beat (`barBeat(at:)`'s inverse).
    public func tick(of position: BarBeat) -> Int {
        let segment = bars.last { $0.firstBar <= position.bar } ?? bars[0]
        return segment.start + (position.bar - segment.firstBar) * segment.meter.ticksPerBar
            + (position.beat - 1) * segment.meter.ticksPerPulse + position.tick
    }

    /// The index of the chord sounding at `tick`.
    public func chord(atTick tick: Int) -> Int? {
        guard tick >= 0, tick < totalTicks else { return nil }
        var low = 0
        var high = chords.count - 1
        var found: Int?
        while low <= high {
            let mid = (low + high) / 2
            if chords[mid].onset <= tick {
                found = mid
                low = mid + 1
            } else {
                high = mid - 1
            }
        }
        return found
    }

    /// The onset of the first chord on `line` in pass `pass`.
    public func lineOnset(_ line: BlockPath, pass: Int) -> Int? {
        chords.first { $0.pass == pass && $0.line == line }?.onset
    }

    /// Seconds from the timeline's start to `tick`, each chord at the `{tempo}` in effect
    /// (`fallback` BPM without one) times `factor`.
    public func seconds(at tick: Int, factor: Double = 1, fallback: Double = 90) -> Double {
        var total = 0.0
        var reached = 0
        for chord in chords where chord.onset < tick {
            let start = max(chord.onset, reached)
            let end = min(chord.onset + chord.length, tick)
            guard end > start else { continue }
            let bpm = max(1, (chord.tempo ?? fallback) * factor)
            total += Double(end - start) / Double(chord.meter.ticksPerPulse) * 60 / bpm
            reached = end
        }
        if tick > reached {
            let last = chords.last
            let bpm = max(1, (last?.tempo ?? fallback) * factor)
            let pulse = last?.meter.ticksPerPulse ?? Ticks.perQuarter
            total += Double(tick - reached) / Double(pulse) * 60 / bpm
        }
        return total
    }

    /// What play-along plays (P8-6 section 7.5): the passes in `passes` alone, from tick 0,
    /// rounded up to whole bars by lengthening the last chord so a loop wraps on a downbeat.
    /// A push on the slice's first chord is ignored.
    public func slice(passes range: Range<Int>) -> Self {
        let kept = entries.filter { range.contains($0.chord.pass) }
        var result = Self.assemble(
            kept,
            passes: passes,
            maps: PositionalMaps(meters: meters, tempos: tempos, keys: keys),
            unmatched: unmatched,
            roundToBars: true,
        )
        result.passes = Array(result.passes[range.clamped(to: result.passes.indices)])
        return result.renumbered(from: range.lowerBound)
    }

    // MARK: Build

    /// The timeline of `document` (its `RenderModel.sections` as `sections`, its
    /// `SongSections.units(of:)` as `units`) with the song's sidecar `timing`. `order` nil is
    /// the written song with `{chorus}` stubs written out (the editor and library); on the
    /// Rehearsal stage it is P8-2's played passes (a Skip pass plays nothing).
    public static func build(
        document: SongDocument,
        sections: [RenderSection],
        units: [SongSectionUnit],
        timing: ChordTiming,
        order: [PlayedPass]?,
    ) -> Self {
        var builder = Builder(
            document: document,
            sections: sections,
            units: units,
            timing: timing,
        )
        let plays = order ?? sections.indices.map { PlayedPass(index: $0) }
        for play in plays where sections.indices.contains(play.index) && play.mode != .skip {
            builder.play(play)
        }
        return assemble(
            builder.entries,
            passes: builder.passes,
            maps: builder.directives.maps(sections),
            unmatched: builder.unmatched,
            roundToBars: false,
        )
    }
}

// MARK: - Assembly

extension SongTimeline {
    /// Onsets (cumulative grid lengths), pushes, the bar grid and the lookup.
    static func assemble(
        _ entries: [Entry],
        passes: [TimedPass],
        maps: PositionalMaps,
        unmatched: [ChordBeatsOverride],
        roundToBars: Bool,
    ) -> Self {
        var entries = entries.map { entry in
            var entry = entry
            let most = maximumPulses * entry.chord.meter.ticksPerPulse
            entry.length = min(max(entry.length, minimumLength), most)
            return entry
        }
        var grid = Grid(entries)
        if roundToBars {
            grid.roundUp(&entries)
        }
        let chords = pushed(entries, onsets: grid.onsets)
        return Self(
            meters: maps.meters,
            tempos: maps.tempos,
            keys: maps.keys,
            chords: chords,
            passes: bounds(passes, entries: entries, onsets: grid.onsets),
            totalTicks: grid.total,
            unmatched: unmatched,
            entries: entries,
            bars: grid.bars,
            lookup: lookup(chords),
        )
    }

    /// The bar grid: each entry's onset before any push, one segment per meter change.
    struct Grid {
        var onsets: [Int] = []
        var bars: [BarSegment]
        var total = 0

        init(_ entries: [Entry]) {
            bars = [BarSegment(start: 0, meter: entries.first?.chord.meter ?? .common, firstBar: 1)]
            onsets.reserveCapacity(entries.count)
            for entry in entries {
                let meter = entry.chord.meter
                if let last = bars.last, last.meter != meter {
                    let span = total - last.start
                    if span <= 0 {
                        bars[bars.count - 1].meter = meter
                    } else {
                        let used = (span + last.meter.ticksPerBar - 1) / last.meter.ticksPerBar
                        bars.append(BarSegment(
                            start: total,
                            meter: meter,
                            firstBar: last.firstBar + used,
                        ))
                    }
                }
                onsets.append(total)
                total += entry.length
            }
        }

        /// Lengthens the last entry so the total ends on a bar line.
        mutating func roundUp(_ entries: inout [Entry]) {
            guard let last = bars.last, !entries.isEmpty else { return }
            let remainder = (total - last.start) % last.meter.ticksPerBar
            guard remainder > 0 else { return }
            let extra = last.meter.ticksPerBar - remainder
            entries[entries.count - 1].length += extra
            total += extra
        }
    }

    /// The chords at their onsets; a push moves its chord's onset earlier and shortens the
    /// chord before (the grid stays), unless that would leave less than a sixteenth.
    static func pushed(_ entries: [Entry], onsets: [Int]) -> [TimedChord] {
        var chords = entries.enumerated().map { index, entry in
            var chord = entry.chord
            chord.onset = onsets[index]
            chord.length = entry.length
            chord.push = nil
            return chord
        }
        for index in chords.indices.dropFirst() {
            guard let push = entries[index].push,
                  chords[index - 1].length - push.ticks >= minimumLength
            else { continue }
            chords[index].onset -= push.ticks
            chords[index].length += push.ticks
            chords[index].push = push
            chords[index - 1].length -= push.ticks
        }
        return chords
    }

    /// (pass, ordinal) to the first such chord.
    static func lookup(_ chords: [TimedChord]) -> [ChordPosition: Int] {
        var lookup: [ChordPosition: Int] = [:]
        for (index, chord) in chords.enumerated() where !chord.isSilent {
            let key = ChordPosition(section: chord.pass, chord: chord.position.chord)
            if lookup[key] == nil {
                lookup[key] = index
            }
        }
        return lookup
    }

    /// Each pass's start and end on the grid; a pass with no chords sits where the one before
    /// it ended.
    static func bounds(_ passes: [TimedPass], entries: [Entry], onsets: [Int]) -> [TimedPass] {
        var passes = passes
        var seen = Set<Int>()
        for (index, entry) in entries.enumerated() {
            let pass = entry.chord.pass
            guard passes.indices.contains(pass) else { continue }
            if seen.insert(pass).inserted {
                passes[pass].start = onsets[index]
            }
            passes[pass].end = onsets[index] + entry.length
        }
        var reached = 0
        for index in passes.indices {
            if seen.contains(index) {
                reached = passes[index].end
            } else {
                passes[index].start = reached
                passes[index].end = reached
            }
        }
        return passes
    }

    /// Passes renumbered so the slice's first pass is 0 (its chords and lookup follow).
    func renumbered(from first: Int) -> Self {
        guard first != 0 else { return self }
        var copy = self
        for index in copy.chords.indices {
            copy.chords[index].pass -= first
        }
        for index in copy.entries.indices {
            copy.entries[index].chord.pass -= first
        }
        copy.lookup = Dictionary(uniqueKeysWithValues: lookup.map { key, value in
            (ChordPosition(section: key.section - first, chord: key.chord), value)
        })
        return copy
    }
}
