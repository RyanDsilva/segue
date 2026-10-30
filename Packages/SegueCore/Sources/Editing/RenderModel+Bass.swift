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
public struct ApproachRun: Sendable, Equatable {
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

    public init(
        change: ChangeID,
        notes: [String],
        chromatic: [Bool],
        isPick: Bool,
        accessibility: String,
    ) {
        self.change = change
        self.notes = notes
        self.chromatic = chromatic
        self.isPick = isPick
        self.accessibility = accessibility
    }

    /// The run as drawn: "A B ›", chromatic notes with a trailing "°" ("A B C#° ›").
    public var text: String {
        zip(notes, chromatic).map { $0 + ($1 ? "\u{00B0}" : "") }.joined(separator: " ")
            + " \u{203A}"
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
    /// Fifth and octave positions around the suggested one (octave only for slash chords).
    public var shape: [FretPosition]
    /// The tuning drawn (the profile's).
    public var tuning: Tuning

    public init(
        note: String,
        chordName: String,
        positions: [FretPosition],
        suggested: FretPosition?,
        shape: [FretPosition],
        tuning: Tuning,
    ) {
        self.note = note
        self.chordName = chordName
        self.positions = positions
        self.suggested = suggested
        self.shape = shape
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
            let isSlash = symbol.bass.map { $0.pitchClass != symbol.root.pitchClass } ?? false
            let fifth = isSlash ? nil : BassFretboard.fifthInterval(of: symbol.formula)
            let shape = suggested.map { root in
                BassFretboard.shape(around: root, fifth: fifth, home: home, tuning: tuning)
            } ?? []
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
                shape: shape,
                tuning: tuning,
            )
            return diagram
        }
    }
}
