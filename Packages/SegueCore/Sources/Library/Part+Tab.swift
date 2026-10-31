// P8-7d (docs/phases/8-workstreams/P8-7-time-model-and-fills.md section 12.6): a resolved note
// as the mini tab's input. Pure.

import Diagrams

public extension TabNote {
    /// `note` as drawn in a mini tab; `isLanding` marks the landing chord's root.
    init(_ note: ResolvedNote, isLanding: Bool = false) {
        self.init(
            tick: note.tick,
            length: note.len,
            position: note.position,
            articulations: note.articulations,
            name: note.name,
            isLanding: isLanding,
        )
    }
}
