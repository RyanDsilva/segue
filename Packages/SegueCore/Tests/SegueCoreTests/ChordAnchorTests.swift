import ChordPro
import Editing
import Library
import MusicTheory
import Testing

/// Chord anchors over grid chords and the P8-7 correction fields (P8-7 sections 5.5, 5.6).
struct ChordAnchorTests {
    static let song = """
    {start_of_verse}
    [G]Hello [C]there
    {end_of_verse}
    {start_of_grid: Solo}
    | Am . . . | F . G . |
    {end_of_grid}
    {start_of_chorus}
    [C]Sing [G]it
    {end_of_chorus}

    """

    static func parts(_ source: String) -> SongTimelineTests.Song {
        SongTimelineTests.Song(source)
    }

    @Test
    func `a grid chord anchor saves and resolves`() throws {
        let song = Self.parts(Self.song)
        let model = song.model
        let units = song.units
        let anchor = try #require(ChordAnchors.anchor(
            at: ChordPosition(section: 1, chord: 2),
            units: units,
            sections: model.sections,
        ))
        #expect(anchor.from == "G")
        #expect(anchor.chord == 2)
        let override = ChordBeatsOverride(anchor: anchor, beats: 1, ticks: 600, push: .sixteenth)
        let resolved = ChordAnchors.resolve([override], units: units, sections: model.sections)
        #expect(resolved.unmatched.isEmpty)
        #expect(resolved.applied[ChordPosition(section: 1, chord: 2)] == override)
        // Edited elsewhere: still resolves; the grid's G changed to E: unmatched.
        let edited = Self.parts(Self.song.replacingOccurrences(of: "[C]Sing", with: "[D]Sing"))
        #expect(ChordAnchors.resolve(
            [override],
            units: edited.units,
            sections: edited.model.sections,
        ).unmatched.isEmpty)
        let changed = Self.parts(Self.song.replacingOccurrences(of: "G . |", with: "E . |"))
        #expect(ChordAnchors.resolve(
            [override],
            units: changed.units,
            sections: changed.model.sections,
        ).unmatched == [override])
    }

    @Test
    func `a ticks and push override round-trips and times its chord`() throws {
        let song = Self.parts(Self.song)
        let document = song.document
        let model = song.model
        let units = song.units
        let anchor = try #require(ChordAnchors.anchor(
            at: ChordPosition(section: 2, chord: 1),
            units: units,
            sections: model.sections,
        ))
        let override = ChordBeatsOverride(
            anchor: anchor,
            ticks: 600,
            meter: .common,
            push: .eighth,
        )
        let timeline = SongTimeline.build(
            document: document,
            sections: model.sections,
            units: units,
            timing: ChordTiming(chords: [override]),
            order: nil,
        )
        let chord = try #require(timeline.timed(pass: 2, chord: 1))
        #expect(chord.push == .eighth)
        #expect(chord.length == 600 + 240)
        #expect(chord.source == .user)
    }

    @Test
    func `a pick into the chorus is not taken by a grid in between`() throws {
        // The walk-up chain passes through a grid (P8-7 section 5.5), so a pick saved on the
        // verse's last chord still targets the chorus's first chord.
        let song = Self.parts(Self.song)
        let document = song.document
        let model = song.model
        let units = song.units
        let options = DisplayOptions()
            .withBass(InstrumentProfile(bassNotes: true, walkUps: .everyChange))
        let bassModel = RenderModel(document: document, options: options)
        let changes = BassLine.changes(bassModel, document: document, prefs: BassPrefs())
        let change = try #require(changes.first { $0.fromName == "C" && $0.toName == "C" })
        let anchor = try #require(ChordAnchors.anchor(
            at: change.id.from,
            units: units,
            sections: model.sections,
        ))
        let pick = WalkUpPick(anchor: anchor, to: change.toBass, kind: .chromBelow, offsets: [-1])
        #expect(ChordAnchors.resolve([pick], units: units, sections: model.sections).unmatched
            .isEmpty)
    }
}
