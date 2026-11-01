// P9-3 9.6 (R178): which medley member the performer is in. The current member follows the
// reading line and is committed to the show once the line has stayed in a new member for
// 1 s on the scroll clock (a quick scroll past a boundary logs no play), or at once on a
// key. Pure, from the plan and the scroll offset.

import Foundation

public enum MedleyFollow {
    /// How long the reading line stays in a new member before it is committed.
    public static let dwell: TimeInterval = 1.0

    /// The top of member `segment`'s header (its block's top plus the inset); nil when the
    /// plan has no header for it.
    public static func headerTop(of segment: Int, in plan: LayoutPlan) -> Double? {
        for column in plan.columns {
            for block in column.blocks where block.segment == segment && block.memberHeader != nil {
                return block.y + block.memberHeaderTop
            }
        }
        return nil
    }

    /// How many members the plan holds (1 for a song).
    public static func memberCount(in plan: LayoutPlan) -> Int {
        (plan.passes.map(\.segment).max() ?? 0) + 1
    }

    /// The member at `readLine`: the last whose header (else first pass) top is at or above
    /// it; 0 when none is.
    public static func member(at readLine: Double, plan: LayoutPlan) -> Int {
        let count = memberCount(in: plan)
        guard count > 1 else { return 0 }
        var member = 0
        for segment in 0 ..< count {
            let top = headerTop(of: segment, in: plan)
                ?? plan.passes.first { $0.segment == segment }?.top
            if let top, top <= readLine {
                member = segment
            }
        }
        return member
    }

    /// The member the stage shows at `offset`: the pinned pass's member when a jump or a loop
    /// pinned one; for a plan that follows the scroll, the member at the reading line; nil
    /// when nothing follows (a fitted or multi-column plan only moves on keys).
    public static func member(in plan: LayoutPlan, offset: Double, pinned: Int?) -> Int? {
        if let pinned, plan.passes.indices.contains(pinned) {
            return plan.passes[pinned].segment
        }
        guard StagePasses.followsScroll(plan) else { return nil }
        return member(at: StagePasses.readLine(offset: offset, plan: plan), plan: plan)
    }

    /// Where `→` / `←` land on member `segment`: its header's top minus the jump margin,
    /// clamped to the overflow.
    public static func seekOffset(to segment: Int, in plan: LayoutPlan) -> Double? {
        let top = headerTop(of: segment, in: plan)
            ?? plan.passes.first { $0.segment == segment }?.top
        guard let top else { return nil }
        return min(max(top - StagePasses.jumpMargin, 0), plan.overflow)
    }

    /// The dwell rule: feed it the member the stage shows and the committed one; it returns
    /// the member to commit once the shown one has differed for `dwell` seconds.
    public struct Dwell: Sendable, Equatable {
        public private(set) var candidate: Int?
        public private(set) var since: Date?

        public init() {}

        public mutating func observe(shown: Int, committed: Int, at now: Date) -> Int? {
            guard shown != committed else {
                reset()
                return nil
            }
            if candidate != shown {
                candidate = shown
                since = now
                return nil
            }
            guard let since, now.timeIntervalSince(since) >= MedleyFollow.dwell else {
                return nil
            }
            reset()
            return shown
        }

        public mutating func reset() {
            candidate = nil
            since = nil
        }
    }
}
