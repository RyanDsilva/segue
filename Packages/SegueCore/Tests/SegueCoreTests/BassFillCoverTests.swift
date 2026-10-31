import ChordPro
import Editing
import Library
import MusicTheory
import Testing

/// A fill wins over a walk-up pick on the changes it covers, and the pick is kept (P8-7
/// section 9.3, R167 Q8).
struct BassFillCoverTests {
    static let fillSong = """
    {key: G}
    {start_of_verse}
    [G]Hello [C]there [D]friend
    {end_of_verse}
    {start_of_chorus}
    [G]Sing [C]it [Em]loud [D]now
    {end_of_chorus}

    """

    struct Covered {
        var model: RenderModel
        var document: SongDocument
        var prefs: BassPrefs
        var part: Part
    }

    /// The chorus's C (chord 1) into Em, as a pick and as a fill on `passes`.
    static func coveredSong(passes: PassFilter) throws -> Covered {
        let (model, document) = BassLineTests.model(Self.fillSong)
        let units = SongSections.units(of: document)
        let from = try #require(ChordAnchors.anchor(
            at: ChordPosition(section: 1, chord: 1),
            units: units,
            sections: model.sections,
        ))
        let to = try #require(ChordAnchors.anchor(
            at: ChordPosition(section: 1, chord: 2),
            units: units,
            sections: model.sections,
        ))
        let prefs = BassPrefs(walkUps: [WalkUpPick(
            anchor: from,
            to: "E",
            kind: .chromBelow,
            offsets: [-1],
        )])
        let part = Part(
            span: SpanAnchor(start: from, end: to, spanBass: ["C", "E"]),
            passes: passes,
            events: [PartEvent(chord: 0, at: 1440, len: 480, deg: 2)],
        )
        return Covered(model: model, document: document, prefs: prefs, part: part)
    }

    @Test
    func `a fill wins over the pick on its changes and the pick is kept`() throws {
        let song = try Self.coveredSong(passes: .all)
        let (model, document, prefs, part) = (song.model, song.document, song.prefs, song.part)
        func change(_ parts: [Part]) throws -> ChordChange {
            let changes = BassLine.changes(model, document: document, prefs: prefs, parts: parts)
            return try #require(changes.first { $0.fromName == "C" && $0.toName == "Em" })
        }
        let covered = try change([part])
        #expect(covered.coveredBy == part.id)
        #expect(covered.shown == nil)
        #expect(covered.pick != nil)
        #expect(covered.pickCandidate?.notes.map(\.chartName) == ["D#"])
        // Other changes keep their walk-ups; with the fill deleted the pick shows again.
        let others = BassLine.changes(model, document: document, prefs: prefs, parts: [part])
        #expect(others.filter { $0.coveredBy != nil }.count == 1)
        let uncovered = try change([])
        #expect(uncovered.coveredBy == nil)
        #expect(uncovered.shown?.notes.map(\.chartName) == ["D#"])
        let runs = BassLineTests.runs(BassLine.annotated(
            model,
            document: document,
            prefs: prefs,
            parts: [part],
        ))
        #expect(!runs.contains { $0.hasPrefix("C: ") && $0.contains("D#") }, "\(runs)")
    }

    @Test
    func `the pick applies again on a play the fill skips`() throws {
        let song = try Self.coveredSong(passes: .only([2]))
        let (model, document, prefs, part) = (song.model, song.document, song.prefs, song.part)
        let context = try #require(BassLine.context(
            for: model,
            document: document,
            prefs: prefs,
            parts: [part],
        ))
        // Verse, chorus, chorus: the fill plays only on the second chorus.
        let played = [model.sections[0], model.sections[1], model.sections[1]]
        let changes = BassLine.changes(played, origins: [0, 1, 1], context: context)
            .filter { $0.fromName == "C" && $0.toName == "Em" }
        #expect(changes.count == 2)
        #expect(changes.map(\.coveredBy) == [nil, part.id])
        #expect(changes.map { $0.shown?.notes.map(\.chartName) } == [["D#"], nil])
    }
}
