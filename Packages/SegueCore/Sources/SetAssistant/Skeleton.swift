// The set assistant's skeleton (P3-7, R115; P9-3 11): what Rebuild keeps in place and the
// free slots it packs.

import Foundation
import Library
import Setlists

// MARK: - Skeleton

/// The shape a set is packed into: Rebuild's locked songs, every medley (P9-3 11, locked or
/// not, members unchanged) and break rows stay put, the other song slots are free. A new
/// set is all free slots.
struct Skeleton {
    enum Position: Equatable {
        case fixed(SetlistEntry, AssistantSong?)
        /// A medley: flow runs into its first member and on from its last (P9-3 11).
        case medley(SetlistEntry, first: AssistantSong?, last: AssistantSong?)
        case breakRow(SetlistEntry)
        case free

        static func == (lhs: Self, rhs: Self) -> Bool {
            switch (lhs, rhs) {
            case let (.fixed(left, _), .fixed(right, _)): left == right
            case let (.medley(left, _, _), .medley(right, _, _)): left == right
            case let (.breakRow(left), .breakRow(right)): left == right
            case (.free, .free): true
            default: false
            }
        }
    }

    private let positions: [Position]
    /// Songs in locked slots and every medley member: never picked again (the assistant
    /// never makes a reprise, P9-3 11).
    let lockedSongs: Set<SongID>
    /// Unlocked entries by song: a song picked again keeps its item ID, overrides and note.
    private let reusable: [SongID: SetlistEntry]
    /// Locked songs' and medleys' known times plus break intermissions.
    let fixedTime: TimeInterval
    /// Locked and medley slots (each one slot for changeovers).
    let lockedCount: Int
    /// The songs in locked slots and medleys (a medley counts its members toward a song
    /// count).
    let lockedSongCount: Int
    let partCount: Int
    /// Unlocked reprise slots of a medley member: Rebuild leaves them out ("lock it to keep
    /// it", R181), in set order.
    let droppedReprises: [SongID]

    init(
        layout: RebuildLayout,
        songs: [SongID: AssistantSong],
        medleyTimes: [SetlistItemID: MedleyTime] = [:],
    ) {
        var positions: [Position] = []
        var lockedSlots: Set<SongID> = []
        var members: Set<SongID> = []
        var reusable: [SongID: SetlistEntry] = [:]
        var fixed: TimeInterval = 0
        var slots = 0
        var songCount = 0
        for entry in layout.entries {
            if let medley = entry.medley {
                members.formUnion(medley.songIds)
            }
        }
        var dropped: [SongID] = []
        for entry in layout.entries {
            if let info = entry.breakInfo {
                positions.append(.breakRow(entry))
                fixed += max(info.length ?? 0, 0)
            } else if entry.isMedley {
                guard let position = Self.medleyPosition(entry, songs: songs) else { continue }
                positions.append(position)
                fixed += Self.medleyTime(entry, songs: songs, times: medleyTimes)
                slots += 1
                songCount += entry.songIds.count
            } else if let id = entry.songId, layout.locked.contains(entry.itemId),
                      !lockedSlots.contains(id)
            {
                lockedSlots.insert(id)
                positions.append(.fixed(entry, songs[id]))
                fixed += songs[id]?.time ?? 0
                slots += 1
                songCount += 1
            } else {
                if let id = entry.songId, members.contains(id) {
                    dropped.append(id)
                } else if let id = entry.songId, reusable[id] == nil {
                    reusable[id] = entry
                }
                positions.append(.free)
            }
        }
        let locked = lockedSlots.union(members)
        self.positions = positions
        lockedSongs = locked
        self.reusable = reusable.filter { !locked.contains($0.key) }
        fixedTime = fixed
        lockedCount = slots
        lockedSongCount = songCount
        partCount = layout.entries.count(where: \.isBreak) + 1
        droppedReprises = dropped
    }

    /// A medley's position, flowing in through its first member and out through its last;
    /// nil for an empty medley.
    private static func medleyPosition(_ entry: SetlistEntry, songs: [SongID: AssistantSong])
        -> Position?
    {
        guard let first = entry.songIds.first, let last = entry.songIds.last else { return nil }
        return .medley(entry, first: songs[first], last: songs[last])
    }

    /// A medley's known time: its `MedleyTime`, else its members' own times.
    private static func medleyTime(
        _ entry: SetlistEntry,
        songs: [SongID: AssistantSong],
        times: [SetlistItemID: MedleyTime],
    ) -> TimeInterval {
        times[entry.itemId]?.known ?? entry.songIds.reduce(0) { $0 + (songs[$1]?.time ?? 0) }
    }

    /// The positions for `count` new songs: the existing free slots, the last ones dropped
    /// when fewer songs are picked, extra ones appended at the end of the set when more are.
    func positions(for count: Int) -> [Position] {
        let free = positions.count(where: { $0 == .free })
        if count >= free {
            return positions + Array(repeating: .free, count: count - free)
        }
        var drop = free - count
        var result = positions
        for index in result.indices.reversed() where drop > 0 && result[index] == .free {
            result.remove(at: index)
            drop -= 1
        }
        return result
    }

    /// How many free song slots the layout has.
    var freeCount: Int {
        positions.count(where: { $0 == .free })
    }

    /// Whether the set's first song slot is free (with at least one new song).
    var opensFree: Bool {
        positions(for: max(freeCount, 1)).first { !$0.isBreak } == .free
    }

    /// Whether the set's last song slot is free (with at least one new song).
    var closesFree: Bool {
        positions(for: max(freeCount, 1)).last { !$0.isBreak } == .free
    }

    /// The setlist entries with `songs` in the free positions, in order.
    func entries(
        filling songs: [AssistantSong],
        newItemID: () -> SetlistItemID,
    ) -> [SetlistEntry] {
        var queue = songs[...]
        return positions(for: songs.count).compactMap { position in
            switch position {
            case let .breakRow(entry), let .fixed(entry, _), let .medley(entry, _, _):
                return entry
            case .free:
                guard let song = queue.popFirst() else { return nil }
                return reusable[song.id] ?? SetlistEntry(itemId: newItemID(), songId: song.id)
            }
        }
    }

    /// Estimated set total with `picked` new songs: times, intermissions and a changeover
    /// between songs of a part (each part assumed to hold a song).
    func total(times: TimeInterval, songs: Int, changeover: TimeInterval) -> TimeInterval {
        let all = songs + lockedCount
        let gaps = max(all - min(partCount, all), 0)
        return fixedTime + times + changeover * TimeInterval(gaps)
    }
}

extension Skeleton.Position {
    var isBreak: Bool {
        if case .breakRow = self {
            return true
        }
        return false
    }
}
