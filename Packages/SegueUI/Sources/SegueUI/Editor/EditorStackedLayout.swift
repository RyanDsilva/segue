import SwiftUI

/// Text mode in a narrow pane: the source over a rule over the preview. The two share the
/// height, except that the preview never gets less than its pinned diagram strip plus
/// `pageMinimum` of page, so the song's title and first lines stay in view under a tall
/// strip (a bassist's fretboard diagrams left the page 90 pt, only the title, at the
/// default window size). The source keeps at least `sourceMinimum`.
struct EditorStackedLayout: Layout {
    var pageMinimum: CGFloat = 180
    var sourceMinimum: CGFloat = 120

    func sizeThatFits(
        proposal: ProposedViewSize,
        subviews _: Subviews,
        cache _: inout (),
    ) -> CGSize {
        proposal.replacingUnspecifiedDimensions()
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal _: ProposedViewSize,
        subviews: Subviews,
        cache _: inout (),
    ) {
        guard subviews.count == 3 else { return }
        let width = bounds.width
        let rule = subviews[1].sizeThatFits(ProposedViewSize(width: width, height: nil)).height
        // Proposed no height, the preview answers with what it cannot give up: the strip.
        let pinned = subviews[2].sizeThatFits(ProposedViewSize(width: width, height: 0)).height
        let preview = Self.previewHeight(
            total: bounds.height,
            rule: rule,
            pinned: pinned,
            pageMinimum: pageMinimum,
            sourceMinimum: sourceMinimum,
        )
        let heights = [max(0, bounds.height - rule - preview), rule, preview]
        var y = bounds.minY
        for (subview, height) in zip(subviews, heights) {
            subview.place(
                at: CGPoint(x: bounds.minX, y: y),
                anchor: .topLeading,
                proposal: ProposedViewSize(width: width, height: height),
            )
            y += height
        }
    }

    /// Half the space, or the strip plus `pageMinimum` when that is more, as long as the
    /// source keeps `sourceMinimum`; never less than half.
    static func previewHeight(
        total: CGFloat,
        rule: CGFloat,
        pinned: CGFloat,
        pageMinimum: CGFloat,
        sourceMinimum: CGFloat,
    ) -> CGFloat {
        let available = max(0, total - rule)
        let half = available / 2
        let wanted = max(half, pinned + pageMinimum)
        return min(wanted, max(half, available - sourceMinimum))
    }
}
