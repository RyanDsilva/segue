// Phase 2 frozen interface (docs/phases/2-interfaces.md). Owner: unit B; used by C.
//
// The one place that decides which face each `TextRole` uses on stage. The layout engine
// measures with `StageTextMetrics` and the stage view draws with `StageTypography.font`, both
// from the same table, so the drawn text is exactly what auto-fit measured.

import LiveLayout
import SwiftUI

/// Core Text measurement with the bundled Schibsted Grotesk faces (and the system monospaced
/// face for `.verbatim`). Thread-safe; caches fonts per (role, size).
public struct StageTextMetrics: TextMeasuring {
    public init() {}

    public func width(of text: String, role: TextRole, size: Double) -> Double {
        fatalError("unimplemented: unit B (StageTextMetrics.width)")
    }
}

/// SwiftUI fonts matching `StageTextMetrics`.
public enum StageTypography {
    /// The face for `role` at point `size` (the plan's lyric/chord size, or the fixed role
    /// sizes in `LayoutStyle`).
    public static func font(_ role: TextRole, size: Double) -> Font {
        fatalError("unimplemented: unit B (StageTypography.font)")
    }
}
