import ChordPro
import Editing
import Library
import MusicTheory
import Playback
import Testing

/// Play-along plays a saved fill instead of the pick on the plays it applies to (P8-7
/// section 13, R167 Q8: the fill wins, the pick is kept).
struct PlayAlongFillTests {
    static let song = """
    {key: G}
    {tempo: 60}
    {start_of_chorus}
    [G]Sing [C]it [Em]loud
    {end_of_chorus}
    {chorus}

    """

    @Test
    func `the fill replaces the pick on its play and the pick plays on the other`() throws {
        // swiftlint:disable:previous function_body_length
        let (document, _) = ChordProParser.parse(Self.song)
        let options = DisplayOptions()
            .withBass(InstrumentProfile(bassNotes: true, walkUps: .everyChange))
        let model = RenderModel(document: document, options: options)
        let units = SongSections.units(of: document)
        let from = try #require(ChordAnchors.anchor(
            at: ChordPosition(section: 0, chord: 1),
            units: units,
            sections: model.sections,
        ))
        let to = try #require(ChordAnchors.anchor(
            at: ChordPosition(section: 0, chord: 2),
            units: units,
            sections: model.sections,
        ))
        let prefs = BassPrefs(walkUps: [
            WalkUpPick(anchor: from, to: "E", kind: .chromBelow, offsets: [-1]),
        ])
        // On the second chorus only: D then E over C (deg 2, 4), landing on E.
        let part = Part(
            span: SpanAnchor(start: from, end: to, spanBass: ["C", "E"]),
            passes: .only([2]),
            events: [
                PartEvent(chord: 0, at: 960, len: 480, deg: 2),
                PartEvent(chord: 0, at: 1440, len: 480, deg: 4),
                PartEvent(chord: 1, at: 0, len: 480, deg: 0),
            ],
        )
        let timeline = SongTimeline.build(
            document: document,
            sections: model.sections,
            units: units,
            timing: prefs.timing,
            order: nil,
        )
        let resolved = PartAnchors.resolve(
            [part],
            timeline: timeline,
            units: units,
            sections: model.sections,
        )
        let placement = BassPlacement(tuning: .bassStandard4, home: 3)
        var playAlong = PlayAlongTimeline.make(
            timeline: timeline,
            range: .whole,
            changes: BassLine.changes(model, document: document, prefs: prefs, parts: [part]),
            transform: model.transform,
            placement: placement,
        )
        playAlong.fills = PlayAlongFill.fills(
            resolved,
            in: playAlong,
            song: timeline,
            transform: model.transform,
            placement: placement,
        )
        #expect(playAlong.fills.count == 1)
        let phrase = PhraseBuilder.playAlong(
            playAlong,
            voices: [.bass, .walkUps],
            sound: .piano,
            style: .block,
            countIn: false,
        )
        let bass = phrase.events.filter { $0.voice == .bass }
        // 60 BPM, one bar per chord: C sounds at 4 s and 16 s. The pick (D#, a half step
        // below E) walks on the first chorus's last beat of C; the second chorus plays the
        // fill's D (beat 3) and E (beat 4) and no D#.
        func notes(_ range: ClosedRange<Double>) -> [UInt8] {
            bass.filter { range.contains($0.onset) }.map(\.note).map { $0 % 12 }
        }
        #expect(notes(4 ... 7.9).contains(3))
        #expect(!notes(16 ... 19.9).contains(3))
        #expect(notes(18 ... 19.9) == [2, 4])
    }

    @Test
    func `"Last time" is the song's last play, even looping one chorus`() throws {
        // swiftlint:disable:previous function_body_length
        let (document, _) = ChordProParser.parse(Self.song)
        let model = RenderModel(document: document, options: DisplayOptions())
        let units = SongSections.units(of: document)
        let from = try #require(ChordAnchors.anchor(
            at: ChordPosition(section: 0, chord: 1),
            units: units,
            sections: model.sections,
        ))
        let to = try #require(ChordAnchors.anchor(
            at: ChordPosition(section: 0, chord: 2),
            units: units,
            sections: model.sections,
        ))
        let part = Part(
            span: SpanAnchor(start: from, end: to, spanBass: ["C", "E"]),
            passes: .last,
            events: [PartEvent(chord: 0, at: 1440, len: 480, deg: 4)],
        )
        let timeline = SongTimeline.build(
            document: document,
            sections: model.sections,
            units: units,
            timing: ChordTiming(),
            order: nil,
        )
        let resolved = PartAnchors.resolve(
            [part],
            timeline: timeline,
            units: units,
            sections: model.sections,
        )
        let placement = BassPlacement(tuning: .bassStandard4, home: 3)
        func fills(_ range: PlayAlongRange) -> Int {
            let playAlong = PlayAlongTimeline.make(
                timeline: timeline,
                range: range,
                changes: [],
                transform: model.transform,
                placement: placement,
            )
            return PlayAlongFill.fills(
                resolved,
                in: playAlong,
                song: timeline,
                transform: model.transform,
                placement: placement,
            ).count
        }
        #expect(fills(.whole) == 1)
        // Looping the first chorus alone: it is not the song's last chorus.
        #expect(fills(.section(0)) == 0)
        #expect(fills(.section(1)) == 1)
    }
}
