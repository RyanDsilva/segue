// Owner: P9-2 (Singer view). Following a performer's position from one plan of a song in
// another (P9-2 sections 6.1 and 6.13): pass by pass at the same progress, so flipping `V`
// mid-song keeps the place, and the Singer Screen on a second display follows the main stage
// although its plan is laid out at another size in another drawing. Pure.

import Foundation

public enum SingerScreenFollow {
    /// The scroll offset at which the reading line (`StagePasses.readLine`) is `progress`
    /// (0 ... 1) of the way through pass `index` of `plan`, clamped to the plan's overflow;
    /// 0 when the plan does not scroll or has no such pass.
    public static func offset(pass index: Int, progress: Double, in plan: LayoutPlan) -> Double {
        let overflow = plan.overflow
        guard overflow > 0, plan.passes.indices.contains(index) else { return 0 }
        let pass = plan.passes[index]
        let fraction = progress.isFinite ? min(max(progress, 0), 1) : 0
        let target = pass.top + fraction * (pass.bottom - pass.top)
        // readLine(offset) = offset + h x (r + (1 - r) x offset / overflow): linear in offset.
        let height = plan.viewport.height
        let reading = StagePasses.readingFraction
        let slope = 1 + height * (1 - reading) / overflow
        return min(max((target - height * reading) / slope, 0), overflow)
    }

    /// Where the performer is in `plan` at `offset`: the current pass (`pinned` when set,
    /// else as the stage computes it) and the reading line's progress through it. Nil when
    /// the plan has no passes.
    public static func position(in plan: LayoutPlan, offset: Double, pinned: Int?)
        -> (pass: Int, progress: Double)?
    {
        guard let current = StagePasses.current(in: plan, offset: offset, pinned: pinned) else {
            return nil
        }
        return (current, StagePasses.progress(of: current, in: plan, offset: offset))
    }

    /// The follower's scroll offset for the leader at `offset`: the same pass at the same
    /// progress. When the leader's plan does not follow the scroll (it fits, or uses
    /// columns), its current pass (pinned by a jump, else the first) is shown from its start.
    /// A pass index the follower lacks lands on its last pass.
    public static func offset(
        following leader: LayoutPlan,
        at offset: Double,
        pinned: Int?,
        in follower: LayoutPlan,
    ) -> Double {
        guard let (pass, progress) = position(in: leader, offset: offset, pinned: pinned),
              !follower.passes.isEmpty
        else { return 0 }
        return self.offset(
            pass: min(pass, follower.passes.count - 1),
            progress: StagePasses.followsScroll(leader) ? progress : 0,
            in: follower,
        )
    }
}
