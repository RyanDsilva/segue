// P8-4b (docs/phases/8-workstreams/P8-4-bass.md sections 7.2, 8.8). What the render model
// carries for a bassist: a walk-up run after a departing chord, and fretboard cells for the
// editor's diagram strip.

import ChordPro
import Diagrams
import MusicTheory

/// One chord change: the departing chord's position in the written song and the target's
/// written bass (a section-final chord can lead to different targets in an arrangement).
public struct ChangeID: Sendable, Hashable, CustomStringConvertible {
    public var from: ChordPosition
    /// The target's bass as written (slash bass, else root), as a pitch class.
    public var toBass: PitchClass

    public init(from: ChordPosition, toBass: PitchClass) {
        self.from = from
        self.toBass = toBass
    }

    public var description: String {
        "\(from)>\(toBass.rawValue)"
    }
}

/// The small run of approach notes drawn after a departing chord (section 8.8).
public struct ApproachRun: Sendable, Hashable {
    /// Opens the popover (editor, library).
    public var change: ChangeID
    /// "A", "B" (or degrees "2", "3" with the song's Nashville toggle on).
    public var notes: [String]
    /// Per note: drawn with a trailing small "°" (outside the passing scale, R162 Q3).
    public var chromatic: [Bool]
    /// The user's saved pick (drawn as "yours").
    public var isPick: Bool
    /// "walk up A, B into C".
    public var accessibility: String
    /// The notes at concert pitch, played order (the stage neck's numbered path, R166).
    public var pitches: [PitchClass]
    /// Up or down from the departing chord; nil for a fifth or an octave pickup.
    public var ascending: Bool?

    public init(
        change: ChangeID,
        notes: [String],
        chromatic: [Bool],
        isPick: Bool,
        accessibility: String,
        pitches: [PitchClass] = [],
        ascending: Bool? = nil,
    ) {
        self.change = change
        self.notes = notes
        self.chromatic = chromatic
        self.isPick = isPick
        self.accessibility = accessibility
        self.pitches = pitches
        self.ascending = ascending
    }

    /// The run as drawn: "A B ›", chromatic notes with a trailing "°" ("A B C#° ›").
    public var text: String {
        zip(notes, chromatic).map { $0 + ($1 ? "\u{00B0}" : "") }.joined(separator: " ")
            + " \u{203A}"
    }
}

/// The notes of a saved fill sounding over one chord of its span, drawn after the chord unit
/// like a walk-up run (P8-7 section 14.1). Set by `BassLine.annotate` on every chord of the
/// span but the landing, in each pass the fill applies to.
public struct FillRun: Sendable, Hashable {
    /// The fill's `PartID`, as its string (Editing cannot see Library's type).
    public var part: String
    /// "E", "F#" (or degrees "5", "6" with the song's Nashville toggle on), in played order.
    public var notes: [String]
    /// Per note: outside the chord's passing scale (drawn with a trailing small "°").
    public var chromatic: [Bool]
    /// The span's last departing chord: its run ends in "›" into the landing.
    public var isLast: Bool
    /// "fill: E, F sharp, G sharp into A".
    public var accessibility: String
    /// The notes at concert pitch, played order (the stage neck's numbered path).
    public var pitches: [PitchClass]
    /// Per note: the pinned position when the note has a string pin, else nil (the neck
    /// walks it from the chord's suggested position).
    public var pins: [FretPosition?]
    /// The 1-based number of this run's first note in the whole fill (the neck numbers the
    /// fill across its chords: "3, 4, 5" over the second chord).
    public var firstNumber: Int
    /// The fill's notes over every departing chord.
    public var total: Int
    /// The fill shows as a mini tab (its `.fillTab` block): this run is not drawn, it only
    /// tells the stage neck the chord's notes (P8-7 14.4).
    public var inTab: Bool

    public init(
        part: String,
        notes: [String],
        chromatic: [Bool],
        isLast: Bool,
        accessibility: String,
        pitches: [PitchClass] = [],
        pins: [FretPosition?] = [],
        firstNumber: Int = 1,
        total: Int = 0,
        inTab: Bool = false,
    ) {
        self.part = part
        self.notes = notes
        self.chromatic = chromatic
        self.isLast = isLast
        self.accessibility = accessibility
        self.pitches = pitches
        self.pins = pins
        self.firstNumber = firstNumber
        self.total = total
        self.inTab = inTab
    }

    /// The run when it is drawn as names (nil when the fill shows as a tab).
    public var drawn: Self? {
        inTab ? nil : self
    }

    /// The run as drawn: "E F# G#" and, on the last departing chord, " ›"; chromatic notes
    /// with a trailing "°".
    public var text: String {
        zip(notes, chromatic).map { $0 + ($1 ? "\u{00B0}" : "") }.joined(separator: " ")
            + (isLast ? " \u{203A}" : "")
    }
}

/// A chord name over a fill's mini tab, at its onset tick.
public struct FillTabChord: Sendable, Hashable {
    public var tick: Int
    public var name: String

    public init(tick: Int, name: String) {
        self.tick = tick
        self.name = name
    }
}

/// A saved fill drawn as a mini tab under the lyric line holding its first chord (P8-7
/// section 14.2): the `TabLayout` input, laid out at whatever width draws it.
public struct FillTabBlock: Sendable, Hashable {
    /// The fill's `PartID`, as its string.
    public var part: String
    public var notes: [TabNote]
    public var chords: [FillTabChord]
    public var ticks: Range<Int>
    public var pulses: [Int]
    public var bars: [Int]
    public var tuning: Tuning
    /// "Tab: A string 7, 9, D string 7, then A".
    public var accessibility: String

    public init(
        part: String,
        notes: [TabNote],
        chords: [FillTabChord],
        ticks: Range<Int>,
        pulses: [Int],
        bars: [Int],
        tuning: Tuning,
        accessibility: String,
    ) {
        self.part = part
        self.notes = notes
        self.chords = chords
        self.ticks = ticks
        self.pulses = pulses
        self.bars = bars
        self.tuning = tuning
        self.accessibility = accessibility
    }

    /// The tab laid out at `width` with `measure` (the face the caller draws in).
    public func layout(
        width: Double,
        metrics: TabLayout.Metrics = TabLayout.Metrics(),
        measure: (String) -> Double,
    ) -> TabLayout {
        TabLayout.layout(
            notes: notes,
            chords: chords.map { (tick: $0.tick, name: $0.name) },
            ticks: ticks,
            pulses: pulses,
            bars: bars,
            tuning: tuning,
            width: width,
            metrics: metrics,
            measure: measure,
        )
    }
}

/// A bass fretboard cell of the editor's diagram strip (section 7.2).
public struct BassDiagram: Sendable, Equatable {
    /// The bass note at concert pitch ("B").
    public var note: String
    /// The concert chord ("G/B").
    public var chordName: String
    /// Every position of the note on frets 0 ... 12.
    public var positions: [FretPosition]
    /// The one suggested position (filled).
    public var suggested: FretPosition?
    /// Every chord tone on frets 0 ... 12 with its degree (R166): the note to play, the root
    /// of a slash chord, the third, fifth, seventh and any extension.
    public var tones: [NeckTone]
    /// The tuning drawn (the profile's).
    public var tuning: Tuning

    public init(
        note: String,
        chordName: String,
        positions: [FretPosition],
        suggested: FretPosition?,
        tones: [NeckTone],
        tuning: Tuning,
    ) {
        self.note = note
        self.chordName = chordName
        self.positions = positions
        self.suggested = suggested
        self.tones = tones
        self.tuning = tuning
    }

    /// One cell per unique concert chord of `document`, in order of first appearance. The
    /// hand position is one `home` per song from the sounding key (no key: the first bass
    /// note).
    static func cells(
        document: SongDocument,
        transform: DisplayTransform,
        tuning: Tuning,
    ) -> [RenderDiagram] {
        var seen = Set<String>()
        var concerts: [ChartChord] = []
        for token in document.chordTokens {
            guard let concert = transform.concert(token).chord,
                  seen.insert(concert.original).inserted
            else { continue }
            concerts.append(concert)
        }
        guard let first = concerts.first else { return [] }
        let tonic = transform.concertKey?.tonic.pitchClass
            ?? (first.symbol.bass ?? first.symbol.root).pitchClass
        let home = BassFretboard.homeFret(tonic: tonic, tuning: tuning)
        return concerts.map { chord in
            let symbol = chord.symbol
            let note = symbol.bass ?? symbol.root
            let suggested = BassFretboard.suggested(note.pitchClass, home: home, tuning: tuning)
            var diagram = RenderDiagram(
                name: chord.original,
                concertName: chord.original,
                guitar: nil,
                piano: nil,
                capoFret: nil,
            )
            diagram.bass = Self(
                note: note.chartName,
                chordName: chord.original,
                positions: BassFretboard.positions(of: note.pitchClass, tuning: tuning),
                suggested: suggested,
                tones: BassFretboard.tones(
                    of: symbol,
                    frets: 0 ... BassFretboard.maxFret,
                    tuning: tuning,
                ),
                tuning: tuning,
            )
            return diagram
        }
    }
}
