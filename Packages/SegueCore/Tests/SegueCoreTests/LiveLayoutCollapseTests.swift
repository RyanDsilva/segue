import ChordPro
import Editing
import Foundation
import LiveLayout
import Testing

/// `collapseRepeats` on and off: `RepeatCollapser` and how collapsed sections are laid out.
struct LiveLayoutCollapseTests {
    typealias Support = LiveLayoutSupport

    @Test
    func `chorus repeats collapse to the first chorus`() throws {
        let model = try Support.model("basic-verse-chorus.cho")
        let collapsed = RepeatCollapser.collapse(model.sections, enabled: true)
        // Verse 1, Chorus, Verse 2, {chorus}, Bridge, {chorus: Final Chorus}
        #expect(collapsed.map(\.repeatOf) == [nil, nil, nil, 1, nil, 1])
        #expect(collapsed.map(\.occurrence) == [1, 1, 1, 2, 1, 3])
        let differing = collapsed.flatMap(\.differingItems)
        #expect(differing.isEmpty)
    }

    @Test
    func `disabled leaves every section in full`() throws {
        let model = try Support.model("basic-verse-chorus.cho")
        let collapsed = RepeatCollapser.collapse(model.sections, enabled: false)
        #expect(collapsed.allSatisfy { $0.repeatOf == nil && $0.occurrence == 1 })
    }

    @Test
    func `a written-out repeat collapses and keeps its differing line`() throws {
        let model = Support.model(source: """
        {start_of_chorus}
        [C]Let them go, [G]let them glow
        [D]Down the river [Em]where the winds blow
        [C]Hold me close till [G]morning
        {end_of_chorus}

        {start_of_verse}
        [G]Something else entirely
        {end_of_verse}

        {start_of_chorus}
        [C]let them go - [G]LET them glow!
        [D]Down the river [Em]where the winds blow
        [C]Hold me close till [D]evening
        {end_of_chorus}

        {start_of_chorus}
        [F]All new words here
        [F]and here
        [F]and here too
        {end_of_chorus}
        """)
        let collapsed = RepeatCollapser.collapse(model.sections, enabled: true)
        #expect(collapsed.map(\.repeatOf) == [nil, nil, 0, nil])
        // Case and punctuation are ignored; the changed chord and word are not.
        #expect(collapsed[2].differingItems == [2])
        let (plan, request) = Support.plan(model)
        let block = try #require(plan.block(id: 2))
        guard case let .collapsed(line, differing) = block.content else {
            Issue.record("third section is not collapsed")
            return
        }
        #expect(line.text == "Repeat chorus")
        #expect(line.role == .collapsedRepeat)
        #expect(line.size == plan.lyricSize)
        #expect(block.label == "Chorus x2")
        #expect(block.isChorusLabel)
        #expect(differing.map { $0.text.map(\.text).joined() } == ["Hold me close till evening"])
        #expect(block.collapsedBaseline != nil)
        #expect(LayoutAudit.violations(of: plan, request: request, metrics: FixedAdvanceMetrics())
            .isEmpty)
    }

    @Test
    func `a chorus repeat refers to the chorus with its label`() throws {
        let model = try Support.model("hindi-dil-kabhie.cho")
        let repeatIndex = try #require(model.sections.firstIndex { $0.isRepeat })
        let target = try #require(RepeatCollapser.repeatTarget(of: repeatIndex, in: model.sections))
        #expect(model.sections[target].label == "Mukhda")
        let (plan, _) = Support.plan(model)
        let block = try #require(plan.block(id: repeatIndex))
        guard case let .collapsed(line, _) = block.content else {
            Issue.record("the repeat is not collapsed")
            return
        }
        #expect(line.text == "Repeat Mukhda")
        #expect(block.label == "Mukhda x2")
    }

    @Test
    func `with collapsing off a chorus repeat is drawn in full`() throws {
        let model = try Support.model("basic-verse-chorus.cho")
        let (plan, request) = Support.plan(model, collapseRepeats: false)
        let chorus = try #require(plan.block(id: 1))
        let repeated = try #require(plan.block(id: 3))
        guard case let .rows(rows) = repeated.content else {
            Issue.record("repeat is not drawn in full")
            return
        }
        #expect(rows.map(\.text) == chorus.allRows.map(\.text))
        #expect(repeated.label == "Chorus")
        #expect(LayoutAudit.violations(of: plan, request: request, metrics: FixedAdvanceMetrics())
            .isEmpty)
        // Collapsing makes the same song shorter, so it can only be set larger.
        let (collapsed, _) = Support.plan(model, collapseRepeats: true)
        #expect(collapsed.lyricSize >= plan.lyricSize)
    }

    @Test
    func `a chorus repeat with no chorus before it shows the repeat line`() {
        let model = Support.model(source: "{chorus}\n\n[G]After")
        let (plan, _) = Support.plan(model, collapseRepeats: false)
        guard case let .collapsed(line, _) = plan.block(id: 0)?.content else {
            Issue.record("orphan repeat not drawn as a repeat line")
            return
        }
        #expect(line.text == "Repeat chorus")
    }

    @Test
    func `line count includes repeated choruses`() throws {
        let model = try Support.model("basic-verse-chorus.cho")
        let (plan, _) = Support.plan(model)
        // 2 + 3 + 2 + 3 (repeat) + 2 + 3 (repeat)
        #expect(plan.lineCount == 15)
    }
}
