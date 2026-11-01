import Foundation
import Library

/// Why a medley edit was refused (P9-3 5.6).
public enum MedleyRefusal: Sendable, Equatable {
    /// A medley needs two or more songs from song slots or medleys.
    case tooFewSongs
    /// A medley holds at most `SetlistMedley.maxMembers` songs.
    case tooManyMembers
    /// Breaks never go inside a medley, and a medley never inside a medley.
    case notASongSlot(SetlistItemID)
    /// No medley or member with this ID.
    case notFound(SetlistItemID)
    /// Decision 8: the song is already in the set here (another medley, this medley, or a
    /// second plain slot).
    case duplicate(SongID, SongOccurrence)
}

/// Medley edits (P9-3 5.6). Each is one write, so each is one builder undo step; each
/// refuses (throws `SetlistError.medley`) an edit decision 8 forbids, a 13th member, or a
/// break, and then changes nothing.
public extension SetlistStore {
    /// Makes one medley from the song slots and medleys `items` (two or more songs; adjacent
    /// or not): members in set order, a selected medley's members spliced in place (with
    /// their transitions). The medley sits where the first selected row was; the other rows
    /// are removed. Song slots keep their item IDs as member IDs, so notes and arrangements
    /// stay attached. A spliced medley's title and any selected lock carry over.
    /// - Returns: the setlist and the new medley's item ID.
    @discardableResult
    func makeMedley(
        from items: [SetlistItemID],
        in id: SetlistID,
    ) throws -> (setlist: Setlist, medley: SetlistItemID) {
        let medleyId = SetlistItemID(ids.next())
        let setlist = try mutateSetlist(id) { setlist in
            let selected = Set(items)
            let rows = setlist.entries.enumerated().filter { selected.contains($0.element.itemId) }
            guard rows.count == selected.count else {
                let missing = items.first { setlist.entry($0) == nil } ?? items[0]
                throw SetlistError.medley(id, .notFound(missing))
            }
            let entry = try Self.joined(rows.map(\.element), id: medleyId, in: id)
            var remaining = setlist
            remaining.entries.removeAll { selected.contains($0.itemId) }
            try Self.checkNewMedley(entry, in: setlist, remaining: remaining, id)
            let first = rows[0].offset
            let position = setlist.entries[..<first].count { !selected.contains($0.itemId) }
            remaining.entries.insert(entry, at: position)
            setlist = remaining
        }
        return (setlist, medleyId)
    }

    /// Ungroups `medley`: its members become song slots in place, transitions dropped. A
    /// member whose song is also a plain slot elsewhere (its reprise) would make the song
    /// two slots, so that is refused.
    @discardableResult
    func ungroup(_ medley: SetlistItemID, in id: SetlistID) throws -> Setlist {
        try mutateSetlist(id) { setlist in
            let (index, value) = try Self.medley(medley, in: setlist, id)
            try Self.checkSlotsFree(value.members, excluding: medley, in: setlist, id)
            setlist.entries.replaceSubrange(index ... index, with: value.members.map(\.asSlot))
        }
    }

    /// Adds `songID` to `medley` as a new member at `offset` (nil = the end). Refused when
    /// the song is already a member of any medley or the medley is full; a song that is a
    /// plain slot elsewhere joins as its reprise.
    @discardableResult
    func addToMedley(
        _ songID: SongID,
        overrides: SetlistOverrides = SetlistOverrides(),
        medley: SetlistItemID,
        at offset: Int? = nil,
        in id: SetlistID,
    ) throws -> Setlist {
        let member = MedleyMember(
            itemId: SetlistItemID(ids.next()),
            songId: songID,
            overrides: overrides,
        )
        return try mutateSetlist(id) { setlist in
            try Self.insert(member, into: medley, at: offset, in: &setlist, id)
        }
    }

    /// Moves the song slot `item` into `medley` at `offset` (nil = the end): it keeps its
    /// item ID, overrides, note and arrangement.
    @discardableResult
    func moveIntoMedley(
        _ item: SetlistItemID,
        medley: SetlistItemID,
        at offset: Int? = nil,
        in id: SetlistID,
    ) throws -> Setlist {
        try mutateSetlist(id) { setlist in
            guard let entry = setlist.entry(item) else {
                throw SetlistError.medley(id, .notFound(item))
            }
            guard let member = MedleyMember(slot: entry) else {
                throw SetlistError.medley(id, .notASongSlot(item))
            }
            setlist.entries.removeAll { $0.itemId == item }
            try Self.insert(member, into: medley, at: offset, in: &setlist, id)
        }
    }

    /// Takes `member` out of its medley: it becomes a song slot right after the medley. A
    /// medley left with one member becomes that song's slot (auto-ungroup) in the same
    /// write.
    @discardableResult
    func removeFromMedley(_ member: SetlistItemID, in id: SetlistID) throws -> Setlist {
        try mutateSetlist(id) { setlist in
            var place = try Self.member(member, in: setlist, id)
            let removed = place.medley.members.remove(at: place.position)
            try Self.checkSlotsFree(
                [removed],
                excluding: setlist.entries[place.index].itemId,
                in: setlist,
                id,
            )
            try Self.replaceMedley(
                at: place.index,
                with: place.medley,
                appending: [removed.asSlot],
                in: &setlist,
                id,
            )
        }
    }

    /// Removes `member` from the set altogether (⌫ on a member, "Remove Song"). A medley
    /// left with one member becomes that song's slot.
    @discardableResult
    func removeMember(_ member: SetlistItemID, in id: SetlistID) throws -> Setlist {
        try mutateSetlist(id) { setlist in
            var place = try Self.member(member, in: setlist, id)
            place.medley.members.remove(at: place.position)
            try Self.replaceMedley(
                at: place.index,
                with: place.medley,
                appending: [],
                in: &setlist,
                id,
            )
        }
    }

    /// Moves `member` to `index` (its final position) within its medley. It never leaves
    /// the medley; an index outside it throws `invalidOffsets`.
    @discardableResult
    func moveMember(_ member: SetlistItemID, to index: Int, in id: SetlistID) throws -> Setlist {
        try mutateSetlist(id, writesUnchanged: false) { setlist in
            var place = try Self.member(member, in: setlist, id)
            guard place.medley.members.indices.contains(index) else {
                throw SetlistError.invalidOffsets(id)
            }
            let moving = place.medley.members.remove(at: place.position)
            place.medley.members.insert(moving, at: index)
            setlist.entries[place.index].kind = .medley(place.medley.normalized())
        }
    }

    /// Renames `medley`; a blank title clears it ("Medley").
    @discardableResult
    func renameMedley(_ medley: SetlistItemID, to title: String?, in id: SetlistID) throws
        -> Setlist
    {
        try mutateSetlist(id, writesUnchanged: false) { setlist in
            let (index, value) = try Self.medley(medley, in: setlist, id)
            var renamed = value
            renamed.title = SetlistMedley.clean(title)
            setlist.entries[index].kind = .medley(renamed.normalized())
        }
    }

    /// Sets the transition into `member` (trimmed; blank clears it; at most
    /// `SetlistMedley.maxTransitionLength` characters). The first member has none.
    @discardableResult
    func setTransition(_ text: String?, member: SetlistItemID, in id: SetlistID) throws
        -> Setlist
    {
        try mutateSetlist(id, writesUnchanged: false) { setlist in
            var place = try Self.member(member, in: setlist, id)
            place.medley.members[place.position].transition = SetlistMedley.clean(text)
                .map { String($0.prefix(SetlistMedley.maxTransitionLength)) }
            setlist.entries[place.index].kind = .medley(place.medley.normalized())
        }
    }

    /// Replaces the overrides, note and arrangement of the member with `member.itemId` (its
    /// song and transition stay): the member's slot popover and arrangement editor.
    @discardableResult
    func updateMember(_ member: MedleyMember, in id: SetlistID) throws -> Setlist {
        try mutateSetlist(id) { setlist in
            var place = try Self.member(member.itemId, in: setlist, id)
            place.medley.members[place.position].overrides = member.overrides
            place.medley.members[place.position].note = member.note
            place.medley.members[place.position].arrangement = member.arrangement
            setlist.entries[place.index].kind = .medley(place.medley.normalized())
        }
    }

    /// Replaces the overrides, note and arrangement of the song slot or member with
    /// `itemId`: one path for both (`Setlist.songSlot(_:)`).
    @discardableResult
    func updateSongSlot(
        _ itemId: SetlistItemID,
        overrides: SetlistOverrides,
        note: String?,
        arrangement: SlotArrangement?,
        in id: SetlistID,
    ) throws -> Setlist {
        guard let current = setlist(id: id) else { throw SetlistError.setlistNotFound(id) }
        switch current.songSlot(itemId) {
        case let .entry(entry):
            var entry = entry
            entry.overrides = overrides
            entry.note = note
            entry.arrangement = arrangement
            return try updateEntry(entry, in: id)
        case let .member(_, member):
            var member = member
            member.overrides = overrides
            member.note = note
            member.arrangement = arrangement
            return try updateMember(member, in: id)
        case nil:
            throw SetlistError.invalidOffsets(id)
        }
    }

    // MARK: - Private

    /// The medley made of `rows` (song slots and medleys, in set order).
    private static func joined(
        _ rows: [SetlistEntry],
        id medleyId: SetlistItemID,
        in id: SetlistID,
    ) throws -> SetlistEntry {
        var members: [MedleyMember] = []
        var title: String?
        for entry in rows {
            switch entry.kind {
            case .song:
                members += MedleyMember(slot: entry).map { [$0] } ?? []
            case let .medley(medley):
                title = title ?? medley.title
                members += medley.members
            case .break:
                throw SetlistError.medley(id, .notASongSlot(entry.itemId))
            }
        }
        guard rows.count >= 2, members.count >= 2 else {
            throw SetlistError.medley(id, .tooFewSongs)
        }
        guard members.count <= SetlistMedley.maxMembers else {
            throw SetlistError.medley(id, .tooManyMembers)
        }
        return SetlistEntry(
            itemId: medleyId,
            medley: SetlistMedley(title: title, members: members),
            locked: rows.contains(where: \.locked),
        )
    }

    /// Decision 8 over a new medley: no song twice in it, none in another medley.
    private static func checkNewMedley(
        _ entry: SetlistEntry,
        in setlist: Setlist,
        remaining: Setlist,
        _ id: SetlistID,
    ) throws {
        let members = entry.medley?.members ?? []
        for (index, member) in members.enumerated() {
            if let twin = members[..<index].first(where: { $0.songId == member.songId }),
               let occurrence = setlist.occurrences(of: twin.songId)
                   .first(where: { $0.itemId == twin.itemId })
            {
                throw SetlistError.medley(id, .duplicate(member.songId, occurrence))
            }
            let verdict = remaining.canAdd(member.songId, as: .member(of: entry.itemId))
            if case let .refused(occurrence) = verdict {
                throw SetlistError.medley(id, .duplicate(member.songId, occurrence))
            }
        }
    }

    /// `entry` with its medley's members given new item IDs, leaving out `dropping` (a
    /// duplicated setlist; repeated members are not copied).
    internal func copiedMembers(of entry: SetlistEntry, dropping: Set<SetlistItemID>)
        -> SetlistEntry
    {
        guard var medley = entry.medley else { return entry }
        medley.members = medley.members.filter { !dropping.contains($0.itemId) }.map { member in
            var member = member
            member.itemId = SetlistItemID(ids.next())
            return member
        }
        var copy = entry
        copy.kind = .medley(medley.normalized())
        return copy
    }

    /// Where a member sits: its medley's entry index, the medley, and its position in it.
    private struct MemberPlace {
        var index: Int
        var medley: SetlistMedley
        var position: Int
    }

    private static func medley(
        _ itemId: SetlistItemID,
        in setlist: Setlist,
        _ id: SetlistID,
    ) throws -> (index: Int, medley: SetlistMedley) {
        guard let index = setlist.entries.firstIndex(where: { $0.itemId == itemId }),
              let medley = setlist.entries[index].medley
        else {
            throw SetlistError.medley(id, .notFound(itemId))
        }
        return (index, medley)
    }

    private static func member(
        _ itemId: SetlistItemID,
        in setlist: Setlist,
        _ id: SetlistID,
    ) throws -> MemberPlace {
        for (index, entry) in setlist.entries.enumerated() {
            if let medley = entry.medley,
               let position = medley.members.firstIndex(where: { $0.itemId == itemId })
            {
                return MemberPlace(index: index, medley: medley, position: position)
            }
        }
        throw SetlistError.medley(id, .notFound(itemId))
    }

    /// Inserts `member` into `medley` after the decision 8 and size checks.
    private static func insert(
        _ member: MedleyMember,
        into medley: SetlistItemID,
        at offset: Int?,
        in setlist: inout Setlist,
        _ id: SetlistID,
    ) throws {
        let (index, value) = try Self.medley(medley, in: setlist, id)
        guard value.members.count < SetlistMedley.maxMembers else {
            throw SetlistError.medley(id, .tooManyMembers)
        }
        if case let .refused(occurrence) = setlist.canAdd(member.songId, as: .member(of: medley)) {
            throw SetlistError.medley(id, .duplicate(member.songId, occurrence))
        }
        let position = offset ?? value.members.count
        guard (0 ... value.members.count).contains(position) else {
            throw SetlistError.invalidOffsets(id)
        }
        var grown = value
        grown.members.insert(member, at: position)
        setlist.entries[index].kind = .medley(grown.normalized())
    }

    /// Writes `medley` back at `index`, followed by `appending` slots; a medley left with
    /// one member becomes that song's slot (auto-ungroup, decision 9) and an empty one is
    /// removed.
    private static func replaceMedley(
        at index: Int,
        with medley: SetlistMedley,
        appending slots: [SetlistEntry],
        in setlist: inout Setlist,
        _ id: SetlistID,
    ) throws {
        let entry = setlist.entries[index]
        var rows: [SetlistEntry]
        switch medley.members.count {
        case 0:
            rows = []
        case 1:
            try checkSlotsFree(medley.members, excluding: entry.itemId, in: setlist, id)
            var slot = medley.members[0].asSlot
            slot.locked = entry.locked
            rows = [slot]
        default:
            var kept = entry
            kept.kind = .medley(medley.normalized())
            rows = [kept]
        }
        rows += slots
        setlist.entries.replaceSubrange(index ... index, with: rows)
    }

    /// Refuses turning `members` into plain slots when one's song is already a plain slot
    /// (decision 8: a song is never two slots).
    private static func checkSlotsFree(
        _ members: [MedleyMember],
        excluding medley: SetlistItemID,
        in setlist: Setlist,
        _ id: SetlistID,
    ) throws {
        for member in members {
            let slot = setlist.occurrences(of: member.songId).first { occurrence in
                !occurrence.isMember && occurrence.itemId != medley
            }
            if let slot {
                throw SetlistError.medley(id, .duplicate(member.songId, slot))
            }
        }
    }
}
