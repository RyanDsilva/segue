// P8-6b (docs/phases/8-workstreams/P8-6-audio.md section 10.4, R162 Q4): where the stage
// scrolls while Rehearsal play-along plays. The audio is the clock: the line holding the
// chord at the playhead sits at the reading line. Pure, from the plan.

import Editing
import Foundation

public extension StagePasses {
    /// The top of `line` as pass `pass` (a `PlanPass.index`) shows it: the first row laid
    /// out from that source line in that pass's blocks. Nil when the pass does not show it
    /// (a First line pass, or a Chords only pass for a chordless line).
    static func lineTop(_ line: BlockPath, pass: Int, in plan: LayoutPlan) -> Double? {
        for column in plan.columns {
            for block in column.blocks where block.pass == pass {
                guard case let .rows(rows) = block.content else { continue }
                if let row = rows.first(where: { $0.source == line }) {
                    return block.y + row.y
                }
            }
        }
        return nil
    }

    /// The offset that puts `y` at the reading line (the inverse of `readLine`), clamped to
    /// the overflow; nil when the plan does not follow the scroll (it fits or uses columns).
    static func offset(readingAt y: Double, in plan: LayoutPlan) -> Double? {
        guard followsScroll(plan) else { return nil }
        let overflow = plan.overflow
        let height = plan.viewport.height
        // offset + h x (0.28 + 0.72 x offset / overflow) = y, linear in offset.
        let slope = 1 + height * (1 - readingFraction) / overflow
        return min(max((y - height * readingFraction) / slope, 0), overflow)
    }
}
