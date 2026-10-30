// Owner: P8-2. Which pass is current on stage and how far through it the performer is
// (R147, R148): pure, from the plan and the scroll offset, so it is tested without a window.

import Foundation

public enum StagePasses {
    /// How far down the viewport the reading line sits at the top of the song (mockup).
    public static let readingFraction = 0.28
    /// A jump lands this far above the pass's top (mockup).
    public static let jumpMargin = 14.0

    /// The y in the song that counts as "where the performer is":
    /// `offset + viewportHeight x (0.28 + 0.72 x f)`, `f = offset / overflow` (0 when the plan
    /// does not scroll). It slides to the bottom of the content as the scroll reaches the
    /// end, so the last passes become current even when they never reach 28%.
    public static func readLine(offset: Double, plan: LayoutPlan) -> Double {
        let overflow = plan.overflow
        let fraction = overflow > 0 ? min(max(offset / overflow, 0), 1) : 0
        return offset + plan.viewport.height
            * (readingFraction + (1 - readingFraction) * fraction)
    }

    /// Whether the current pass follows the scroll: a one-column plan that scrolls. A plan
    /// that fits, or is laid out in two or three columns, keeps pass 1 current until a jump
    /// pins another (R158 Q2).
    public static func followsScroll(_ plan: LayoutPlan) -> Bool {
        plan.needsScroll && plan.columns.count <= 1
    }

    /// The current pass's index: `pinned` when set (a jump or a loop wrap), else for a plan
    /// that follows the scroll the last pass whose top is at or above the reading line, else
    /// 0. Nil when the plan has no passes.
    public static func current(in plan: LayoutPlan, offset: Double, pinned: Int?) -> Int? {
        guard !plan.passes.isEmpty else { return nil }
        if let pinned, plan.passes.indices.contains(pinned) {
            return pinned
        }
        guard followsScroll(plan) else { return 0 }
        let line = readLine(offset: offset, plan: plan)
        return plan.passes.last { $0.top <= line }?.index ?? 0
    }

    /// How far the reading line is through pass `index`, 0 ... 1.
    public static func progress(of index: Int, in plan: LayoutPlan, offset: Double) -> Double {
        guard plan.passes.indices.contains(index) else { return 0 }
        let pass = plan.passes[index]
        let span = pass.bottom - pass.top
        guard span > 0 else { return 0 }
        let line = readLine(offset: offset, plan: plan)
        return min(max((line - pass.top) / span, 0), 1)
    }

    /// Where a jump to pass `index` scrolls: `jumpMargin` above its top, clamped to the
    /// overflow; nil when nothing scrolls (the plan fits or uses columns: only the pinned
    /// pass changes).
    public static func jumpOffset(to index: Int, in plan: LayoutPlan) -> Double? {
        guard plan.passes.indices.contains(index), followsScroll(plan) else { return nil }
        return min(max(plan.passes[index].top - jumpMargin, 0), plan.overflow)
    }

    /// The offset at which the reading line reaches pass `index`'s bottom (the loop's wrap
    /// point), or the overflow when it never does.
    public static func wrapOffset(of index: Int, in plan: LayoutPlan) -> Double {
        let overflow = plan.overflow
        guard plan.passes.indices.contains(index), overflow > 0 else { return overflow }
        let bottom = plan.passes[index].bottom
        let height = plan.viewport.height
        // Solve offset + h x (0.28 + 0.72 x offset / overflow) = bottom (linear in offset).
        let slope = 1 + height * (1 - readingFraction) / overflow
        let offset = (bottom - height * readingFraction) / slope
        return min(max(offset, 0), overflow)
    }
}
