// Phase 2 frozen interface (docs/phases/2-interfaces.md). Owner: unit C.

#if os(macOS)
    import SwiftUI

    public extension View {
        /// Everything live mode presents over the main window: the pre-show checklist, the
        /// "Resume show?" prompt, the missing-songs check and the show-end reorder review
        /// (`ReorderDiffSheet`, unit D's view, for `app.pendingReorderReviews.first`). The
        /// main window applies this once, so unit C never edits the root view.
        func liveModePresentations(_ app: AppModel) -> some View {
            modifier(LiveModePresentations(app: app))
        }
    }

    /// Unit C fills this in; until then it presents nothing.
    struct LiveModePresentations: ViewModifier {
        let app: AppModel

        func body(content: Content) -> some View {
            content
        }
    }
#endif
