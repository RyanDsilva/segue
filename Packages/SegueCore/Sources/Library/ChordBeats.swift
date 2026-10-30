// P8-4b (docs/phases/8-workstreams/P8-4-bass.md section 8.5, R161). How many beats each
// chord lasts, estimated from bar lines, beat marks or `{time}`. Pure; shared with P8-6's
// play-along timing.

import ChordPro
import Editing

public enum ChordBeats {
    public struct Estimate: Sendable, Hashable {
        public enum Source: String, Sendable, Hashable {
            case barLines
            case beatMarks
            case meterLine
            case unknown
        }

        /// nil when unknown.
        public var beats: Int?
        public var source: Source

        public init(beats: Int?, source: Source) {
            self.beats = beats
            self.source = source
        }

        public static let unknown = Self(beats: nil, source: .unknown)
    }

    /// Bar tokens, as `ChordLines`' decoration set has them.
    static let barTokens: Set = ["|", "||", "|:", ":|"]
    /// Beat marks: one more beat of the chord before them.
    static let beatMarks: Set = ["/", "."]
    /// A repeat bar: a bar holding no chord.
    static let repeatBar = "%"

    /// Whether chord text is layout, not a chord (`[|]`, `[/]`, `[%]` typed by hand): the
    /// beat estimate reads it as a mark, and a walk-up chain passes over it.
    public static func isMark(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        return barTokens.contains(trimmed) || beatMarks.contains(trimmed) || trimmed == repeatBar
    }

    /// One estimate per `.chord`-kind chord of `sections`, in written order, keyed by
    /// (section index, chord ordinal within the section). `time` is the song's `{time}`.
    public static func estimate(
        _ sections: [RenderSection],
        time: String?,
    ) -> [ChordPosition: Estimate] {
        let perBar = Metadata.pulses(ofTime: time)
        var result: [ChordPosition: Estimate] = [:]
        for (sectionIndex, section) in sections.enumerated() {
            var ordinal = 0
            for item in section.items {
                guard case let .lyrics(line) = item else { continue }
                let estimates = estimate(line, perBar: perBar, hasTime: time != nil)
                for estimate in estimates {
                    result[ChordPosition(section: sectionIndex, chord: ordinal)] = estimate
                    ordinal += 1
                }
            }
        }
        return result
    }

    /// The estimates of one line's `.chord`-kind chords, in order. A chord's estimate never
    /// reads past its own line.
    static func estimate(_ line: RenderLine, perBar: Int, hasTime: Bool) -> [Estimate] {
        let tokens = tokens(of: line)
        let chordCount = line.chords.count { $0.kind == .chord }
        guard chordCount > 0 else { return [] }
        if tokens.contains(where: \.isBar) {
            return barLines(tokens, perBar: perBar)
        }
        if tokens.contains(where: \.isBeatMark) {
            return beatMarks(tokens)
        }
        let chords = tokens.count(where: \.isChord)
        if hasTime, chords == 1 {
            return [Estimate(beats: perBar, source: .meterLine)]
        }
        return Array(repeating: .unknown, count: chordCount)
    }

    /// Rule 1: a chord's bar is the span between the bar tokens around it; it gets
    /// `perBar / chords in that bar` (at least 1), the bar's last chord plus `perBar` for
    /// each following bar on the line that holds no chord or only `%`.
    private static func barLines(_ tokens: [Token], perBar: Int) -> [Estimate] {
        var bars: [[Token]] = [[]]
        for token in tokens {
            if token.isBar {
                bars.append([])
            } else {
                bars[bars.count - 1].append(token)
            }
        }
        // Nothing before the first bar line or after the last is a bar of its own.
        if bars.first?.isEmpty == true {
            bars.removeFirst()
        }
        if bars.last?.isEmpty == true {
            bars.removeLast()
        }
        var result: [Estimate] = []
        for (index, bar) in bars.enumerated() {
            let chords = bar.filter(\.isChord)
            guard !chords.isEmpty else { continue }
            let share = max(1, perBar / chords.count)
            let held = bars[(index + 1)...].prefix { !$0.contains(where: \.isChord) }.count
            for (position, chord) in chords.enumerated() where chord.isChordKind {
                let extra = position == chords.count - 1 ? held * perBar : 0
                result.append(Estimate(beats: share + extra, source: .barLines))
            }
        }
        return result
    }

    /// Rule 2: `/` or `.` after a chord, before the next chord or bar: 1 + their count.
    private static func beatMarks(_ tokens: [Token]) -> [Estimate] {
        var result: [Estimate] = []
        var current: (isChord: Bool, marks: Int)?
        func close() {
            if let current, current.isChord {
                result.append(Estimate(beats: 1 + current.marks, source: .beatMarks))
            }
        }
        for token in tokens {
            switch token {
            case let .chord(isChordKind):
                close()
                current = (isChordKind, 0)
            case .beatMark:
                current?.marks += 1
            case .bar, .other:
                break
            }
        }
        close()
        return result
    }

    private enum Token {
        /// A chord of any kind (`isChordKind` for `.chord`).
        case chord(isChordKind: Bool)
        case bar
        case beatMark
        case other

        var isChord: Bool {
            if case .chord = self {
                true
            } else {
                false
            }
        }

        var isChordKind: Bool {
            if case let .chord(isChordKind) = self {
                isChordKind
            } else {
                false
            }
        }

        var isBar: Bool {
            if case .bar = self {
                true
            } else {
                false
            }
        }

        var isBeatMark: Bool {
            if case .beatMark = self {
                true
            } else {
                false
            }
        }
    }

    /// The line's chords and whitespace-separated words in order; chord text that is a mark
    /// (`[|]`) reads as that mark.
    private static func tokens(of line: RenderLine) -> [Token] {
        struct Event {
            var offset: Int
            var order: Int
            var token: Token
        }
        var events: [Event] = []
        for (index, chord) in line.chords.enumerated() {
            let trimmed = chord.original.trimmingCharacters(in: .whitespaces)
            let token: Token = if chord.kind == .unknown, isMark(trimmed) {
                classify(trimmed)
            } else {
                .chord(isChordKind: chord.kind == .chord)
            }
            events.append(Event(offset: chord.offset, order: index, token: token))
        }
        var word = ""
        var start = 0
        func flush() {
            if !word.isEmpty {
                events.append(Event(offset: start, order: Int.max, token: classify(word)))
            }
            word = ""
        }
        for offset in 0 ..< line.lyricCount {
            let character = line.character(at: offset)
            if character.allSatisfy(\.isWhitespace) {
                flush()
            } else {
                if word.isEmpty {
                    start = offset
                }
                word += character
            }
        }
        flush()
        // Chords before a word that starts at the same offset (`[G]Hello`).
        return events.sorted { ($0.offset, $0.order) < ($1.offset, $1.order) }.map(\.token)
    }

    private static func classify(_ word: String) -> Token {
        if barTokens.contains(word) {
            return .bar
        }
        if beatMarks.contains(word) {
            return .beatMark
        }
        return .other
    }
}
