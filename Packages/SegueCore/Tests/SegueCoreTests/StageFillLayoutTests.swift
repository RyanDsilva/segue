import ChordPro
import Diagrams
import Editing
import Library
import LiveLayout
import MusicTheory
import Testing

/// Saved fills on charts and on stage (P8-7 section 14, R167 Q12, R168 Q5, Q7, Q8): note names
/// after the span's chord units by default, a mini tab block under the first chord's line per
/// fill or for every fill with "Fills as tab", only in the passes a fill applies to, never
/// beside a walk-up on a change it covers, and the same runs and blocks in a written-order
/// render model (the bass chart PDF's seam).
struct StageFillLayoutTests {
    private let metrics = FixedAdvanceMetrics()

    static let song = """
    {key: G}
    {start_of_verse}
    [G]Hello there [C]my friend [D]and so
    {end_of_verse}
    {start_of_chorus}
    [C]Sing it [D]loud and [G]clear
    {end_of_chorus}

    """

    /// A song, its parts and how to lay it out.
    struct Song {
        var document: SongDocument
        var model: RenderModel
        var parts: [Part]
    }

    /// A span of written chords as a part with `events`.
    static func part(
        _ positions: [ChordPosition],
        bass: [String],
        events: [PartEvent],
        show: PartShow = .names,
        passes: PassFilter = .all,
        model: RenderModel,
        document: SongDocument,
    ) throws -> Part {
        let units = SongSections.units(of: document)
        let first = try #require(positions.first)
        let last = try #require(positions.last)
        let start = try #require(ChordAnchors.anchor(
            at: first,
            units: units,
            sections: model.sections,
        ))
        let end = try #require(ChordAnchors.anchor(
            at: last,
            units: units,
            sections: model.sections,
        ))
        return Part(
            span: SpanAnchor(start: start, end: end, spanBass: bass),
            passes: passes,
            show: show,
            events: events,
        )
    }

    /// The verse's G -> C -> D (G A over G, D E over C) and the chorus's C -> D (D over C).
    static func song(
        chorusShow: PartShow = .names,
        chorusPasses: PassFilter = .all,
        fillsAsTab: Bool = false,
        density: WalkUpDensity = .everyChange,
        nashville: Bool = false,
        source: String = song,
    ) throws -> Song {
        let (document, _) = ChordProParser.parse(source)
        let options = DisplayOptions(nashville: nashville).withBass(InstrumentProfile(
            bassNotes: true,
            walkUps: density,
            fillsAsTab: fillsAsTab,
        ))
        let model = RenderModel(document: document, options: options)
        let verse = try part(
            [ChordPosition(section: 0, chord: 0), ChordPosition(section: 0, chord: 1),
             ChordPosition(section: 0, chord: 2)],
            bass: ["G", "C", "D"],
            events: [
                PartEvent(chord: 0, at: 960, len: 480, deg: 0),
                PartEvent(chord: 0, at: 1440, len: 480, deg: 2),
                PartEvent(chord: 1, at: 960, len: 480, deg: 2),
                PartEvent(chord: 1, at: 1440, len: 480, deg: 4),
                PartEvent(chord: 2, at: 0, len: 480, deg: 0),
            ],
            model: model,
            document: document,
        )
        let chorus = try part(
            [ChordPosition(section: 1, chord: 0), ChordPosition(section: 1, chord: 1)],
            bass: ["C", "D"],
            events: [PartEvent(chord: 0, at: 1440, len: 480, deg: 2)],
            show: chorusShow,
            passes: chorusPasses,
            model: model,
            document: document,
        )
        return Song(document: document, model: model, parts: [verse, chorus])
    }

    private func plan(
        _ song: Song,
        passes: [PlayedPass]? = nil,
    ) throws -> (LayoutPlan, LayoutRequest) {
        let units = SongSections.units(of: song.document)
        let context = try #require(BassLine.context(
            for: song.model,
            document: song.document,
            prefs: BassPrefs(),
            parts: song.parts,
            order: passes ?? ArrangementResolver.fullSong(units),
        ))
        let request = LayoutRequest(
            model: song.model,
            viewport: LayoutSize(width: 900, height: 600),
            minLyricSize: 30,
            columns: 1,
            passes: passes,
            walkUps: context,
        )
        return (LayoutEngine.plan(request, metrics: metrics), request)
    }

    /// The approach-style runs on stage: "F:" for a fill's notes, "W:" for a walk-up.
    private func runs(_ plan: LayoutPlan) -> [String] {
        plan.blocks.flatMap(\.allRows).flatMap(\.chords).filter { $0.role == .approach }
            .map { ($0.fill == nil ? "W: " : "F: ") + $0.text }
    }

    private func tabRows(_ plan: LayoutPlan) -> [LayoutRow] {
        plan.blocks.flatMap(\.allRows).filter { $0.kind == .fillTab }
    }

    @Test
    func `fills read as note names after their chord units and the plan audits clean`() throws {
        let (plan, request) = try plan(Self.song())
        #expect(runs(plan) == [
            "F: G A", "F: D E \u{203A}", "W: B \u{203A}", "F: D \u{203A}", "W: E F# \u{203A}",
        ])
        #expect(tabRows(plan).isEmpty)
        #expect(LayoutAudit.violations(of: plan, request: request, metrics: metrics).isEmpty)
        let row = try #require(plan.blocks.first?.allRows.first)
        let first = try #require(row.chords.first)
        let run = try #require(row.chords.first { $0.role == .approach })
        #expect(abs(run.x - (first.x + first.width + ChordUnit.detailGap * plan.chordSize)) < 1e-9)
        let next = try #require(row.chords.first { $0.text == "C" })
        #expect(next.x >= run.x + run.width)
        // The chord run carries the fill for the neck, and no walk-up beside it.
        #expect(first.fill?.notes == ["G", "A"])
        #expect(first.walkUp == nil)
        #expect(next.fill?.firstNumber == 3)
        #expect(next.fill?.total == 4)
    }

    @Test
    func `a tab fill is a measured block after the line holding its first chord`() throws {
        let (plan, request) = try plan(Self.song(chorusShow: .tab))
        #expect(runs(plan) == ["F: G A", "F: D E \u{203A}", "W: B \u{203A}", "W: E F# \u{203A}"])
        let chorus = try #require(plan.blocks.first { $0.source == 1 })
        let rows = chorus.allRows
        let tab = try #require(rows.firstIndex { $0.kind == .fillTab })
        #expect(tab > 0 && rows[tab - 1].kind == .lyric)
        let placed = try #require(rows[tab].fillTab)
        #expect(abs(placed.size - plan.chordSize * ChordUnit.detailScale) < 1e-9)
        #expect(placed.height > 0)
        #expect(rows[tab].height >= placed.height)
        // The D over C, then the landing root D in the landing bar.
        #expect(placed.block.notes.map(\.name) == ["D", "D"])
        #expect(placed.block.notes.map(\.isLanding) == [false, true])
        #expect(placed.block.chords.map(\.name) == ["C", "D"])
        #expect(placed.block.accessibility.hasPrefix("Tab: "))
        #expect(LayoutAudit.violations(of: plan, request: request, metrics: metrics).isEmpty)
    }

    @Test
    func `fills as tab draws every fill as a block`() throws {
        let (plan, request) = try plan(Self.song(fillsAsTab: true))
        #expect(runs(plan) == ["W: B \u{203A}", "W: E F# \u{203A}"])
        #expect(tabRows(plan).count == 2)
        #expect(LayoutAudit.violations(of: plan, request: request, metrics: metrics).isEmpty)
    }

    @Test
    func `fills draw only on the passes they apply to, Last time on the last chorus`() throws {
        let song = try Self.song(chorusPasses: .last)
        // Chorus, verse, chorus: the chorus fill plays on the last chorus only.
        let (plan, _) = try plan(song, passes: [
            PlayedPass(index: 1, position: 0),
            PlayedPass(index: 0, position: 1),
            PlayedPass(index: 1, position: 2),
        ])
        let byPass = plan.blocks.compactMap { block -> [String]? in
            guard block.pass != nil else { return nil }
            return block.allRows.flatMap(\.chords).filter { $0.role == .approach }
                .map { ($0.fill == nil ? "W: " : "F: ") + $0.text }
        }
        #expect(byPass == [
            ["W: C#\u{00B0} \u{203A}", "W: E F# \u{203A}"],
            ["F: G A", "F: D E \u{203A}", "W: B \u{203A}"],
            ["F: D \u{203A}", "W: E F# \u{203A}"],
        ])
    }

    @Test
    func `fills follow the walk-up density and show nothing while walk-ups are off`() throws {
        let song = try Self.song(density: .off)
        let annotated = BassLine.annotated(
            song.model,
            document: song.document,
            prefs: BassPrefs(),
            parts: song.parts,
        )
        #expect(Self.fillRuns(annotated).isEmpty)
        let sections = try Self.song(density: .sections)
        let shown = BassLine.annotated(
            sections.model,
            document: sections.document,
            prefs: BassPrefs(),
            parts: sections.parts,
        )
        #expect(Self.fillRuns(shown) == ["G: G A", "C: D E \u{203A}", "C: D \u{203A}"])
    }

    @Test
    func `fill notes read as Nashville numbers in the key`() throws {
        let song = try Self.song(nashville: true)
        let annotated = BassLine.annotated(
            song.model,
            document: song.document,
            prefs: BassPrefs(),
            parts: song.parts,
        )
        #expect(Self.fillRuns(annotated) == ["G: 1 2", "C: 5 6 \u{203A}", "C: 5 \u{203A}"])
    }

    @Test
    func `a fill starting in a grid draws its tab after the grid`() throws {
        let source = """
        {key: G}
        {start_of_grid: 1+4x2+4}
        | G . . . | C . . . |
        {end_of_grid}
        {start_of_verse}
        [D]Hello [G]there
        {end_of_verse}

        """
        let (document, _) = ChordProParser.parse(source)
        let options = DisplayOptions()
            .withBass(InstrumentProfile(bassNotes: true, walkUps: .everyChange))
        let model = RenderModel(document: document, options: options)
        let part = try Self.part(
            [ChordPosition(section: 0, chord: 0), ChordPosition(section: 0, chord: 1)],
            bass: ["G", "C"],
            events: [PartEvent(chord: 0, at: 1440, len: 480, deg: 4)],
            model: model,
            document: document,
        )
        let annotated = BassLine.annotated(
            model,
            document: document,
            prefs: BassPrefs(),
            parts: [part],
        )
        let items = try #require(annotated.sections.first?.items)
        let tab = try #require(items.firstIndex { item in
            if case .fillTab = item {
                return true
            }
            return false
        })
        #expect(tab > 0)
        guard case .verbatim = items[tab - 1] else {
            Issue.record("the tab follows the grid: \(items)")
            return
        }
        #expect(tab == items.count - 1)
    }

    /// The fill runs of a render model as "chord: run".
    static func fillRuns(_ model: RenderModel) -> [String] {
        model.sections.flatMap(\.items).flatMap { item -> [String] in
            guard case let .lyrics(line) = item else { return [] }
            return line.chords.compactMap { chord in
                chord.fill?.drawn.map { "\(chord.original): \($0.text)" }
            }
        }
    }
}
