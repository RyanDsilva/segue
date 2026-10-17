import ChordPro
import Editing
import Foundation
import Library
import LiveLayout
import Testing

/// Gutter labels (decisions.md, "Auto-fit prefers no wrapping"): never below 12pt, the
/// repeat count and "(cont.)" on a small second line instead of an awkward wrap, the gutter
/// widening for long names, and every label top-aligned with its section (mockup C).
struct LiveLayoutGutterTests {
    typealias Support = LiveLayoutSupport

    private let metrics = FixedAdvanceMetrics()

    @Test
    func `a repeat count is a small second line under the name`() throws {
        let model = Support.model(source: """
        {start_of_verse: Verse 2}
        [G]Paper boats
        {end_of_verse}
        {start_of_verse: Verse 2}
        [G]Paper boats
        {end_of_verse}
        """)
        let (plan, request) = Support.plan(model)
        let block = try #require(plan.block(id: 1))
        #expect(block.label == "Verse 2 x2")
        #expect(block.labelLines.map(\.text.text) == ["Verse 2", "x2"])
        #expect(block.labelLines.map(\.text.role) == [.sectionLabel, .labelDetail])
        #expect(block.labelLines.map(\.text.size) == [13, 12])
        #expect(block.labelLines[1].baseline > block.labelLines[0].baseline)
        #expect(LayoutAudit.violations(of: plan, request: request, metrics: metrics).isEmpty)
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
