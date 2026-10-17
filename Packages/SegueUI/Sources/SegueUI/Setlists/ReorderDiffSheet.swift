// Phase 2 frozen interface (docs/phases/2-interfaces.md). Owner: unit D; presented by C
// (`liveModePresentations`).

#if os(macOS)
    import Shows
    import SwiftUI

    /// The show-end review: planned vs performed order side by side, moved rows and inserted
    /// songs (requests, play now, insert next) marked, each inserted row with an "Add to
    /// setlist" checkbox (default off). Two buttons, **Save to Setlist** and **Discard**,
    /// neither preselected as the default action (decisions.md).
    public struct ReorderDiffSheet: View {
        let diff: ReorderDiff
        /// Called with the inserted item IDs the user ticked.
        let onSave: (Set<ShowItemID>) -> Void
        let onDiscard: () -> Void

        public init(
            diff: ReorderDiff,
            onSave: @escaping (Set<ShowItemID>) -> Void,
            onDiscard: @escaping () -> Void,
        ) {
            self.diff = diff
            self.onSave = onSave
            self.onDiscard = onDiscard
        }

        public var body: some View {
            // Unit D builds the real sheet.
            Text("Reorder review for \(diff.setlistName)")
        }
    }
#endif
