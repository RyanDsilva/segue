import Foundation
import Library

/// A medley slot (P9-3): two or more songs played as one block, with written transitions
/// between them. It lives in its setlist slot (like an arrangement, R122), never in the
/// library.
public struct SetlistMedley: Sendable, Hashable, Codable {
    /// The most members a medley may hold (decision 9).
    public static let maxMembers = 12
    /// The longest transition text the builder accepts (P9-3 6.2).
    public static let maxTransitionLength = 280

    /// Shown in the builder, on stage and in the Gig Log; nil = "Medley".
    public var title: String?
    public var members: [MedleyMember]

    public init(title: String? = nil, members: [MedleyMember]) {
        self.title = Self.clean(title)
        self.members = members
    }

    /// "Medley" when untitled; the title trimmed otherwise.
    public var displayTitle: String {
        Self.clean(title) ?? "Medley"
    }

    /// The member titles joined " / ".
    public static func memberLine(_ titles: [String]) -> String {
        titles.joined(separator: " / ")
    }

    /// The members' songs, in order.
    public var songIds: [SongID] {
        members.map(\.songId)
    }

    /// The same medley with the first member's transition cleared (it is ignored and never
    /// written, decision 3) and blank texts read as nil. Every store operation saves this.
    public func normalized() -> Self {
        var copy = self
        copy.title = Self.clean(title)
        for index in copy.members.indices {
            copy.members[index].transition = index == 0
                ? nil
                : Self.clean(copy.members[index].transition)
        }
        return copy
    }

    /// Nil for nil, empty or whitespace text; the text trimmed otherwise.
    public static func clean(_ text: String?) -> String? {
        guard let trimmed = text?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty
        else {
            return nil
        }
        return trimmed
    }

    private enum CodingKeys: String, CodingKey {
        case title
        case members
    }

    /// Lenient (P9-3 5.3): a member without a readable `itemId` or `songId` is dropped; an
    /// unknown key is ignored; a blank title or transition reads as nil.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let title = try? container.decodeIfPresent(String.self, forKey: .title)
        let lenient = (try? container.decodeIfPresent([LenientMember].self, forKey: .members))
            ?? []
        self.init(title: title, members: lenient.compactMap(\.member))
        self = normalized()
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        let medley = normalized()
        try container.encodeIfPresent(medley.title, forKey: .title)
        try container.encode(medley.members, forKey: .members)
    }

    private struct LenientMember: Decodable {
        var member: MedleyMember?

        init(from decoder: any Decoder) throws {
            member = try? MedleyMember(from: decoder)
        }
    }
}

/// One song in a medley: everything a song slot has, plus the transition into it.
public struct MedleyMember: Sendable, Hashable, Codable, Identifiable {
    /// Stable and unique in the setlist; also the show item's ID.
    public var itemId: SetlistItemID
    public var songId: SongID
    /// Key and capo for this member.
    public var overrides: SetlistOverrides
    /// Its slot note (the stage's notes block).
    public var note: String?
    /// Its slot arrangement (R122, R149); nil = the full song.
    public var arrangement: SlotArrangement?
    /// Written between the previous member and this one ("into this member"); ignored for
    /// the first member.
    public var transition: String?

    public var id: SetlistItemID {
        itemId
    }

    public init(
        itemId: SetlistItemID,
        songId: SongID,
        overrides: SetlistOverrides = SetlistOverrides(),
        note: String? = nil,
        arrangement: SlotArrangement? = nil,
        transition: String? = nil,
    ) {
        self.itemId = itemId
        self.songId = songId
        self.overrides = overrides
        self.note = note
        self.arrangement = arrangement
        self.transition = transition
    }

    /// A member made from a song slot: the slot's item ID, overrides, note and arrangement
    /// stay attached (P9-3 5.2). Nil for a break or a medley.
    public init?(slot entry: SetlistEntry) {
        guard let song = entry.songId else { return nil }
        self.init(
            itemId: entry.itemId,
            songId: song,
            overrides: entry.overrides,
            note: entry.note,
            arrangement: entry.arrangement,
        )
    }

    /// The song slot this member becomes on ungroup or removal (its transition dropped).
    public var asSlot: SetlistEntry {
        SetlistEntry(
            itemId: itemId,
            songId: songId,
            overrides: overrides,
            note: note,
            arrangement: arrangement,
        )
    }

    private enum CodingKeys: String, CodingKey {
        case itemId
        case songId
        case overrides
        case note
        case arrangement
        case transition
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        itemId = try container.decode(SetlistItemID.self, forKey: .itemId)
        songId = try container.decode(SongID.self, forKey: .songId)
        overrides = (try? container.decodeIfPresent(SetlistOverrides.self, forKey: .overrides))
            .flatMap(\.self) ?? SetlistOverrides()
        note = try? container.decodeIfPresent(String.self, forKey: .note)
        arrangement = try? container.decodeIfPresent(SlotArrangement.self, forKey: .arrangement)
        transition = SetlistMedley.clean(
            try? container.decodeIfPresent(String.self, forKey: .transition),
        )
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(itemId, forKey: .itemId)
        try container.encode(songId, forKey: .songId)
        if !overrides.isEmpty {
            try container.encode(overrides, forKey: .overrides)
        }
        try container.encodeIfPresent(note, forKey: .note)
        try container.encodeIfPresent(arrangement, forKey: .arrangement)
        try container.encodeIfPresent(SetlistMedley.clean(transition), forKey: .transition)
    }
}

// MARK: - Song slots, occurrences and the reprise rule (decision 8)

/// A song slot or a medley member, edited the same way (the slot popover, the arrangement
/// editor, "Rehearse this").
public enum SongSlotRef: Sendable, Hashable {
    case entry(SetlistEntry)
    case member(entryId: SetlistItemID, MedleyMember)

    public var itemId: SetlistItemID {
        switch self {
        case let .entry(entry): entry.itemId
        case let .member(_, member): member.itemId
        }
    }

    public var songId: SongID? {
        switch self {
        case let .entry(entry): entry.songId
        case let .member(_, member): member.songId
        }
    }

    public var overrides: SetlistOverrides {
        switch self {
        case let .entry(entry): entry.overrides
        case let .member(_, member): member.overrides
        }
    }

    public var note: String? {
        switch self {
        case let .entry(entry): entry.note
        case let .member(_, member): member.note
        }
    }

    public var arrangement: SlotArrangement? {
        switch self {
        case let .entry(entry): entry.arrangement
        case let .member(_, member): member.arrangement
        }
    }

    /// The medley slot holding this member; nil for a plain slot.
    public var medleyId: SetlistItemID? {
        if case let .member(entryId, _) = self {
            return entryId
        }
        return nil
    }

    /// A song entry with this slot's song, overrides, note and arrangement (a member as if
    /// it were a slot; its item ID kept): what single-song code paths read.
    public var asEntry: SetlistEntry? {
        switch self {
        case let .entry(entry): entry.songId == nil ? nil : entry
        case let .member(_, member): member.asSlot
        }
    }
}

/// Where a song sits in a setlist.
public enum SongOccurrence: Sendable, Hashable {
    /// A plain song slot, numbered as the builder numbers it (1-based, breaks unnumbered).
    case slot(SetlistItemID, number: Int)
    /// A medley member: the medley's slot ID, the member's item ID and its label ("4b").
    case member(entryId: SetlistItemID, itemId: SetlistItemID, label: String)

    /// The item ID of the slot or member.
    public var itemId: SetlistItemID {
        switch self {
        case let .slot(id, _): id
        case let .member(_, id, _): id
        }
    }

    /// "9" or "4b": how the builder and composer name it.
    public var label: String {
        switch self {
        case let .slot(_, number): "\(number)"
        case let .member(_, _, label): label
        }
    }

    public var isMember: Bool {
        if case .member = self {
            return true
        }
        return false
    }
}

/// The role a song would take in a setlist.
public enum AddRole: Sendable, Hashable {
    /// A plain song slot.
    case slot
    /// A member of the medley with this slot ID.
    case member(of: SetlistItemID)
}

/// Whether a song may be added in a role (decision 8).
public enum AddVerdict: Sendable, Hashable {
    /// Not in the set yet.
    case ok
    /// Allowed as the medley reprise: the song is already in the set at this occurrence.
    case reprise(of: SongOccurrence)
    /// Refused: the song is already in the set here in a way decision 8 forbids.
    case refused(SongOccurrence)

    public var isAllowed: Bool {
        if case .refused = self {
            return false
        }
        return true
    }
}

public extension SetlistEntry {
    /// The medley this slot holds; nil for a song or a break.
    var medley: SetlistMedley? {
        if case let .medley(medley) = kind {
            return medley
        }
        return nil
    }

    /// Whether this slot is a medley.
    var isMedley: Bool {
        medley != nil
    }

    /// The songs this row plays: a song slot its song, a medley its members in order, a
    /// break none.
    var songIds: [SongID] {
        switch kind {
        case let .song(id): [id]
        case .break: []
        case let .medley(medley): medley.songIds
        }
    }
}

public extension Setlist {
    /// The rows that are songs or medleys (breaks left out): what the builder numbers.
    var slotCount: Int {
        entries.count { !$0.isBreak }
    }

    /// Each entry's 1-based slot number (nil for a break): songs and medleys count 1 ... n
    /// across parts.
    var slotNumbers: [SetlistItemID: Int] {
        var count = 0
        var numbers: [SetlistItemID: Int] = [:]
        for entry in entries where !entry.isBreak {
            count += 1
            numbers[entry.itemId] = count
        }
        return numbers
    }

    /// The member label "4b": the medley's slot number and the member's letter (a ... l).
    static func memberLabel(slot number: Int, index: Int) -> String {
        let letters = Array("abcdefghijklmnopqrstuvwxyz")
        let letter = index < letters.count ? String(letters[index]) : "\(index + 1)"
        return "\(number)\(letter)"
    }

    /// Every song slot and medley member in set order, with its number as the builder shows
    /// it ("3", "4b"): what plays, one song each.
    var songSlotLabels: [(slot: SongSlotRef, label: String)] {
        var number = 0
        var result: [(slot: SongSlotRef, label: String)] = []
        for entry in entries where !entry.isBreak {
            number += 1
            if let medley = entry.medley {
                for (index, member) in medley.members.enumerated() {
                    result.append((
                        .member(entryId: entry.itemId, member),
                        Self.memberLabel(slot: number, index: index),
                    ))
                }
            } else {
                result.append((.entry(entry), "\(number)"))
            }
        }
        return result
    }

    /// The medley member with `itemId` and its index, if present.
    func member(_ itemId: SetlistItemID) -> (entry: SetlistEntry, index: Int)? {
        for entry in entries {
            if let index = entry.medley?.members.firstIndex(where: { $0.itemId == itemId }) {
                return (entry, index)
            }
        }
        return nil
    }

    /// The song slot or medley member with `itemId`: a member edits exactly like a slot.
    func songSlot(_ itemId: SetlistItemID) -> SongSlotRef? {
        if let entry = entry(itemId), entry.songId != nil {
            return .entry(entry)
        }
        if let (entry, index) = member(itemId), let medley = entry.medley {
            return .member(entryId: entry.itemId, medley.members[index])
        }
        return nil
    }

    /// Every song slot and member holding `song`, in set order.
    func occurrences(of song: SongID) -> [SongOccurrence] {
        var number = 0
        var found: [SongOccurrence] = []
        for entry in entries where !entry.isBreak {
            number += 1
            switch entry.kind {
            case let .song(id) where id == song:
                found.append(.slot(entry.itemId, number: number))
            case let .medley(medley):
                for (index, member) in medley.members.enumerated() where member.songId == song {
                    found.append(.member(
                        entryId: entry.itemId,
                        itemId: member.itemId,
                        label: Self.memberLabel(slot: number, index: index),
                    ))
                }
            default:
                break
            }
        }
        return found
    }

    /// The one place decision 8 is written. A song appears at most twice in a set: once as
    /// a medley member and once as a plain slot (the reprise). A second slot, a second
    /// medley, or a second time in one medley is refused.
    func canAdd(_ song: SongID, as role: AddRole) -> AddVerdict {
        let found = occurrences(of: song)
        let slot = found.first { !$0.isMember }
        let member = found.first(where: \.isMember)
        switch role {
        case .slot:
            if let slot {
                return .refused(slot)
            }
            return member.map { .reprise(of: $0) } ?? .ok
        case .member:
            if let member {
                return .refused(member)
            }
            return slot.map { .reprise(of: $0) } ?? .ok
        }
    }

    /// Whether `song` is a plain slot of this setlist (the Pick tick, the "In set" mark).
    func hasSlot(for song: SongID) -> Bool {
        entries.contains { $0.songId == song }
    }

    /// The medley holding `song` as a member, if any.
    func medley(containing song: SongID) -> SetlistEntry? {
        entries.first { $0.medley?.songIds.contains(song) ?? false }
    }
}
