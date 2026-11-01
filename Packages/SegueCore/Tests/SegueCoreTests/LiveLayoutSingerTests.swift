import ChordPro
import Editing
import Foundation
import Library
import LiveLayout
import Testing

/// Singer view on stage (P9-2 section 6): the same passes, chips, badges and tags as the
/// chart, no chord anywhere, a Chords only pass as First line, larger lyrics, no notes.
struct LiveLayoutSingerTests {
    typealias Support = LiveLayoutSupport

    private let metrics = FixedAdvanceMetrics(factor: 0.45)

    /// An instrumental intro, chords inside romanized Hindi words, a tab riff.
    static let song = """
    {title: Kitaabon}
    {key: Am}
    {tempo: 84}

    {start_of_verse: Intro}
    [Am]  [G]  [F]  [E]
    {end_of_verse}

    {start_of_verse: Verse 1}
    Tu[G]jh mein [D]rab dikh[Em]ta hai
    [Am]Purani si gali mein [G]kitaabon ki du[F]kaan,
    {end_of_verse}

    {start_of_chorus}
    {comment: All together}
    Ke[A]sari[E]ya te[F#m]ra
    [F]Har ek kahaani [G]mein teri [E]yaad chhupi,
    [F]Lafzon ke [G]mele mein [C]main kho [Am]jaaun,
    {end_of_chorus}

    {start_of_tab: Riff}
    e|--3--|
    {end_of_tab}

    {chorus}
    """

    private static var model: RenderModel {
        Support.model(source: song)
    }

    /// Intro, Verse 1, Chorus, Chorus (Chords only), Riff, Chorus (First line); one Skip.
    private static var passes: [PlayedPass] {
        let units = SongSections.units(of: model.sections)
        return [
            PlayedPass(index: units[0].index, position: 0),
            PlayedPass(index: units[1].index, position: 1),
            PlayedPass(index: units[2].index, position: 2),
            PlayedPass(index: units[2].index, mode: .chordsOnly, position: 3),
            PlayedPass(index: units[3].index, position: 5),
            PlayedPass(index: units[2].index, mode: .firstLine, position: 6),
        ]
    }

    private func plan(
        view: StageView,
        passes: [PlayedPass]? = Self.passes,
        viewport: LayoutSize = Support.macBook13,
        notes: [String] = [],
        cues: [SongCue] = [],
        walkUps: Bool = false,
        minimum: Double = 22,
    ) -> (LayoutPlan, LayoutRequest) {
        var model = Self.model
        var context: BassLineContext?
        if walkUps {
            var options = DisplayOptions()
            options.bass = BassView(notes: true, walkUps: .everyChange)
            let document = ChordProParser.parse(Self.song).0
            model = RenderModel(document: document, options: options)
            context = BassLine.context(
                for: model,
                document: document,
                prefs: BassPrefs(),
                order: passes,
            )
        }
        let request = LayoutRequest(
            model: model,
            viewport: viewport,
            minLyricSize: view == .singer
                ? max(minimum, LayoutStyle.singerMinimumLyricSize) : minimum,
            cues: cues,
            notes: notes,
            passes: passes,
            style: view == .singer ? .singer : .stage,
            walkUps: context,
            view: view,
        )
        return (LayoutEngine.plan(request, metrics: metrics), request)
    }

    private static func texts(_ plan: LayoutPlan) -> [PlacedText] {
        plan.blocks.flatMap(\.allRows).flatMap { $0.chords + $0.text }
    }

    private static let chordRoles: Set<TextRole> = [
        .chord, .chordDetail, .chordSeparator, .approach,
    ]

    @Test
    func `a singer plan has no chord, chord row or tab anywhere`() {
        let (chart, _) = plan(view: .chart)
        #expect(Self.texts(chart).contains { Self.chordRoles.contains($0.role) })
        let (singer, request) = plan(view: .singer)
        #expect(!Self.texts(singer).contains { Self.chordRoles.contains($0.role) })
        let kinds = Set(singer.blocks.flatMap(\.allRows).map(\.kind))
        #expect(!kinds.contains(.chordRow))
        #expect(!kinds.contains(.verbatim))
        #expect(!kinds.contains(.fillTab))
        #expect(LayoutAudit.violations(of: singer, request: request, metrics: metrics).isEmpty)
    }

    @Test
    func `the passes, names, badges and tags match the chart`() {
        for passes in [Self.passes, nil] {
            let (chart, _) = plan(view: .chart, passes: passes)
            let (singer, _) = plan(view: .singer, passes: passes)
            #expect(singer.passes.map(\.index) == chart.passes.map(\.index))
            #expect(singer.passes.map(\.position) == chart.passes.map(\.position))
            #expect(singer.passes.map(\.source) == chart.passes.map(\.source))
            #expect(singer.passes.map(\.name) == chart.passes.map(\.name))
            #expect(singer.passes.map(\.mode) == chart.passes.map(\.mode))
            let gutter: (LayoutPlan) -> [[String]] = { plan in
                plan.blocks.filter { $0.part == 0 }.map { $0.labelLines.map(\.text.text) }
            }
            #expect(gutter(singer) == gutter(chart))
        }
    }

    @Test
    func `a chords only pass reads as its first line and keeps the CHORDS tag`() throws {
        let (singer, _) = plan(view: .singer)
        let block = try #require(singer.blocks.first { $0.pass == 3 && $0.part == 0 })
        #expect(block.labelLines.map(\.text.text).contains("CHORDS"))
        #expect(block.allRows.map(\.kind) == [.comment, .lyric, .moreLines])
        #expect(block.allRows.map { $0.text.map(\.text).joined() } == [
            "All together", "Kesariya tera", "+ 2 more lines (first line only)",
        ])
    }

    @Test
    func `an instrumental part shows its name and Instrumental, with no count`() throws {
        let (singer, _) = plan(view: .singer, passes: [
            PlayedPass(index: 0, position: 0),
            PlayedPass(index: 0, mode: .firstLine, position: 1),
        ])
        for pass in [0, 1] {
            let block = try #require(singer.blocks.first { $0.pass == pass && $0.part == 0 })
            #expect(block.label == "Intro")
            #expect(block.allRows.map(\.kind) == [.comment])
            #expect(block.allRows.first?.text.map(\.text).joined() == SingerView.instrumentalText)
        }
    }

    @Test
    func `a word a chord split reads whole`() {
        let (singer, _) = plan(view: .singer)
        let lines = singer.blocks.flatMap(\.allRows).filter { $0.kind == .lyric }
            .map { $0.text.map(\.text).joined(separator: " ") }
        #expect(lines.contains("Tujh mein rab dikhta hai"))
    }

    @Test(arguments: LiveLayoutSupport.stages.map(\.size))
    func `singer lyrics are at least the chart's and never below 28 or above 60`(
        viewport: LayoutSize,
    ) throws {
        for name in ["hindi-pyaar-ki-raah.cho", "basic-verse-chorus.cho", "live-very-long.cho"] {
            let model = try Support.model(name)
            let chart = LayoutEngine.plan(
                LayoutRequest(model: model, viewport: viewport, minLyricSize: 22),
                metrics: metrics,
            )
            let singer = LayoutEngine.plan(LayoutRequest(
                model: model,
                viewport: viewport,
                minLyricSize: LayoutStyle.singerMinimumLyricSize,
                style: .singer,
                view: .singer,
            ), metrics: metrics)
            #expect(singer.lyricSize >= chart.lyricSize, "\(name)")
            #expect(singer.lyricSize >= 28)
            #expect(singer.lyricSize <= 60)
        }
        #expect(LayoutStyle.singer.maxLyricSize == 60)
    }

    @Test
    func `cues show, notes and walk-ups do not`() throws {
        let cue = SongCue(section: "Chorus", text: "Watch me")
        let (singer, _) = plan(
            view: .singer,
            notes: ["Capo up for the bridge", "Bring the shaker"],
            cues: [cue],
            walkUps: true,
        )
        let notes = singer.blocks.contains { block in
            if case .notes = block.content {
                return true
            }
            return false
        }
        #expect(!notes)
        let chorus = try #require(singer.blocks.first { $0.pass == 2 && $0.part == 0 })
        #expect(chorus.cues.map(\.text) == ["Watch me"])
        #expect(!Self.texts(singer).contains { $0.walkUp != nil || $0.fill != nil })
        #expect(!Self.texts(singer).contains { Self.chordRoles.contains($0.role) })
    }

    @Test
    func `the line count is the same in both views`() throws {
        for passes in [Self.passes, nil] {
            let (chart, _) = plan(view: .chart, passes: passes)
            let (singer, _) = plan(view: .singer, passes: passes)
            #expect(singer.lineCount == chart.lineCount)
        }
        let model = try Support.model("live-forty-lines.cho")
        let chart = LayoutEngine.plan(
            LayoutRequest(model: model, viewport: Support.macBook13, minLyricSize: 22),
            metrics: metrics,
        )
        let singer = LayoutEngine.plan(LayoutRequest(
            model: model,
            viewport: Support.macBook13,
            minLyricSize: 28,
            style: .singer,
            view: .singer,
        ), metrics: metrics)
        #expect(singer.lineCount == chart.lineCount)
    }

    @Test
    func `the singer style changes nothing for the stage`() {
        #expect(LayoutStyle.stage.wrapPenalty == nil)
        #expect(LayoutStyle.stage == LayoutStyle())
    }
}
