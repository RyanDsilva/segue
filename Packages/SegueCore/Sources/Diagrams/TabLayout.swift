// P8-7d (docs/phases/8-workstreams/P8-7-time-model-and-fills.md sections 12.6, 12.8, 14.2): the
// mini tab a fill draws in the fill editor and, as a block, on stage. Pure: the caller measures
// text (SwiftUI in the editor, Core Text in LiveLayout), so both lay it out identically.

import MusicTheory

/// One note to draw in a mini tab. Diagrams' own input type (Diagrams cannot see Library's
/// `ResolvedNote`; `TabNote(_:isLanding:)` in Library adapts one).
public struct TabNote: Sendable, Hashable {
    /// Ticks from the timeline's start (480 per quarter).
    public var tick: Int
    /// Ticks. Carried for callers; the tab shows rhythm by spacing only (no stems).
    public var length: Int
    /// Where it is played; nil when it has no playable position (drawn as "?").
    public var position: FretPosition?
    public var articulations: Set<Articulation>
    /// The spelled note name ("F#"), for the spoken text.
    public var name: String
    /// The landing chord's root, drawn in the landing bar and spoken as "then A".
    public var isLanding: Bool

    public init(
        tick: Int,
        length: Int,
        position: FretPosition?,
        articulations: Set<Articulation> = [],
        name: String,
        isLanding: Bool = false,
    ) {
        self.tick = tick
        self.length = length
        self.position = position
        self.articulations = articulations
        self.name = name
        self.isLanding = isLanding
    }
}

/// A mini tab laid out in points (origin top-left, y down): one line per string (the highest
/// on top) labelled with its open string's letter, fret glyphs placed in proportion to their
/// tick (rhythm as spacing), accents above the staff and staccato dots below it, a short tick
/// under each pulse, a bar line at each bar and chord names above at their onsets.
///
/// Rows, top to bottom: chord names, accent marks, the staff, staccato marks, the beat ruler.
public struct TabLayout: Sendable, Hashable {
    /// Fixed vertical metrics and spacing, in points. The defaults suit a 10 pt glyph face;
    /// the stage scales them with its type.
    public struct Metrics: Sendable, Hashable {
        /// Distance between neighbouring string lines.
        public var lineGap: Double
        /// Height of the chord-name row.
        public var chordRow: Double
        /// Height of the accent row above the staff and of the staccato row below it.
        public var markRow: Double
        /// Height of the beat ruler under the staff.
        public var rulerRow: Double
        /// Length of a beat tick.
        public var tickLength: Double
        /// The height a glyph occupies on its line (lines are broken behind it).
        public var glyphHeight: Double
        /// Space between the label column and the first tick.
        public var labelGap: Double
        /// A glyph starts this far right of its onset (clear of a bar line there).
        public var onsetInset: Double
        /// The least space between two glyphs (or chord names) on one row.
        public var glyphGap: Double
        /// Space kept clear on each side of a glyph where its line is broken.
        public var linePad: Double

        public init(
            lineGap: Double = 12,
            chordRow: Double = 16,
            markRow: Double = 8,
            rulerRow: Double = 6,
            tickLength: Double = 4,
            glyphHeight: Double = 10,
            labelGap: Double = 6,
            onsetInset: Double = 3,
            glyphGap: Double = 3,
            linePad: Double = 1.5,
        ) {
            self.lineGap = lineGap
            self.chordRow = chordRow
            self.markRow = markRow
            self.rulerRow = rulerRow
            self.tickLength = tickLength
            self.glyphHeight = glyphHeight
            self.labelGap = labelGap
            self.onsetInset = onsetInset
            self.glyphGap = glyphGap
            self.linePad = linePad
        }
    }

    /// One string's line.
    public struct Line: Sendable, Hashable {
        /// 0 = the lowest string.
        public var string: Int
        /// The open string's letter ("G", "A#").
        public var label: String
        /// The label's leading x (it is vertically centred on `y`).
        public var labelX: Double
        public var y: Double
        /// The drawn stretches of the line, left to right: broken behind every glyph on it.
        public var segments: [Range<Double>]
    }

    /// A fret glyph: an articulation prefix and the fret ("s7", "h9", "p7"), "x" for a ghost
    /// note, "?" for a note with no playable position.
    public struct Glyph: Sendable, Hashable {
        public var text: String
        /// Leading x; the text is vertically centred on `y`.
        public var x: Double
        public var width: Double
        public var y: Double
        /// The string it sits on; nil for "?" (centred on the staff).
        public var string: Int?
        public var tick: Int
        public var isLanding: Bool

        public var maxX: Double {
            x + width
        }
    }

    /// A text item on a row of its own (a chord name, an accent ">" or a staccato ".").
    public struct Label: Sendable, Hashable {
        public var text: String
        /// Leading x; the text is vertically centred on `y`.
        public var x: Double
        public var width: Double
        public var y: Double
    }

    public var lines: [Line]
    public var glyphs: [Glyph]
    /// Accent ">" marks above the staff and staccato "." marks below it, each centred over
    /// its glyph.
    public var marks: [Label]
    /// Chord names above the staff at their onsets.
    public var chords: [Label]
    /// The x of a short tick under each pulse, from `rulerY` down `metrics.tickLength`.
    public var beatTicks: [Double]
    public var rulerY: Double
    /// The x of a bar line at each bar, from the top line to the bottom line.
    public var barLines: [Double]
    public var width: Double
    public var height: Double
    /// The accessibility text: "Tab: A string 7, 9, D string 7, then A".
    public var spoken: String

    /// Lays out `notes` over `ticks` at `width` points.
    ///
    /// - Parameters:
    ///   - chords: chord names at their onset ticks; those outside `ticks` are dropped.
    ///   - pulses: the onset tick of every beat (a tick is drawn under each one in `ticks`).
    ///   - bars: the onset tick of every bar (a bar line at each one in `ticks`, either end
    ///     included).
    ///   - tuning: names and counts the lines (4 or 5 for a bass).
    ///   - measure: the width in points of a string in the face the caller draws with.
    public static func layout(
        // swiftlint:disable:previous function_parameter_count
        notes: [TabNote],
        chords: [(tick: Int, name: String)],
        ticks: Range<Int>,
        pulses: [Int],
        bars: [Int],
        tuning: Tuning,
        width: Double,
        metrics: Metrics = Metrics(),
        measure: (String) -> Double,
    ) -> Self {
        let labels = tuning.strings.indices.map { tuning.openStringName($0) }
        let labelWidth = labels.map(measure).max() ?? 0
        let ordered = notes.sorted { $0.tick < $1.tick }
        let texts = ordered.map(glyphText)
        let left = labelWidth + metrics.labelGap
        let frame = Frame(
            ticks: ticks,
            left: left,
            right: max(left + 1, width - (texts.map(measure).max() ?? 0) - metrics.onsetInset),
            inset: metrics.onsetInset,
        )
        let staff = Staff(strings: labels.count, frame: frame, metrics: metrics)
        let glyphs = placeGlyphs(ordered, texts: texts, staff: staff, measure: measure)
        let lines = labels.indices.reversed().map { string in
            Line(
                string: string,
                label: labels[string],
                labelX: labelWidth - measure(labels[string]),
                y: staff.y(string),
                segments: segments(to: width, y: staff.y(string), glyphs: glyphs, staff: staff),
            )
        }
        return Self(
            lines: lines,
            glyphs: glyphs,
            marks: marks(ordered, glyphs: glyphs, staff: staff, measure: measure),
            chords: placeChords(chords, staff: staff, measure: measure),
            beatTicks: pulses.filter { ticks.contains($0) }
                .map { frame.onset($0) + measure("0") / 2 },
            rulerY: staff.ruler + (metrics.rulerRow - metrics.tickLength) / 2,
            barLines: bars.filter { ticks.lowerBound <= $0 && $0 <= ticks.upperBound }
                .map(frame.x),
            width: max(width, glyphs.map(\.maxX).max() ?? 0),
            height: staff.ruler + metrics.rulerRow,
            spoken: spoken(ordered, tuning: tuning),
        )
    }

    /// A note's glyph: "?" without a position, "x" for a ghost, else the fret with a slide,
    /// hammer-on or pull-off prefix.
    public static func glyphText(_ note: TabNote) -> String {
        guard let position = note.position else { return "?" }
        if note.articulations.contains(.ghost) {
            return "x"
        }
        let prefix = if note.articulations.contains(.slide) {
            "s"
        } else if note.articulations.contains(.hammer) {
            "h"
        } else if note.articulations.contains(.pull) {
            "p"
        } else {
            ""
        }
        return prefix + String(position.fret)
    }

    /// The tab read aloud in order, consecutive notes on one string grouped under it, the
    /// landing note last: "Tab: A string 7, slide 9, D string 7, then A".
    public static func spoken(_ notes: [TabNote], tuning: Tuning) -> String {
        let ordered = notes.sorted { $0.tick < $1.tick }
        var parts: [String] = []
        var string: Int?
        for note in ordered {
            if note.isLanding {
                parts.append("then " + spokenName(note.name))
                string = nil
                continue
            }
            guard let position = note.position else {
                parts.append(spokenName(note.name) + " with no position")
                string = nil
                continue
            }
            var words = spokenArticulations(note)
            if !note.articulations.contains(.ghost) {
                words.append(String(position.fret))
            }
            var said = words.joined(separator: " ")
            if position.string != string {
                said = spokenName(tuning.openStringName(position.string)) + " string " + said
                string = position.string
            }
            parts.append(said)
        }
        return parts.isEmpty ? "Tab: no notes" : "Tab: " + parts.joined(separator: ", ")
    }
}

// MARK: - Placement

private extension TabLayout {
    /// Maps ticks to x between the label column and the right margin.
    struct Frame {
        let ticks: Range<Int>
        let left: Double
        let right: Double
        let inset: Double

        /// The x of `tick` (a bar line's x).
        func x(_ tick: Int) -> Double {
            let span = Double(max(1, ticks.count))
            return left + Double(tick - ticks.lowerBound) / span * (right - left)
        }

        /// Where a glyph or chord name at `tick` starts.
        func onset(_ tick: Int) -> Double {
            x(tick) + inset
        }
    }

    /// The vertical rows: chord names, accents, the staff's lines, staccato marks, the ruler.
    struct Staff {
        let strings: Int
        let frame: Frame
        let metrics: Metrics

        var top: Double {
            metrics.chordRow + metrics.markRow + metrics.glyphHeight / 2
        }

        /// The y of a string's line, the highest string on top.
        func y(_ string: Int) -> Double {
            top + Double(strings - 1 - string) * metrics.lineGap
        }

        /// Where a "?" sits: mid-staff.
        var centre: Double {
            (top + y(0)) / 2
        }

        /// The string whose line a "?" shares (the middle one of an odd count), else -1.
        var centreString: Int {
            strings % 2 == 1 ? (strings - 1) / 2 : -1
        }

        var chordY: Double {
            metrics.chordRow / 2
        }

        var accentY: Double {
            metrics.chordRow + metrics.markRow / 2
        }

        var staccatoY: Double {
            y(0) + metrics.glyphHeight / 2 + metrics.markRow / 2
        }

        /// The top of the ruler row.
        var ruler: Double {
            y(0) + metrics.glyphHeight / 2 + metrics.markRow
        }
    }

    /// Each note's glyph at its onset, nudged right past the glyph before it on the same line.
    static func placeGlyphs(
        _ notes: [TabNote],
        texts: [String],
        staff: Staff,
        measure: (String) -> Double,
    ) -> [Glyph] {
        var lastEnd: [Int: Double] = [:] // keyed by the string whose line it shares
        var glyphs: [Glyph] = []
        for (note, text) in zip(notes, texts) {
            let key = note.position?.string ?? staff.centreString
            var x = staff.frame.onset(note.tick)
            if let end = lastEnd[key] {
                x = max(x, end + staff.metrics.glyphGap)
            }
            let width = measure(text)
            lastEnd[key] = x + width
            glyphs.append(Glyph(
                text: text,
                x: x,
                width: width,
                y: note.position.map { staff.y($0.string) } ?? staff.centre,
                string: note.position?.string,
                tick: note.tick,
                isLanding: note.isLanding,
            ))
        }
        return glyphs
    }

    /// The stretches of a line at `y` from the first tick to `end`, broken behind every glyph
    /// that covers it.
    static func segments(
        to end: Double,
        y: Double,
        glyphs: [Glyph],
        staff: Staff,
    ) -> [Range<Double>] {
        let metrics = staff.metrics
        let start = staff.frame.left
        let gaps = glyphs
            .filter { abs($0.y - y) < metrics.glyphHeight / 2 }
            .map { ($0.x - metrics.linePad, $0.maxX + metrics.linePad) }
            .sorted { $0.0 < $1.0 }
        var result: [Range<Double>] = []
        var cursor = start
        for (gapStart, gapEnd) in gaps {
            if gapStart > cursor {
                result.append(cursor ..< min(gapStart, end))
            }
            cursor = max(cursor, gapEnd)
        }
        if cursor < end {
            result.append(cursor ..< end)
        }
        return result
    }

    static func marks(
        _ notes: [TabNote],
        glyphs: [Glyph],
        staff: Staff,
        measure: (String) -> Double,
    ) -> [Label] {
        var marks: [Label] = []
        for (note, glyph) in zip(notes, glyphs) {
            let centre = glyph.x + glyph.width / 2
            for (articulation, text, y) in [
                (Articulation.accent, ">", staff.accentY),
                (.staccato, ".", staff.staccatoY),
            ] where note.articulations.contains(articulation) {
                let width = measure(text)
                marks.append(Label(text: text, x: centre - width / 2, width: width, y: y))
            }
        }
        return marks
    }

    /// Chord names at their onsets in `ticks`, each nudged right past the one before.
    static func placeChords(
        _ chords: [(tick: Int, name: String)],
        staff: Staff,
        measure: (String) -> Double,
    ) -> [Label] {
        let shown = chords.filter { staff.frame.ticks.contains($0.tick) }
            .sorted { $0.tick < $1.tick }
        var labels: [Label] = []
        for chord in shown {
            var x = staff.frame.onset(chord.tick)
            if let previous = labels.last {
                x = max(x, previous.x + previous.width + staff.metrics.glyphGap)
            }
            labels.append(Label(
                text: chord.name,
                x: x,
                width: measure(chord.name),
                y: staff.chordY,
            ))
        }
        return labels
    }

    // MARK: Spoken

    static func spokenArticulations(_ note: TabNote) -> [String] {
        let order: [(Articulation, String)] = [
            (.accent, "accented"), (.staccato, "staccato"), (.slide, "slide"),
            (.hammer, "hammer-on"), (.pull, "pull-off"), (.ghost, "ghost"),
        ]
        return order.filter { note.articulations.contains($0.0) }.map(\.1)
    }

    /// "F sharp" for "F#", "B flat" for "Bb".
    static func spokenName(_ name: String) -> String {
        guard name.count > 1 else { return name }
        let letter = String(name.prefix(1))
        return switch name.dropFirst() {
        case "#": letter + " sharp"
        case "b": letter + " flat"
        default: name
        }
    }
}
