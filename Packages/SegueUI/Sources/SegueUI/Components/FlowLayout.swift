import SwiftUI

/// Lays subviews out left to right, wrapping onto new lines (tag chips).
struct FlowLayout: Layout {
    var spacing: CGFloat = 6
    var lineSpacing: CGFloat = 6
    /// The last subview is an accessory of the one before it (the song card's "+"): when it
    /// would wrap onto a line of its own, the item before it moves down with it.
    var keepsLastWithPrevious = false

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache _: inout ()) -> CGSize {
        let rows = arrange(subviews, width: proposal.width ?? .infinity)
        let width = rows.map(\.width).max() ?? 0
        let height = rows.map(\.height).reduce(0, +)
            + lineSpacing * CGFloat(max(rows.count - 1, 0))
        return CGSize(width: width, height: height)
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal _: ProposedViewSize,
        subviews: Subviews,
        cache _: inout (),
    ) {
        var y = bounds.minY
        for row in arrange(subviews, width: bounds.width) {
            var x = bounds.minX
            for (index, size) in zip(row.indices, row.sizes) {
                // Centre each item on the row's midline (chips and fields differ slightly).
                let offset = (row.height - size.height) / 2
                subviews[index].place(
                    at: CGPoint(x: x, y: y + offset),
                    proposal: ProposedViewSize(size),
                )
                x += size.width + spacing
            }
            y += row.height + lineSpacing
        }
    }

    struct Row: Equatable {
        var indices: [Int] = []
        var sizes: [CGSize] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    private func arrange(_ subviews: Subviews, width: CGFloat) -> [Row] {
        rows(subviews.map { $0.sizeThatFits(.unspecified) }, width: width)
    }

    /// The lines for items of `sizes` in `width` (in-process tests call it directly).
    func rows(_ sizes: [CGSize], width: CGFloat) -> [Row] {
        var rows: [Row] = []
        var row = Row()
        for (index, size) in sizes.enumerated() {
            let needed = row.indices.isEmpty ? size.width : row.width + spacing + size.width
            if needed > width, !row.indices.isEmpty {
                rows.append(row)
                row = Row()
            }
            row.width = row.indices.isEmpty ? size.width : row.width + spacing + size.width
            row.height = max(row.height, size.height)
            row.indices.append(index)
            row.sizes.append(size)
        }
        if !row.indices.isEmpty {
            rows.append(row)
        }
        return keepsLastWithPrevious ? Self.withoutOrphan(rows, spacing: spacing, width: width)
            : rows
    }

    /// Moves the last item of the next-to-last row down beside a lone last item, when the
    /// two fit on one line and the row they leave keeps an item.
    private static func withoutOrphan(_ rows: [Row], spacing: CGFloat, width: CGFloat) -> [Row] {
        guard rows.count >= 2, let lone = rows.last, lone.indices.count == 1,
              rows[rows.count - 2].indices.count >= 2
        else { return rows }
        var above = rows[rows.count - 2]
        let index = above.indices.removeLast()
        let size = above.sizes.removeLast()
        guard size.width + spacing + lone.width <= width else { return rows }
        above.width = above.sizes.map(\.width).reduce(0, +)
            + spacing * CGFloat(max(above.sizes.count - 1, 0))
        above.height = above.sizes.map(\.height).max() ?? 0
        let last = Row(
            indices: [index] + lone.indices,
            sizes: [size] + lone.sizes,
            width: size.width + spacing + lone.width,
            height: max(size.height, lone.height),
        )
        return rows.dropLast(2) + [above, last]
    }
}
