/// Multi-selection over an ordered list with Finder's rules (R84): a click selects one row;
/// ⌘-click toggles a row; ⇧-click selects the range from the anchor to the row; ⇧↑ / ⇧↓
/// grow or shrink that range by one; plain ↑ / ↓ move a single selection. `focus` is the row
/// the detail pane and single-song commands act on (the last row clicked or reached by
/// keyboard); `ids` is everything selected, `focus` included. Pure, so the gestures are
/// tested without a view.
struct ListSelection<ID: Hashable>: Equatable {
    /// Every selected row.
    private(set) var ids: Set<ID> = []
    /// The row single-song commands and the detail pane use; nil when nothing is selected.
    private(set) var focus: ID?
    /// Where a ⇧ range starts: the last row clicked without ⇧.
    private(set) var anchor: ID?

    init() {}

    /// Exactly `id` (or nothing).
    init(single id: ID?) {
        select(id)
    }

    var count: Int {
        ids.count
    }

    var isMultiple: Bool {
        ids.count > 1
    }

    func contains(_ id: ID) -> Bool {
        ids.contains(id)
    }

    /// The selected rows in list order (Add to Setlist adds them in this order).
    func ordered(in order: [ID]) -> [ID] {
        order.filter(ids.contains)
    }

    /// A plain click, or a selection set from elsewhere: only `id`.
    mutating func select(_ id: ID?) {
        ids = id.map { [$0] } ?? []
        focus = id
        anchor = id
    }

    /// ⌘-click: adds `id`, or removes it (the focus moves to the nearest selected row in
    /// `order`, else nothing).
    mutating func toggle(_ id: ID, in order: [ID]) {
        if ids.contains(id) {
            ids.remove(id)
            if focus == id {
                focus = nearestSelected(to: id, in: order)
            }
            if anchor == id {
                anchor = focus
            }
        } else {
            ids.insert(id)
            focus = id
            anchor = id
        }
    }

    /// ⇧-click: the rows from the anchor to `id` (the anchor stays). Without an anchor in
    /// `order` it is a plain click.
    mutating func extend(to id: ID, in order: [ID]) {
        guard let anchor, let from = order.firstIndex(of: anchor),
              let to = order.firstIndex(of: id)
        else {
            select(id)
            return
        }
        ids = Set(order[min(from, to) ... max(from, to)])
        focus = id
    }

    /// ↑ / ↓ (`delta` -1 / +1): a single selection one row from the focus (the first or last
    /// row when nothing is selected). With `extending` (⇧), the range from the anchor grows
    /// or shrinks instead.
    mutating func move(_ delta: Int, in order: [ID], extending: Bool) {
        guard !order.isEmpty else { return }
        let current = focus.flatMap { order.firstIndex(of: $0) }
        let next = current.map { min(max($0 + delta, 0), order.count - 1) }
            ?? (delta > 0 ? 0 : order.count - 1)
        if extending, current != nil {
            extend(to: order[next], in: order)
        } else {
            select(order[next])
        }
    }

    /// Drops rows no longer in `order` (a search narrowed the list); the focus moves to the
    /// nearest row still selected.
    mutating func keep(only order: [ID]) {
        let present = Set(order)
        ids.formIntersection(present)
        if let focus, !present.contains(focus) {
            self.focus = order.first(where: ids.contains)
        }
        if let anchor, !ids.contains(anchor) {
            self.anchor = focus
        }
    }

    private func nearestSelected(to id: ID, in order: [ID]) -> ID? {
        guard let index = order.firstIndex(of: id) else { return order.first(where: ids.contains) }
        let after = order[(index + 1)...].first(where: ids.contains)
        return after ?? order[..<index].last(where: ids.contains)
    }
}
