// Phase 2 frozen interface (docs/phases/2-interfaces.md). Owner: unit B.

import Editing
import Foundation
import Library

/// The auto-fit algorithm (phase 2 spec, "Auto-fit layout"). Deterministic and pure:
///
/// 1. Lay out the rendered model (sections, lines, chord runs) with `metrics`, one block per
///    shown pass (`LayoutRequest.passes`, else the full song): every repeat written out in
///    full (R147), each pass in its show mode (R149).
/// 2. (Removed by R147: repeats are never collapsed.)
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
