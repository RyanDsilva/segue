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
        let plannedIndex = Dictionary(
            record.planned.enumerated().map { ($0.element.itemId, $0.offset) },
            uniquingKeysWith: { first, _ in first },
        )
        // Planned items in performed order, as (row, planned position).
        let kept = record.items.enumerated().compactMap { row, item -> (row: Int, planned: Int)? in
            guard item.origin == .setlist, let planned = plannedIndex[item.itemId] else {
                return nil
            }
            return (row, planned)
        }
        // Items the performer moved (drawer drags, "Next"): when several runs are equally
        // long, the run that keeps the others wins, so the moved song is the one marked
        // "moved from #n" rather than the neighbour it was dropped past.
        let reordered = Set(record.events.compactMap { event in
            event.kind == .reordered ? event.itemId : nil
        })
        let unchangedRows = longestIncreasingRun(kept.map { pair in
            let moved = reordered.contains(record.items[pair.row].itemId)
            return KeptRow(row: pair.row, planned: pair.planned, moved: moved)
        })
        var changed = false
        let performed = record.items.enumerated().map { row, item -> Row in
            guard item.origin == .setlist, let planned = plannedIndex[item.itemId] else {
                changed = true
                return Row(item: item, change: .inserted(item.origin))
            }
            if unchangedRows.contains(row) {
                return Row(item: item, change: .unchanged)
            }
            changed = true
            return Row(item: item, change: .moved(fromPosition: planned))
        }
        // Entries left out at start (missing songs) are not a change: Save keeps them.
        guard changed else { return nil }
        return Self(
            setlistId: record.setlistId,
            setlistName: record.setlistName,
            planned: record.planned,
            performed: performed,
        )
    }

    /// The entries "Save to setlist" writes (`SetlistStore.replaceEntries`): planned entries
    /// in performed order (keeping their item IDs, overrides and notes), plus the inserted
    /// rows in `including` (`defaultIncluded` unless the performer unticks some) as new
    /// entries at their performed positions. Entries left out of the show because their song
    /// was missing keep their place after their planned predecessor.
    public func entries(including inserted: Set<ShowItemID>) -> [SetlistEntry] {
        let plannedByID = Dictionary(
            planned.map { ($0.itemId, $0) },
            uniquingKeysWith: { first, _ in first },
        )
        var written: [SetlistEntry] = performed.compactMap { row in
            if case .inserted = row.change {
                guard inserted.contains(row.item.itemId) else { return nil }
                return SetlistEntry(
                    itemId: row.item.itemId,
                    songId: row.item.songId,
                    overrides: row.item.overrides,
                    note: row.item.note,
                )
            }
            return plannedByID[row.item.itemId]
        }
        // Planned entries with no row (left out at start because the song was missing) go
        // back right after the planned entry before them, so Save never drops a song.
        var present = Set(written.map(\.itemId))
        for (position, entry) in planned.enumerated() where !present.contains(entry.itemId) {
            let anchor = planned[..<position].last { present.contains($0.itemId) }
            let index = anchor
                .flatMap { anchor in written.firstIndex { $0.itemId == anchor.itemId } }
                .map { $0 + 1 } ?? 0
            written.insert(entry, at: index)
            present.insert(entry.itemId)
        }
        return written
    }

    /// What the sheet ticks before the performer touches it: every inserted song and played
    /// request (decisions.md, phase 2 build rulings: inserted rows are checked by default).
    public var defaultIncluded: Set<ShowItemID> {
        Set(insertedItemIds)
    }

    /// Rows of `pairs` (row, planned position, moved by the performer) that form the
    /// longest run kept in planned order (strictly increasing planned positions). Among runs
    /// of the same length, the one keeping the most rows the performer did not move wins;
    /// remaining ties go to the earliest rows. Setlists are short, so this is the plain
    /// quadratic search.
    private static func longestIncreasingRun(_ pairs: [KeptRow]) -> Set<Int> {
        guard !pairs.isEmpty else { return [] }
        // Per index: (run length, unmoved rows kept) of the best run ending there.
        var best = [(length: Int, unmoved: Int)](
            repeating: (length: 0, unmoved: 0),
            count: pairs.count,
        )
        var previous = [Int?](repeating: nil, count: pairs.count)
        for index in pairs.indices {
            let own = pairs[index].moved ? 0 : 1
            best[index] = (1, own)
            for earlier in 0 ..< index where pairs[earlier].planned < pairs[index].planned {
                let candidate = (
                    length: best[earlier].length + 1,
                    unmoved: best[earlier].unmoved + own,
                )
                if candidate > best[index] {
                    best[index] = candidate
                    previous[index] = earlier
                }
            }
        }
        var end = 0
        for index in pairs.indices where best[index] > best[end] {
            end = index
        }
        var rows: Set<Int> = []
        var cursor: Int? = end
        while let index = cursor {
            rows.insert(pairs[index].row)
            cursor = previous[index]
        }
        return rows
    }

    /// A planned item in performed order: its row, its planned position, and whether the
    /// performer moved it.
    private struct KeptRow {
        var row: Int
        var planned: Int
        var moved: Bool
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
