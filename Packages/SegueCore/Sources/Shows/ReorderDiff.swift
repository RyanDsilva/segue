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

    /// The show the diff came from (its review state is stored there); nil for diffs built
    /// by hand.
    public var showId: ShowID?
    public var setlistId: SetlistID
    public var setlistName: String
    /// The setlist's entries at show start.
    public var planned: [SetlistEntry]
    /// Every show item in performed order (skipped ones included, so they keep a slot).
    public var performed: [Row]

    public init(
        showId: ShowID? = nil,
        setlistId: SetlistID,
        setlistName: String,
        planned: [SetlistEntry],
        performed: [Row],
    ) {
        self.showId = showId
        self.setlistId = setlistId
        self.setlistName = setlistName
        self.planned = planned
        self.performed = performed
    }

    /// The diff for `record`; nil when its items are the planned entries in planned order
    /// with nothing inserted.
    public static func compute(_ record: ShowRecord) -> Self? {
        // A medley's members are one slot keyed by the medley's ID (P9-3 8.2): they share
        // its planned position and its verdict, so a medley played in its place reads
        // "unchanged".
        let plannedIndex = Dictionary(
            record.planned.enumerated().map { ($0.element.itemId, $0.offset) },
            uniquingKeysWith: { first, _ in first },
        )
        func plannedPosition(_ item: ShowItem) -> Int? {
            guard item.origin == .setlist else { return nil }
            return plannedIndex[item.medley?.slot ?? item.itemId]
        }
        // Planned slots in performed order, as (row, planned position): a medley by its first
        // member's row.
        let slotRow = slotRows(record.items)
        let kept = record.items.enumerated().compactMap { row, item -> (row: Int, planned: Int)? in
            guard slotRow[row] == row, let planned = plannedPosition(item) else { return nil }
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
            guard let planned = plannedPosition(item) else {
                changed = true
                return Row(item: item, change: .inserted(item.origin))
            }
            if unchangedRows.contains(slotRow[row]) {
                return Row(item: item, change: .unchanged)
            }
            changed = true
            return Row(item: item, change: .moved(fromPosition: planned))
        }
        // Entries left out at start (missing songs) are not a change: Save keeps them.
        guard changed else { return nil }
        return Self(
            showId: record.id,
            setlistId: record.setlistId,
            setlistName: record.setlistName,
            planned: record.planned,
            performed: performed,
        )
    }

    /// Each item's slot row: its own row, or for a medley member its medley's first row.
    private static func slotRows(_ items: [ShowItem]) -> [Int] {
        var first: [SetlistItemID: Int] = [:]
        return items.enumerated().map { row, item in
            guard let slot = item.medley?.slot else { return row }
            if let start = first[slot] {
                return start
            }
            first[slot] = row
            return row
        }
    }

    /// The entries "Save to setlist" writes when the setlist still holds the planned
    /// entries: `entries(mergingInto: planned, including:)`.
    public func entries(including inserted: Set<ShowItemID>) -> [SetlistEntry] {
        entries(mergingInto: planned, including: inserted)
    }

    /// The entries "Save to setlist" writes (`SetlistStore.replaceEntries`), merged into the
    /// setlist as it is now (`current`, which may have been edited during the show):
    ///
    /// - entries still in `current` that the show performed take their performed order,
    ///   with their current overrides and notes;
    /// - the inserted rows in `including` (`defaultIncluded` unless the performer unticks
    ///   some) become new entries at their performed positions, except a row whose song is
    ///   already in `current` or in an earlier row (a song appears at most once per
    ///   setlist);
    /// - entries removed from the setlist during the show stay removed;
    /// - entries the show never had (added to the setlist during the show, or left out at
    ///   start because the song was missing) keep their place after the entry before them
    ///   in `current`, or stay at the end when nothing after them was performed, so Save
    ///   never drops a song. Break rows are not show items yet: each stays right before the
    ///   next performed entry that followed it, so it still opens the same part.
    public func entries(
        mergingInto current: [SetlistEntry],
        including inserted: Set<ShowItemID>,
    ) -> [SetlistEntry] {
        let currentByID = Dictionary(
            current.map { ($0.itemId, $0) },
            uniquingKeysWith: { first, _ in first },
        )
        var written = performedEntries(currentByID: currentByID, including: inserted)
        let performedIDs = Set(written.map(\.itemId))
        var present = performedIDs
        for (position, entry) in current.enumerated() where !present.contains(entry.itemId) {
            if !current[(position + 1)...].contains(where: { performedIDs.contains($0.itemId) }) {
                written.append(entry)
                present.insert(entry.itemId)
                continue
            }
            // A break row opens the part after it: it stays right before the next entry the
            // show performed, so a song moved within the part above stays above it.
            if entry.isBreak,
               let next = current[(position + 1)...].first(where: {
                   performedIDs.contains($0.itemId)
               }),
               let index = written.firstIndex(where: { $0.itemId == next.itemId })
            {
                written.insert(entry, at: index)
                present.insert(entry.itemId)
                continue
            }
            let anchor = current[..<position].last { present.contains($0.itemId) }
            let index = anchor
                .flatMap { anchor in written.firstIndex { $0.itemId == anchor.itemId } }
                .map { $0 + 1 } ?? 0
            written.insert(entry, at: index)
            present.insert(entry.itemId)
        }
        return written
    }

    /// The entries the show performed, in performed order: a medley once (its entry as it
    /// is now), inserted rows in `including` as new slots. Only plain slots block an
    /// inserted row: a medley member's song may come back as its reprise (P9-3 decision 8).
    private func performedEntries(
        currentByID: [SetlistItemID: SetlistEntry],
        including inserted: Set<ShowItemID>,
    ) -> [SetlistEntry] {
        var songs = Set(currentByID.values.compactMap(\.songId))
        var writtenMedleys: Set<SetlistItemID> = []
        return performed.compactMap { row in
            if let slot = row.item.medley?.slot, row.item.origin == .setlist {
                guard writtenMedleys.insert(slot).inserted else { return nil }
                return currentByID[slot]
            }
            if case .inserted = row.change {
                guard inserted.contains(row.item.itemId),
                      currentByID[row.item.itemId] == nil,
                      songs.insert(row.item.songId).inserted
                else { return nil }
                return SetlistEntry(
                    itemId: row.item.itemId,
                    songId: row.item.songId,
                    overrides: row.item.overrides,
                    note: row.item.note,
                    arrangement: row.item.arrangement,
                )
            }
            return currentByID[row.item.itemId]
        }
    }

    /// Whether `current` (the setlist's entries now) differs from the entries at show start,
    /// so Save merges into a setlist that was edited during the show.
    public func setlistChanged(current: [SetlistEntry]) -> Bool {
        current != planned
    }

    /// What the sheet ticks before the performer touches it: every inserted song and played
    /// request (decisions.md, phase 2 build rulings: inserted rows are checked by default),
    /// except those in `repeatedItemIds`.
    public var defaultIncluded: Set<ShowItemID> {
        Set(insertedItemIds).subtracting(repeatedItemIds)
    }

    /// Inserted rows whose song is already in the plan or in an earlier inserted row: Save
    /// never adds them (a song appears at most once per setlist), so the sheet offers no
    /// "Add to setlist" for them.
    public var repeatedItemIds: Set<ShowItemID> {
        var songs = Set(planned.compactMap(\.songId))
        var repeated: Set<ShowItemID> = []
        for row in performed {
            guard case .inserted = row.change else { continue }
            if !songs.insert(row.item.songId).inserted {
                repeated.insert(row.item.itemId)
            }
        }
        return repeated
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
