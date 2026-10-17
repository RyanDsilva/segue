// Phase 2 frozen interface (docs/phases/2-interfaces.md). Owner: unit A.

import Foundation
import Setlists

/// Planned vs performed order at show end, for the Save/Discard sheet (decisions.md: always
/// ask when the order changed; no preselected default; no sheet when nothing changed).
public struct ReorderDiff: Sendable, Hashable {
    /// How a performed row relates to the plan.
    public enum Change: Sendable, Hashable {
        /// Same relative position as planned.
        case unchanged
        /// Moved: not part of the longest run of planned items kept in planned order.
        case moved(fromPosition: Int)
        /// Not in the setlist: a played request or a song inserted from search.
        case inserted(ItemOrigin)
    }

    public struct Row: Sendable, Hashable, Identifiable {
        public var item: ShowItem
        public var change: Change

        public var id: ShowItemID {
            item.itemId
        }

        public init(item: ShowItem, change: Change) {
            self.item = item
            self.change = change
        }
    }

    public var setlistId: SetlistID
    public var setlistName: String
    /// The setlist's entries at show start.
    public var planned: [SetlistEntry]
    /// Every show item in performed order (skipped ones included, so they keep a slot).
    public var performed: [Row]

    public init(
        setlistId: SetlistID,
        setlistName: String,
        planned: [SetlistEntry],
        performed: [Row],
    ) {
        self.setlistId = setlistId
        self.setlistName = setlistName
        self.planned = planned
        self.performed = performed
    }

    /// The diff for `record`; nil when its items are the planned entries in planned order
    /// with nothing inserted.
    public static func compute(_ record: ShowRecord) -> Self? {
        fatalError("unimplemented: unit A (ReorderDiff.compute)")
    }

    /// The entries "Save to setlist" writes (`SetlistStore.replaceEntries`): planned entries
    /// in performed order (keeping their item IDs, overrides and notes), plus the inserted
    /// rows in `including` as new entries at their performed positions.
    public func entries(including inserted: Set<ShowItemID>) -> [SetlistEntry] {
        fatalError("unimplemented: unit A (ReorderDiff.entries)")
    }

    /// Item IDs of rows that are inserted songs.
    public var insertedItemIds: [ShowItemID] {
        performed.compactMap { row in
            if case .inserted = row.change {
                return row.item.itemId
            }
            return nil
        }
    }
}
