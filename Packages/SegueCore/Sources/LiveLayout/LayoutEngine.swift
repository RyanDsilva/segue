// Phase 2 frozen interface (docs/phases/2-interfaces.md). Owner: unit B.

import Editing
import Foundation
import Library

/// The auto-fit algorithm (phase 2 spec, "Auto-fit layout"). Deterministic and pure:
///
/// 1. Lay out the rendered model (sections, lines, chord runs) with `metrics`.
/// 2. Collapse repeats when `collapseRepeats` (`RepeatCollapser`).
/// 3. For columns 1...3 (limited by `minColumnWidth`, or forced by `columns`), binary-search
///    the largest lyric size in `minLyricSize ... style.maxLyricSize` at which the content
///    fits the viewport height. Columns break at section boundaries.
/// 4. Pick the largest size; ties go to fewer columns.
/// 5. Nothing fits at the minimum: one or two columns at the minimum, scrolled.
/// 6. Multiply by `zoom` (never below the minimum); re-flow at that size with the chosen
///    column count; if it no longer fits, it scrolls.
public enum LayoutEngine {
    public static func plan(_ request: LayoutRequest, metrics: any TextMeasuring) -> LayoutPlan {
        let measurer = Measurer(metrics: metrics)
        let song = SongPreparation(request: request, measurer: measurer).measure()
        return FitSearch(request: request, song: song, measurer: measurer).plan()
    }
}

/// One section after repeat collapsing.
public struct CollapsedSection: Sendable, Hashable {
    /// Index into `RenderModel.sections`.
    public var index: Int
    /// Nil when shown in full; otherwise the earlier section it repeats and how many times
    /// this content has appeared so far (2 for the first repeat).
    public var repeatOf: Int?
    public var occurrence: Int
    /// Indices into the section's `items` that differ from the first occurrence (shown
    /// under the collapsed line).
    public var differingItems: [Int]

    public init(index: Int, repeatOf: Int?, occurrence: Int, differingItems: [Int]) {
        self.index = index
        self.repeatOf = repeatOf
        self.occurrence = occurrence
        self.differingItems = differingItems
    }
}
