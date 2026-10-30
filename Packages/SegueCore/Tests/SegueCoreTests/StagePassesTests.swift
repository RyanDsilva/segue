import Foundation
import Library
import LiveLayout
import Testing

/// The current pass, progress and jump offset (P8-2 section 9): pure, from the plan and the
/// scroll offset.
struct StagePassesTests {
    typealias Support = LiveLayoutSupport

    /// Eight 6-line verses on a short stage: one column that scrolls.
    private static func scrolling() -> LayoutPlan {
        let request = LayoutRequest(
            model: Support.model(source: Support.longSong(lines: 48, perSection: 6)),
            viewport: LayoutSize(width: 700, height: 400),
            minLyricSize: 30,
            columns: 1,
        )
        return LayoutEngine.plan(request, metrics: FixedAdvanceMetrics())
    }

    @Test
    func `the reading line slides from 28 percent to the bottom of the content`() {
        let plan = Self.scrolling()
        #expect(plan.needsScroll)
        let height = plan.viewport.height
        #expect(abs(StagePasses.readLine(offset: 0, plan: plan) - 0.28 * height) < 1e-9)
        let mid = plan.overflow / 2
        #expect(abs(StagePasses.readLine(offset: mid, plan: plan) - (mid + 0.64 * height)) < 1e-9)
        #expect(abs(StagePasses.readLine(offset: plan.overflow, plan: plan) - plan.contentHeight)
            < 1e-9)
    }

    @Test
    func `the current pass follows the reading line unless pinned`() throws {
        let plan = Self.scrolling()
        #expect(plan.passes.count == 8)
        #expect(StagePasses.current(in: plan, offset: 0, pinned: nil) == 0)
        #expect(StagePasses.current(in: plan, offset: plan.overflow, pinned: nil) == 7)
        // Halfway: the last pass whose top is at or above the reading line.
        let mid = plan.overflow / 2
        let line = StagePasses.readLine(offset: mid, plan: plan)
        let expected = try #require(plan.passes.last { $0.top <= line }).index
        #expect(StagePasses.current(in: plan, offset: mid, pinned: nil) == expected)
        // A pin wins (a jump or a loop wrap), even near the bottom.
        #expect(StagePasses.current(in: plan, offset: 0, pinned: 5) == 5)
        #expect(StagePasses.current(in: plan, offset: plan.overflow, pinned: 2) == 2)
    }

    @Test
    func `progress runs from 0 to 1 through the current pass`() {
        let plan = Self.scrolling()
        let pass = plan.passes[3]
        // An offset that puts the reading line halfway through pass 3.
        let target = (pass.top + pass.bottom) / 2
        var low = 0.0
        var high = plan.overflow
        for _ in 0 ..< 60 {
            let mid = (low + high) / 2
            if StagePasses.readLine(offset: mid, plan: plan) < target {
                low = mid
            } else {
                high = mid
            }
        }
        #expect(abs(StagePasses.progress(of: 3, in: plan, offset: low) - 0.5) < 1e-6)
        #expect(StagePasses.progress(of: 7, in: plan, offset: 0) == 0)
        #expect(StagePasses.progress(of: 0, in: plan, offset: plan.overflow) == 1)
        // The wrap point: the reading line reaches the pass's bottom.
        let wrap = StagePasses.wrapOffset(of: 3, in: plan)
        #expect(abs(StagePasses.readLine(offset: wrap, plan: plan) - pass.bottom) < 1e-6)
        #expect(StagePasses.wrapOffset(of: 7, in: plan) == plan.overflow)
    }

    @Test
    func `a jump lands 14 pt above the pass, clamped to the overflow`() {
        let plan = Self.scrolling()
        #expect(StagePasses.jumpOffset(to: 0, in: plan) == 0)
        #expect(StagePasses.jumpOffset(to: 3, in: plan) == plan.passes[3].top - 14)
        #expect(StagePasses.jumpOffset(to: 7, in: plan) == min(
            plan.passes[7].top - 14,
            plan.overflow,
        ))
        #expect(StagePasses.jumpOffset(to: 8, in: plan) == nil)
    }

    @Test
    func `a fitting or multi-column plan keeps pass 1 current until a pin`() {
        let fits = LayoutEngine.plan(LayoutRequest(
            model: Support.model(source: Support.longSong(lines: 8, perSection: 4)),
            viewport: Support.macBook13,
            minLyricSize: 22,
        ), metrics: FixedAdvanceMetrics())
        #expect(!fits.needsScroll)
        #expect(StagePasses.current(in: fits, offset: 0, pinned: nil) == 0)
        #expect(StagePasses.current(in: fits, offset: 0, pinned: 1) == 1)
        #expect(StagePasses.jumpOffset(to: 1, in: fits) == nil)

        let columns = LayoutEngine.plan(LayoutRequest(
            model: Support.model(source: Support.longSong(lines: 120, perSection: 6)),
            viewport: LayoutSize(width: 1400, height: 400),
            minLyricSize: 30,
            columns: 2,
        ), metrics: FixedAdvanceMetrics())
        #expect(columns.columns.count == 2)
        #expect(columns.needsScroll)
        #expect(StagePasses.current(in: columns, offset: columns.overflow, pinned: nil) == 0)
        #expect(StagePasses.jumpOffset(to: 4, in: columns) == nil)
    }
}
