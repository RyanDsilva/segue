import CoreGraphics
@testable import SegueUI
import Testing

/// The text editor's stacked split (source over preview in a narrow pane): the preview
/// keeps its pinned strip plus room for the page's first lines, the source keeps a minimum.
struct EditorStackedLayoutTests {
    struct Case: Sendable, CustomTestStringConvertible {
        var total: CGFloat
        var pinned: CGFloat
        var preview: CGFloat

        var testDescription: String {
            "\(total) pt, strip \(pinned)"
        }
    }

    @Test(arguments: [
        // No strip: halves.
        Case(total: 467, pinned: 0, preview: 233),
        // The bassist's strip at the default window size: strip + 180 of page.
        Case(total: 467, pinned: 142, preview: 322),
        // A short pane: the source keeps 120.
        Case(total: 401, pinned: 142, preview: 280),
        // Shorter than both minimums: never less than half.
        Case(total: 201, pinned: 142, preview: 100),
        // A tall pane: halves again.
        Case(total: 901, pinned: 142, preview: 450),
    ])
    func `the preview keeps its strip and the first lines`(_ item: Case) {
        #expect(EditorStackedLayout.previewHeight(
            total: item.total,
            rule: 1,
            pinned: item.pinned,
            pageMinimum: 180,
            sourceMinimum: 120,
        ) == item.preview)
    }
}
