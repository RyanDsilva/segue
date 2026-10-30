import ChordPro
import Editing
import Foundation
import Library
import LiveLayout
import Testing

/// The expanded stage (R147, R149, P8-2 section 6): every repeat written out, one block per
/// shown pass, the show modes, `plan.passes` and the performed line count. Replaces the
/// collapsing tests.
struct LiveLayoutPassTests {
    typealias Support = LiveLayoutSupport

    private let metrics = FixedAdvanceMetrics()

    /// Verse, Chorus (written), Verse 2, `{chorus}`, Bridge, `{chorus}`.
    static let song = """
    {title: Harbour}

    {start_of_verse: Verse 1}
    [G]Paper boats on the [C]water
    [D]Drifting out to [G]sea
    {end_of_verse}

    {start_of_chorus}
    {comment: Big}
    [C]Harbour lights, [G]call me back
    [D]Home again to [G]me
    Words without chords

    [Em]After the break
    {end_of_chorus}

    {start_of_verse: Verse 2}
    [G]Second verse here
    {end_of_verse}

    {chorus}

    {start_of_tab: Riff}
    e|--3--|
    {end_of_tab}

    {chorus}
    """

    private func plan(
        _ source: String = song,
        passes: [PlayedPass]? = nil,
        viewport: LayoutSize = LiveLayoutSupport.macBook13,
        columns: Int? = nil,
    ) -> (LayoutPlan, LayoutRequest) {
        let request = LayoutRequest(
            model: Support.model(source: source),
            viewport: viewport,
            minLyricSize: 22,
            columns: columns,
            passes: passes,
        )
        return (LayoutEngine.plan(request, metrics: metrics), request)
    }

    private func text(_ block: LayoutBlock) -> [String] {
        block.allRows.map { $0.text.map(\.text).joined(separator: " ") }
    }

    // MARK: Full song

    @Test
    func `the full song writes out every repeat in full`() {
        let (plan, request) = plan()
        let firsts = plan.blocks.filter { $0.part == 0 }
        #expect(firsts.map(\.label) == [
            "Verse 1", "Chorus", "Verse 2", "Chorus", "Riff", "Chorus",
        ])
        // Each `{chorus}` takes its chorus's lines; ids are pass indices, `source` the part.
        #expect(text(firsts[3]) == text(firsts[1]))
        #expect(text(firsts[5]) == text(firsts[1]))
        #expect(firsts.map(\.id) == [0, 1, 2, 3, 4, 5])
        #expect(firsts.map(\.source) == [0, 1, 2, 3, 4, 5])
        #expect(firsts.map(\.pass) == [0, 1, 2, 3, 4, 5])
        #expect(!plan.blocks.flatMap(text).contains("Repeat chorus"))
        #expect(LayoutAudit.violations(of: plan, request: request, metrics: metrics).isEmpty)
    }

    @Test
    func `a chorus repeat with no chorus to write out is one comment row`() throws {
        let (plan, _) = plan("""
        {start_of_verse}
        [G]Only a verse
        {end_of_verse}
        {chorus}
        """)
        let repeatBlock = try #require(plan.block(id: 1))
        #expect(repeatBlock.allRows.map(\.kind) == [.comment])
        #expect(text(repeatBlock) == ["Repeat chorus"])
        #expect(repeatBlock.label == "Chorus")
    }

    // MARK: Arranged

    @Test
    func `arranged passes play in order with unique ids, cues on the first shown pass`() {
        let model = Support.model(source: Self.song)
        let units = SongSections.units(of: model.sections)
        let request = LayoutRequest(
            model: model,
            viewport: Support.macBook13,
            minLyricSize: 22,
            cues: [
                SongCue(section: "Chorus", occurrence: 3, text: "Last"),
                SongCue(section: "Riff", text: "Gone"),
            ],
            passes: [
                PlayedPass(index: units[5].index, position: 3),
                PlayedPass(index: units[0].index, position: 0),
                PlayedPass(index: units[5].index, position: 4),
            ],
        )
        let plan = LayoutEngine.plan(request, metrics: metrics)
        let firsts = plan.blocks.filter { $0.part == 0 }
        #expect(firsts.map(\.id) == [0, 1, 2])
        #expect(firsts.map(\.source) == [5, 0, 5])
        #expect(firsts.map { $0.cues.map(\.text) } == [["Last"], [], []])
        #expect(plan.passes.map(\.position) == [3, 0, 4])
        // Parts with no shown pass are not laid out.
        #expect(!firsts.contains { $0.source == 2 })
    }

    // MARK: Show modes

    @Test
    func `chords only shows each chorded line as a chord row`() throws {
        let model = Support.model(source: Self.song)
        let (plan, request) = plan(passes: [PlayedPass(index: 1, mode: .chordsOnly)])
        let block = try #require(plan.block(id: 0))
        // The comment stays; the chordless line is dropped and the breaks around it collapse.
        #expect(block.allRows.map(\.kind) == [
            .comment,
            .chordRow,
            .chordRow,
            .stanzaBreak,
            .chordRow,
        ])
        #expect(text(block) == ["Big", "| C | G |", "| D | G |", "", "| Em |"])
        let row = try #require(block.allRows.first { $0.kind == .chordRow })
        #expect(row.text.map(\.role) == [
            .chordSeparator, .chord, .chordSeparator, .chord, .chordSeparator,
        ])
        // Widths from the metrics: chord size 0.82 x lyric size, runs at least 1.6 em, 0.55 em
        // gaps around each bar.
        let size = plan.chordSize
        let bar = metrics.width(of: "|", role: .chordSeparator, size: size)
        let gap = 0.55 * size
        #expect(row.text[0].x == 0)
        #expect(abs(row.text[1].x - (bar + gap)) < 1e-9)
        #expect(abs(row.text[2].x - (bar + gap + 1.6 * size + gap)) < 1e-9)
        #expect(row.text.allSatisfy { $0.size == size })
        #expect(abs(row.height - 1.5 * size) < 1e-9)
        #expect(model.sections[1].items.count > block.allRows.count)
        #expect(LayoutAudit.violations(of: plan, request: request, metrics: metrics).isEmpty)
    }

    @Test
    func `chords only keeps tab lines`() throws {
        let (plan, _) = plan(passes: [PlayedPass(index: 4, mode: .chordsOnly)])
        let block = try #require(plan.block(id: 0))
        #expect(block.allRows.map(\.kind) == [.verbatim])
    }

    @Test
    func `first line only shows the comments before, the first line and a count`() throws {
        let (plan, request) = plan(passes: [
            PlayedPass(index: 1, mode: .firstLine),
            PlayedPass(index: 2, mode: .firstLine),
        ])
        let chorus = try #require(plan.block(id: 0))
        #expect(chorus.allRows.map(\.kind) == [.comment, .lyric, .moreLines])
        #expect(text(chorus) == [
            "Big", "Harbour lights, call me back", "+ 3 more lines (first line only)",
        ])
        let more = try #require(chorus.allRows.last?.text.first)
        #expect(more.role == .moreLines)
        #expect(abs(more.size - 0.6 * plan.lyricSize) < 1e-9)
        // One line only: no count.
        let verse = try #require(plan.block(id: 1))
        #expect(verse.allRows.map(\.kind) == [.lyric])

        let (single, _) = self.plan("""
        {start_of_verse}
        [G]One
        [C]Two
        {end_of_verse}
        """, passes: [PlayedPass(index: 0, mode: .firstLine)])
        #expect(try text(#require(single.block(id: 0))).last == "+ 1 more line (first line only)")
        #expect(LayoutAudit.violations(of: plan, request: request, metrics: metrics).isEmpty)
    }

    @Test
    func `the line count counts performed lines whatever the mode`() {
        let full = plan(passes: [PlayedPass(index: 1)]).0.lineCount
        #expect(full == 4)
        #expect(plan(passes: [PlayedPass(index: 1, mode: .chordsOnly)]).0.lineCount == 4)
        #expect(plan(passes: [PlayedPass(index: 1, mode: .firstLine)]).0.lineCount == 4)
        // The full song counts each written-out repeat.
        #expect(plan().0.lineCount == 2 + 4 + 1 + 4 + 4)
    }

    // MARK: Plan passes

    @Test
    func `plan passes carry name, mode, column and their extent`() {
        let (plan, _) = plan(passes: [
            PlayedPass(index: 0, position: 0),
            PlayedPass(index: 1, mode: .chordsOnly, position: 1),
            PlayedPass(index: 3, position: 3),
            PlayedPass(index: 5, mode: .firstLine, position: 5),
        ], columns: 1)
        #expect(plan.passes.map(\.index) == [0, 1, 2, 3])
        #expect(plan.passes.map(\.position) == [0, 1, 3, 5])
        #expect(plan.passes.map(\.name.chipText) == [
            "Verse 1", "Chorus 1/3", "Chorus 2/3", "Chorus 3/3",
        ])
        #expect(plan.passes.map(\.mode) == [.full, .chordsOnly, .full, .firstLine])
        #expect(plan.passes.map(\.kind) == [.verse, .chorus, .chorus, .chorus])
        #expect(plan.passes.allSatisfy { $0.column == 0 })
        // One column: tops strictly increase and each bottom is the next top minus the gap.
        let gap = plan.lyricSize * LayoutStyle.stage.sectionSpacing
        for (pass, next) in zip(plan.passes, plan.passes.dropFirst()) {
            #expect(pass.top < next.top)
            #expect(abs(pass.bottom + gap - next.top) < 1e-9)
        }
        for pass in plan.passes {
            let blocks = plan.blocks.filter { $0.pass == pass.index }
            #expect(abs(pass.weight - blocks.reduce(0) { $0 + $1.height }) < 1e-9)
        }
        // Gutter badges on the repeated label only.
        #expect(plan.block(id: 1)?.labelLines.map(\.text.text) == ["Chorus", "1 of 3", "CHORDS"])
        #expect(plan.block(id: 0)?.labelLines.map(\.text.text) == ["Verse 1"])
    }

    @Test
    func `a pass split across columns ends at its last part`() throws {
        // One 30-line verse: too tall for one column at the minimum, so it is split.
        let (plan, _) = plan(Support.longSong(lines: 30, perSection: 30))
        #expect(plan.fit == .fits)
        #expect(plan.passes.count == 1)
        let parts = plan.blocks.filter { $0.pass == 0 }
        #expect(parts.count > 1)
        let last = try #require(parts.last)
        #expect(plan.passes[0].column == 0)
        #expect(plan.passes[0].bottom == last.y + last.height)
        #expect(last.labelLines.last?.text.text == "(cont.)")
        #expect(last.labelLines.map(\.text.role) == [.sectionLabel, .labelDetail])
    }
}
