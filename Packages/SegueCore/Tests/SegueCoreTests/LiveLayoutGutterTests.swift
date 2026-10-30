import ChordPro
import Editing
import Foundation
import Library
import LiveLayout
import Testing

/// Gutter labels (decisions.md, "Auto-fit prefers no wrapping"; R147): never below 12pt, the
/// pass badge ("2 of 3"), the mode tag and "(cont.)" on small lines under the name instead of
/// an awkward wrap, the gutter widening for long names, and every label top-aligned with its
/// section (mockup C).
struct LiveLayoutGutterTests {
    typealias Support = LiveLayoutSupport

    private let metrics = FixedAdvanceMetrics()

    @Test
    func `a repeated label carries a pass badge and a mode tag under the name`() throws {
        let model = Support.model(source: """
        {start_of_verse: Verse 2}
        [G]Paper boats
        {end_of_verse}
        {start_of_chorus}
        [C]Harbour lights
        {end_of_chorus}
        {start_of_verse: Verse 2}
        [G]Paper boats
        {end_of_verse}
        """)
        let (plan, request) = Support.plan(model)
        let first = try #require(plan.block(id: 0))
        let block = try #require(plan.block(id: 2))
        #expect(block.label == "Verse 2")
        #expect(first.labelLines.map(\.text.text) == ["Verse 2", "1 of 2"])
        #expect(block.labelLines.map(\.text.text) == ["Verse 2", "2 of 2"])
        #expect(block.labelLines.map(\.text.role) == [.sectionLabel, .passBadge])
        #expect(block.labelLines.map(\.text.size) == [13, 12])
        // The badge sits in its box (6 pt in from the gutter edge), 4 pt below the name.
        #expect(block.labelLines[1].text.x == 6)
        #expect(block.labelLines[1].baseline > block.labelLines[0].baseline + 4)
        // A label shown once has no badge.
        #expect(try #require(plan.block(id: 1)).labelLines.map(\.text.text) == ["Chorus"])
        #expect(LayoutAudit.violations(of: plan, request: request, metrics: metrics).isEmpty)

        // A Chords only pass adds its mode tag under the badge.
        let units = SongSections.units(of: model.sections)
        let request2 = LayoutRequest(
            model: model,
            viewport: Support.macBook13,
            minLyricSize: 22,
            passes: [
                PlayedPass(index: units[0].index, mode: .chordsOnly, position: 0),
                PlayedPass(index: units[2].index, mode: .firstLine, position: 1),
            ],
        )
        let tagged = LayoutEngine.plan(request2, metrics: metrics)
        let chords = try #require(tagged.block(id: 0))
        #expect(chords.labelLines.map(\.text.text) == ["Verse 2", "1 of 2", "CHORDS"])
        #expect(chords.labelLines.map(\.text.role) == [.sectionLabel, .passBadge, .modeTag])
        #expect(chords.labelLines.map(\.text.size) == [13, 12, 10.5])
        #expect(try #require(tagged.block(id: 1)).labelLines.last?.text.text == "1ST LINE")
        let issues = LayoutAudit.violations(of: tagged, request: request2, metrics: metrics)
        #expect(issues.isEmpty, "\(issues)")
    }

    /// The name's first ink sits level with the first chord's ink: the label heads the
    /// section instead of hanging beside its first lyric.
    @Test
    func `labels are top aligned with the section's first ink`() throws {
        let model = Support.model(source: """
        {start_of_chorus}
        [C]Hold on, [G]harbor lights
        {end_of_chorus}
        {start_of_verse}
        Lyrics without chords
        {end_of_verse}
        """)
        let (plan, _) = Support.plan(model)
        let inkTop = metrics.extents(of: .lyric).inkTop
        for block in plan.blocks {
            let label = try #require(block.labelLines.first)
            let labelTop = label.baseline - inkTop * label.text.size
            let row = try #require(block.allRows.first)
            let contentTop = if let baseline = row.chordBaseline {
                row.y + baseline - inkTop * plan.chordSize
            } else {
                row.y + row.textBaseline - inkTop * plan.lyricSize
            }
            #expect(abs(labelTop - contentTop) < 1e-9, "\(block.label ?? "")")
        }
    }

    @Test
    func `labels never go below 12pt and the gutter widens for long names`() throws {
        // 0.5 em per character: "Final Chorus" is 78pt at 13pt, wider than the 64pt gutter.
        let model = Support.model(source: """
        {start_of_chorus: Final Chorus}
        [G]Home again
        {end_of_chorus}
        {start_of_verse: An Extraordinarily Long Section Name}
        [D]Still here
        {end_of_verse}
        """)
        let (plan, request) = Support.plan(model)
        #expect(plan.gutterWidth == LayoutStyle.stage.maxGutterWidth)
        let final = try #require(plan.block(id: 0))
        #expect(final.labelLines.map(\.text.text) == ["Final Chorus"])
        #expect(final.labelLines.first?.text.size == 13)
        // Too long for the widest gutter even at 12pt: wrapped at words, still 12pt.
        let long = try #require(plan.block(id: 1))
        #expect(long.labelLines.count > 1)
        #expect(long.labelLines.allSatisfy { $0.text.size >= 12 })
        #expect(LayoutAudit.violations(of: plan, request: request, metrics: metrics).isEmpty)
        // Short labels keep the 64pt gutter, so lyrics start where the mockup puts them.
        let (short, _) = Support.plan(Support.model(source: Support.longSong(lines: 8)))
        #expect(short.gutterWidth == LayoutStyle.stage.gutterWidth)
    }

    @Test
    func `a split section is labelled cont on each later part`() throws {
        // One 30-line verse: too tall for one column at the minimum, so it is split.
        let model = Support.model(source: Support.longSong(lines: 30, perSection: 30))
        let (plan, request) = Support.plan(model)
        #expect(plan.fit == .fits)
        #expect(plan.blocks.count > 1)
        let first = try #require(plan.blocks.first)
        #expect(first.labelLines.map(\.text.text) == ["Verse 1"])
        for part in plan.blocks.dropFirst() {
            #expect(part.part > 0)
            #expect(part.label == "Verse 1 (cont.)")
            #expect(part.labelLines.map(\.text.text) == ["Verse 1", "(cont.)"])
            #expect(part.labelLines.last?.text.role == .labelDetail)
        }
        #expect(LayoutAudit.violations(of: plan, request: request, metrics: metrics).isEmpty)
    }
}
