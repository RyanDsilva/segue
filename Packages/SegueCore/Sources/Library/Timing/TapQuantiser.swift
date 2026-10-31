// P8-7b (docs/phases/8-workstreams/P8-7-time-model-and-fills.md section 7, R167 Q6). Tap
// capture's arithmetic: taps (seconds on the injected clock) become chord lengths on the
// beat grid, either the click's grid at a known tempo or a tempo derived from the taps.
// Nothing here writes: the result is a proposal the user reviews. Pure but for the
// stopwatch, which reads the injected `Clock`.

import Foundation
import Support

/// Seconds since an origin on the injected clock: when each tap happened.
public struct TapStopwatch: Sendable {
    private let clock: any Clock
    /// The click grid's first downbeat (after the count-in), or the capture's start.
    public let origin: Date

    public init(clock: any Clock, startingIn delay: TimeInterval = 0) {
        self.clock = clock
        origin = clock.now().addingTimeInterval(delay)
    }

    /// Seconds from the origin now (negative before it, during a count-in).
    public func seconds() -> Double {
        clock.now().timeIntervalSince(origin)
    }
}

/// With Segue's click at a known tempo, or with no sound and the tempo from the taps.
public enum TapMode: String, Sendable, Hashable, Codable, CaseIterable {
    case click
    case free
}

/// One key while tapping.
public enum TapEvent: Sendable, Hashable {
    /// Space or Page Down: the next chord starts now, `seconds` from the capture's origin (the
    /// click grid's first downbeat; any origin without the click). `half` while ⌥ is held.
    case tap(seconds: Double, half: Bool)
    /// Tab: the next chord keeps its lower-layer length.
    case skip
}

/// What a capture proposes, chord by chord, for review before anything is saved.
public struct TapProposal: Sendable, Hashable {
    public enum Outcome: Sendable, Hashable {
        /// Tapped to a new length.
        case changed
        /// Tapped to the length it already had.
        case unchanged
        /// Skipped with Tab, or a tap that would have left it no length: keeps its length.
        case skipped
        /// Not reached (or the last one tapped, with no tap after it): keeps its length.
        case untapped
    }

    public struct Chord: Sendable, Hashable {
        /// Index into the chords tapped over.
        public var index: Int
        /// The length before, in ticks on the bar grid.
        public var old: Int
        /// The length proposed (`old` unless changed).
        public var new: Int
        public var outcome: Outcome
    }

    public var chords: [Chord]
    /// The tempo the taps were quantised at (the click's, or derived).
    public var tempo: Double
    /// Taps counted (Tab excluded).
    public var taps: Int

    public var changed: [Chord] {
        chords.filter { $0.outcome == .changed }
    }

    public var skipped: Int {
        chords.count { $0.outcome == .skipped }
    }
}

public enum TapQuantiser {
    /// The derived tempo's search range and step (BPM, pulses per minute).
    public static let tempoRange = 40.0 ... 240.0
    public static let tempoStep = 0.5
    /// A candidate tempo whose error is within this share of the tapped time of the best is
    /// as good as the best (the song's `{tempo}` is then preferred).
    public static let tolerance = 0.02

    /// A chord as the lane holds it: its length on the bar grid and its pulse.
    public struct Chord: Sendable, Hashable {
        public var ticks: Int
        public var ticksPerPulse: Int

        public init(ticks: Int, ticksPerPulse: Int) {
            self.ticks = ticks
            self.ticksPerPulse = ticksPerPulse
        }

        var pulses: Double {
            Double(ticks) / Double(ticksPerPulse)
        }
    }

    /// How a capture was taken.
    public struct Options: Sendable, Hashable {
        public var mode: TapMode
        /// The click's tempo; without the click, one that overrides the derived tempo (the
        /// review's -/+).
        public var tempo: Double?
        /// Every tap snaps to half pulses (else only taps with `half`).
        public var halfBeats: Bool
        /// The song's `{tempo}` at the range's start.
        public var hint: Double?
        /// The range's first meter.
        public var pulsesPerBar: Int

        public init(
            mode: TapMode,
            tempo: Double? = nil,
            halfBeats: Bool = false,
            hint: Double? = nil,
            pulsesPerBar: Int = 4,
        ) {
            self.mode = mode
            self.tempo = tempo
            self.halfBeats = halfBeats
            self.hint = hint
            self.pulsesPerBar = pulsesPerBar
        }
    }

    /// Quantises `events` over `chords`. Click mode: at the click's tempo, with the taps'
    /// seconds counted from the click grid's first downbeat. Free mode: at the tempo the taps
    /// imply (`tempo(intervals:)`, preferring the song's `{tempo}`), from the first tap.
    public static func propose(
        _ events: [TapEvent],
        chords: [Chord],
        options: Options,
    ) -> TapProposal {
        let (mode, tempo, halfBeats, hint) = (
            options.mode, options.tempo, options.halfBeats, options.hint,
        )
        let times = events.compactMap { event -> Double? in
            if case let .tap(seconds, _) = event {
                return seconds
            }
            return nil
        }
        let bpm: Double = switch mode {
        case .click:
            tempo ?? hint ?? 90
        case .free:
            tempo ?? Self.tempo(
                intervals: zip(times.dropFirst(), times).map { $0 - $1 },
                halfBeats: halfBeats,
                hint: hint,
                expected: median(chords.map(\.pulses)),
                pulsesPerBar: options.pulsesPerBar,
            )
        }
        let origin = mode == .free ? times.first ?? 0 : 0
        var walk = Walk(chords: chords)
        for event in events {
            switch event {
            case .skip:
                walk.skip()
            case let .tap(seconds, half):
                let step = halfBeats || half ? 0.5 : 1
                walk.tap(at: snap((seconds - origin) * bpm / 60, step: step))
            }
        }
        return TapProposal(chords: walk.result, tempo: bpm, taps: times.count)
    }

    /// The tempo that best explains `intervals` (seconds between taps): a search over
    /// `tempoRange` in `tempoStep` steps for the least summed error of each interval to a
    /// whole number of pulses (half pulses with `halfBeats`). Among tempos within
    /// `tolerance` of the best: the song's `hint` when it is one; else those whose lengths sum
    /// to whole bars; then the one whose typical chord length is nearest the chords' own
    /// (`expected` pulses: one bar per chord by the song's rule unless corrected, which
    /// settles whether a tap is a beat or a half beat); then the closest fit (least squares);
    /// then the slower.
    public static func tempo(
        intervals: [Double],
        halfBeats: Bool = false,
        hint: Double? = nil,
        expected: Double? = nil,
        pulsesPerBar: Int = 4,
    ) -> Double {
        let intervals = intervals.filter { $0 > 0 }
        guard !intervals.isEmpty else { return hint ?? 90 }
        let total = intervals.reduce(0, +)
        let candidates = candidates(intervals, step: halfBeats ? 0.5 : 1)
        guard let best = candidates.min(by: { $0.error < $1.error }) else { return hint ?? 90 }
        let good = candidates.filter { $0.error <= best.error + tolerance * total }
        if let hint, good.contains(where: { abs($0.bpm - hint) < tempoStep / 2 + 1e-9 }) {
            return hint
        }
        let bars = good.filter { candidate in
            let sum = candidate.pulses.reduce(0, +)
            return sum.truncatingRemainder(dividingBy: Double(max(1, pulsesPerBar))) == 0
        }
        let pool = bars.isEmpty ? good : bars
        func distance(_ candidate: Candidate) -> Double {
            guard let expected, expected > 0, let typical = median(candidate.pulses) else {
                return 0
            }
            return abs(log2(typical / expected))
        }
        let chosen = pool.min { lhs, rhs in
            let (left, right) = (distance(lhs), distance(rhs))
            if abs(left - right) > 1e-9 {
                return left < right
            }
            if abs(lhs.squares - rhs.squares) > 1e-12 {
                return lhs.squares < rhs.squares
            }
            return lhs.bpm < rhs.bpm
        }
        return chosen?.bpm ?? best.bpm
    }

    /// One tempo tried.
    private struct Candidate {
        var bpm: Double
        /// Summed seconds off the grid (the tolerance's measure).
        var error: Double
        /// Summed squares (the closest fit among equals: the centre of a flat run).
        var squares: Double
        var pulses: [Double]
    }

    /// Every tempo in the range at which no interval rounds to nothing.
    private static func candidates(_ intervals: [Double], step: Double) -> [Candidate] {
        var candidates: [Candidate] = []
        var bpm = tempoRange.lowerBound
        while bpm <= tempoRange.upperBound {
            let pulses = intervals.map { snap($0 * bpm / 60, step: step) }
            if !pulses.contains(where: { $0 <= 0 }) {
                let offsets = zip(intervals, pulses).map { abs($0 - $1 * 60 / bpm) }
                candidates.append(Candidate(
                    bpm: bpm,
                    error: offsets.reduce(0, +),
                    squares: offsets.reduce(0) { $0 + $1 * $1 },
                    pulses: pulses,
                ))
            }
            bpm += tempoStep
        }
        return candidates
    }

    // MARK: Walking the taps

    /// The chords as taps reach them: a tap starts the next chord and ends the one before;
    /// a skip passes over the next chord, which keeps its length (the time it takes comes out
    /// of the interval it falls in).
    private struct Walk {
        let chords: [Chord]
        var result: [TapProposal.Chord]
        /// The next chord to start.
        var next = 0
        /// The chord sounding and the pulse it started on.
        var started: (index: Int, at: Double)?
        /// Chords skipped since it started.
        var passed: [Int] = []

        init(chords: [Chord]) {
            self.chords = chords
            result = chords.enumerated().map { index, chord in
                TapProposal.Chord(
                    index: index,
                    old: chord.ticks,
                    new: chord.ticks,
                    outcome: .untapped,
                )
            }
        }

        mutating func skip() {
            guard next < chords.count else { return }
            result[next].outcome = .skipped
            if started != nil {
                passed.append(next)
            }
            next += 1
        }

        mutating func tap(at pulse: Double) {
            if let started {
                let skipped = passed.reduce(0) { $0 + chords[$1].pulses }
                close(started.index, pulses: pulse - started.at - skipped)
            } else if next >= chords.count {
                return
            }
            passed = []
            if next < chords.count {
                started = (next, pulse)
                next += 1
            } else {
                started = nil
                next = chords.count + 1
            }
        }

        /// Chord `index` lasted `pulses`: its new length, or skipped when that is nothing.
        private mutating func close(_ index: Int, pulses: Double) {
            let chord = chords[index]
            let ticks = Int((pulses * Double(chord.ticksPerPulse)).rounded())
            guard ticks >= SongTimeline.minimumLength else {
                result[index].outcome = .skipped
                return
            }
            let most = SongTimeline.maximumPulses * chord.ticksPerPulse
            let new = min(ticks, most)
            result[index].new = new
            result[index].outcome = new == chord.ticks ? .unchanged : .changed
        }
    }

    // MARK: Helpers

    /// `value` to the nearest multiple of `step`.
    static func snap(_ value: Double, step: Double) -> Double {
        (value / step).rounded() * step
    }

    static func median(_ values: [Double]) -> Double? {
        let sorted = values.sorted()
        guard !sorted.isEmpty else { return nil }
        let middle = sorted.count / 2
        return sorted.count.isMultiple(of: 2)
            ? (sorted[middle - 1] + sorted[middle]) / 2 : sorted[middle]
    }
}
