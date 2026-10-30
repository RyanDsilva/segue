import ChordPro
import Editing
import Library
import LiveLayout
import MusicTheory
import Testing

/// Walk-ups on stage (P8-4 sections 8.6, 8.8, 11.2): the run placed as part of the chord
/// unit, the plan audited clean, and each played pass walking into what follows it.
struct StageWalkUpLayoutTests {
    private let metrics = FixedAdvanceMetrics()

    static let song = """
    {key: G}
    {start_of_verse}
    [G]Hello there [C]my friend [D]and so
    {end_of_verse}
    {start_of_chorus}
    [A]Sing it [Em]loud
    {end_of_chorus}

    """

    private func plan(_ passes: [PlayedPass]? = nil) -> (LayoutPlan, LayoutRequest) {
        let (document, _) = ChordProParser.parse(Self.song)
        let options = DisplayOptions()
            .withBass(InstrumentProfile(bassNotes: true, walkUps: .everyChange))
        let model = RenderModel(document: document, options: options)
        let request = LayoutRequest(
            model: model,
            viewport: LayoutSize(width: 900, height: 600),
            minLyricSize: 30,
            columns: 1,
            passes: passes,
            walkUps: BassLine.context(for: model, document: document, prefs: BassPrefs()),
        )
        return (LayoutEngine.plan(request, metrics: metrics), request)
    }

    private func runs(_ plan: LayoutPlan) -> [String] {
        plan.blocks.flatMap(\.allRows).flatMap(\.chords).filter { $0.role == .approach }
            .map(\.text)
    }

    @Test
    func `runs are placed after their chord unit and the plan audits clean`() throws {
        let (plan, request) = plan()
        #expect(runs(plan) == [
            "A B \u{203A}",
            "C#\u{00B0} \u{203A}",
            "F# G \u{203A}",
            "G F# \u{203A}",
        ])
        #expect(LayoutAudit.violations(of: plan, request: request, metrics: metrics).isEmpty)
        let row = try #require(plan.blocks.first?.allRows.first)
        let first = try #require(row.chords.first)
        let run = try #require(row.chords.first { $0.role == .approach })
        #expect(abs(run.x - (first.x + first.width + ChordUnit.detailGap * plan.chordSize)) < 1e-9)
        #expect(abs(run.size - plan.chordSize * ChordUnit.detailScale) < 1e-9)
        let next = try #require(row.chords.first { $0.text == "C" })
        #expect(next.x >= run.x + run.width)
    }

    @Test
    func `each pass walks into the pass that follows it`() {
        // Chorus, verse, chorus: the chorus's Em leads into the verse's G, the verse's D
        // into the chorus's A, and the last chord leads nowhere.
        let (plan, request) = plan([
            PlayedPass(index: 1, position: 0),
            PlayedPass(index: 0, position: 1),
            PlayedPass(index: 1, position: 2),
        ])
        let expected = ["G F#", "F#", "A B", "C#\u{00B0}", "F# G", "G F#"]
        #expect(runs(plan) == expected.map { $0 + " \u{203A}" })
        #expect(LayoutAudit.violations(of: plan, request: request, metrics: metrics).isEmpty)
    }

    @Test
    func `without walk-ups the plan has no runs`() {
        let (document, _) = ChordProParser.parse(Self.song)
        let model = RenderModel(
            document: document,
            options: DisplayOptions().withBass(InstrumentProfile(bassNotes: true)),
        )
        let request = LayoutRequest(
            model: model,
            viewport: LayoutSize(width: 900, height: 600),
            minLyricSize: 30,
            columns: 1,
        )
        #expect(runs(LayoutEngine.plan(request, metrics: metrics)).isEmpty)
    }
}
