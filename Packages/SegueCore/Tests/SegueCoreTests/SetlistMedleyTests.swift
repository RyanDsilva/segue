import Foundation
import Library
import Setlists
import Support
import Testing

/// The medley slot model (P9-3 5.1-5.3): codec, lenient decoding, counts, song slots and
/// the decision 8 reprise rule.
struct SetlistMedleyTests {
    private static func song(_ index: Int) -> SongID {
        SongID(ULID(milliseconds: 1, randomness: Array(repeating: UInt8(index), count: 10)))
    }

    private static func item(_ index: Int) -> SetlistItemID {
        SetlistItemID(ULID(milliseconds: 2, randomness: Array(repeating: UInt8(index), count: 10)))
    }

    private static func member(_ index: Int, song: Int, transition: String? = nil)
        -> MedleyMember
    {
        MedleyMember(itemId: item(index), songId: Self.song(song), transition: transition)
    }

    private static func medley(_ id: Int, songs: [Int], title: String? = nil) -> SetlistEntry {
        SetlistEntry(
            itemId: item(id),
            medley: SetlistMedley(
                title: title,
                members: songs.enumerated().map { offset, song in
                    member(id * 10 + offset + 1, song: song, transition: "into \(song)")
                },
            ),
        )
    }

    private static func slot(_ id: Int, song: Int) -> SetlistEntry {
        SetlistEntry(itemId: item(id), songId: Self.song(song))
    }

    private static func setlist(_ entries: [SetlistEntry]) -> Setlist {
        Setlist(
            id: SetlistID(ULID(milliseconds: 9, randomness: Array(repeating: 9, count: 10))),
            name: "Friday",
            entries: entries,
        )
    }

    @Test
    func `a medley round-trips with empty keys omitted and the first transition dropped`()
        throws
    {
        var medley = Self.medley(4, songs: [1, 2, 3], title: "  Love medley ")
        if case var .medley(value) = medley.kind {
            value.members[0].overrides = SetlistOverrides(transpose: 2)
            value.members[2].note = "Last chorus twice"
            medley.kind = .medley(value)
        }
        medley.locked = true
        let data = try SegueJSON.encode(medley)
        let json = try #require(String(data: data, encoding: .utf8))

        #expect(json.contains("\"title\" : \"Love medley\""))
        #expect(json.contains("\"locked\" : true"))
        #expect(!json.contains("into 1"))
        #expect(json.contains("into 2"))
        #expect(!json.contains("\"songId\" : \"\(medley.itemId)"))
        // A member with nothing set writes only its IDs (and its transition).
        #expect(json.components(separatedBy: "\"overrides\"").count == 2)
        let decoded = try SegueJSON.decode(SetlistEntry.self, from: data)
        #expect(decoded == medley)
        #expect(decoded.medley?.members.map(\.songId) == [1, 2, 3].map(Self.song))
        #expect(decoded.medley?.displayTitle == "Love medley")
        #expect(decoded.songId == nil)
        #expect(decoded.songIds == [1, 2, 3].map(Self.song))
    }

    @Test
    func `decoding is lenient: unknown keys, unreadable members and blank texts`() throws {
        let json = """
        {"itemId": "\(Self.item(4))", "medley": {"title": "  ", "colour": "red",
          "members": [
            {"itemId": "\(Self.item(41))", "songId": "\(Self.song(1))", "mood": 3},
            {"itemId": "\(Self.item(42))"},
            {"songId": "\(Self.song(2))"},
            {"itemId": "\(Self.item(43))", "songId": "\(Self.song(3))", "transition": "  "}
          ]}}
        """
        let entry = try SegueJSON.decode(SetlistEntry.self, from: Data(json.utf8))
        let medley = try #require(entry.medley)
        #expect(medley.title == nil)
        #expect(medley.displayTitle == "Medley")
        #expect(medley.members.map(\.itemId) == [Self.item(41), Self.item(43)])
        #expect(medley.members.allSatisfy { $0.transition == nil })
    }

    @Test
    func `one-member and empty medleys load as saved`() throws {
        for count in [0, 1] {
            let members = (0 ..< count).map {
                "{\"itemId\": \"\(Self.item(41 + $0))\", \"songId\": \"\(Self.song(1))\"}"
            }
            let list = members.joined(separator: ",")
            let json = """
            {"itemId": "\(Self.item(4))", "medley": {"members": [\(list)]}}
            """
            let entry = try SegueJSON.decode(SetlistEntry.self, from: Data(json.utf8))
            #expect(entry.medley?.members.count == count)
            #expect(entry.isMedley)
        }
    }

    @Test
    func `counts: songs count members, slots count rows, songIds are distinct`() {
        let list = Self.setlist([
            Self.slot(1, song: 7),
            Self.medley(2, songs: [1, 2, 3]),
            SetlistEntry(itemId: Self.item(3), break: SetlistBreak(label: "Set 2")),
            Self.slot(4, song: 1),
        ])
        #expect(list.songCount == 5)
        #expect(list.slotCount == 3)
        #expect(list.songIds == [7, 1, 2, 3].map(Self.song))
        #expect(list.slotNumbers[Self.item(4)] == 3)
        #expect(list.member(Self.item(22))?.index == 1)
        #expect(list.songSlot(Self.item(22)) == .member(
            entryId: Self.item(2),
            Self.member(22, song: 2, transition: "into 2"),
        ))
        #expect(list.songSlot(Self.item(1)) == .entry(Self.slot(1, song: 7)))
        #expect(list.songSlot(Self.item(2)) == nil)
        #expect(list.songSlot(Self.item(3)) == nil)
        #expect(list.occurrences(of: Self.song(1)) == [
            .member(entryId: Self.item(2), itemId: Self.item(21), label: "2a"),
            .slot(Self.item(4), number: 3),
        ])
    }

    struct AddCase: CustomTestStringConvertible, Sendable {
        var name: String
        var entries: [SetlistEntry]
        var song: Int
        var role: AddRole
        var verdict: AddVerdict

        var testDescription: String {
            name
        }
    }

    static let addCases: [AddCase] = [
        AddCase(
            name: "new song as a slot",
            entries: [slot(1, song: 1)],
            song: 2,
            role: .slot,
            verdict: .ok,
        ),
        AddCase(
            name: "a second slot is refused",
            entries: [slot(1, song: 1)],
            song: 1,
            role: .slot,
            verdict: .refused(.slot(item(1), number: 1)),
        ),
        AddCase(
            name: "a slot reprising a member",
            entries: [medley(1, songs: [1, 2])],
            song: 1,
            role: .slot,
            verdict: .reprise(of: .member(entryId: item(1), itemId: item(11), label: "1a")),
        ),
        AddCase(
            name: "a member reprising a slot",
            entries: [slot(1, song: 3), medley(2, songs: [1, 2])],
            song: 3,
            role: .member(of: item(2)),
            verdict: .reprise(of: .slot(item(1), number: 1)),
        ),
        AddCase(
            name: "twice in one medley is refused",
            entries: [medley(1, songs: [1, 2])],
            song: 2,
            role: .member(of: item(1)),
            verdict: .refused(.member(entryId: item(1), itemId: item(12), label: "1b")),
        ),
        AddCase(
            name: "two medleys sharing a song is refused",
            entries: [medley(1, songs: [1, 2]), medley(2, songs: [3, 4])],
            song: 2,
            role: .member(of: item(2)),
            verdict: .refused(.member(entryId: item(1), itemId: item(12), label: "1b")),
        ),
        AddCase(
            name: "a third occurrence as a slot is refused",
            entries: [medley(1, songs: [1, 2]), slot(2, song: 1)],
            song: 1,
            role: .slot,
            verdict: .refused(.slot(item(2), number: 2)),
        ),
    ]

    @Test(arguments: addCases)
    func `canAdd follows decision 8`(row: AddCase) {
        #expect(Self.setlist(row.entries).canAdd(Self.song(row.song), as: row.role)
            == row.verdict)
    }

    @Test
    func `repeatedEntries allows the reprise and marks everything else`() {
        let list = Self.setlist([
            Self.medley(1, songs: [1, 2, 1]),
            Self.slot(2, song: 1),
            Self.medley(3, songs: [2, 5]),
            Self.slot(4, song: 5),
            Self.slot(5, song: 5),
        ])
        // 1c repeats 1a in one medley, 3a repeats 1b in another medley, slot 5 repeats
        // slot 4. Slot 2 (reprise of 1a) and slot 4 (reprise of 3b) are fine.
        #expect(list.repeatedEntries == [Self.item(13), Self.item(31), Self.item(5)])
    }
}

/// Medley slot time (P9-3 7, R172, R173): the members' sum, no changeover inside, lower
/// bound and "~" rules, per-member unknown counts.
struct MedleyTimeTests {
    private static func known(_ seconds: TimeInterval, estimated: Bool = false) -> SlotTime {
        .known(seconds: seconds, bars: 1, tempo: 96, estimated: estimated)
    }

    private static func item(_ index: Int) -> SetlistItemID {
        SetlistItemID(ULID(milliseconds: 3, randomness: Array(repeating: UInt8(index), count: 10)))
    }

    private static func song(_ index: Int) -> SongID {
        SongID(ULID(milliseconds: 4, randomness: Array(repeating: UInt8(index), count: 10)))
    }

    private static func medley(_ id: Int, members: Int) -> SetlistEntry {
        SetlistEntry(itemId: item(id), medley: SetlistMedley(members: (0 ..< members).map {
            MedleyMember(itemId: item(id * 10 + $0 + 1), songId: song(id * 10 + $0))
        }))
    }

    struct Row: CustomTestStringConvertible, Sendable {
        var name: String
        var members: [SlotTime]
        var clock: String
        var unknown: [Int]

        var testDescription: String {
            name
        }
    }

    static let rows: [Row] = [
        Row(
            name: "all known",
            members: [known(160), known(130), known(170)],
            clock: "7:40",
            unknown: [],
        ),
        Row(
            name: "one unknown",
            members: [known(160), .unknown(.noTempo), known(170)],
            clock: "5:30",
            unknown: [1],
        ),
        Row(
            name: "estimated",
            members: [known(160, estimated: true), known(300)],
            clock: "~7:40",
            unknown: [],
        ),
        Row(
            name: "estimated and unknown",
            members: [
                known(330, estimated: true),
                .unknown(.missingSong),
            ],
            clock: "~5:30",
            unknown: [1],
        ),
        Row(
            name: "none known",
            members: [.unknown(.noTempo), .unknown(.noChords)],
            clock: "--:--",
            unknown: [0, 1],
        ),
    ]

    @Test(arguments: rows)
    func `medley time`(row: Row) {
        let time = MedleyTime(members: row.members)
        #expect(time.clock == row.clock)
        #expect(time.unknownMembers == row.unknown)
    }

    @Test
    func `help and VoiceOver text`() {
        let all = MedleyTime(members: [Self.known(160), Self.known(130), Self.known(170)])
        #expect(all.help(titles: ["Kesariya", "Tum Hi Ho", "Channa Mereya"])
            == "Kesariya 2:40, Tum Hi Ho 2:10, Channa Mereya 2:50")
        #expect(all.spoken == "7 minutes 40 seconds, medley of 3 songs")
        let some = MedleyTime(members: [Self.known(160), .unknown(.noTempo), Self.known(170)])
        #expect(some.help(titles: []) == "1 of 3 songs has no time: no tempo")
        #expect(some.spoken == "5 minutes 30 seconds so far, incomplete: 1 song has no time")
    }

    @Test
    func `a missing member is unknown with missingSong`() throws {
        let record = try SlotTimeTests.record("{tempo: 120}\n[G]a [C]b\n")
        let time = SlotTimes.medley([(record, nil), (nil, nil)])
        #expect(time.members[1] == .unknown(.missingSong))
        #expect(time.members[0].seconds != nil)
        #expect(time.unknownMembers == [1])
    }

    @Test
    func `in a set: no changeover inside, one after, members as unknowns, lower bounds after`()
        throws
    {
        let entries = [
            SetlistEntry(itemId: Self.item(1), songId: Self.song(1)),
            Self.medley(2, members: 3),
            SetlistEntry(itemId: Self.item(3), songId: Self.song(3)),
            SetlistEntry(itemId: Self.item(4), break: SetlistBreak(label: "Set 2")),
            Self.medley(5, members: 2),
        ]
        let timing = SetlistTiming(
            entries: entries,
            times: [Self.item(1): Self.known(100), Self.item(3): Self.known(200)],
            medleyTimes: [
                Self.item(2): MedleyTime(members: [
                    Self.known(60),
                    .unknown(.noTempo),
                    Self.known(40, estimated: true),
                ]),
                Self.item(5): MedleyTime(members: [Self.known(50), Self.known(70)]),
            ],
            target: nil,
            changeover: 30,
        )
        #expect(timing.items.map(\.timeText) == ["1:40", "~1:40", "3:20", "--:--", "2:00"])
        // 100 + 30 + (60 + 40) + 30 + 200 = 460; part 2: 120.
        #expect(timing.parts.map(\.total) == [460, 120])
        #expect(timing.total == 580)
        #expect(timing.unknownCount == 1)
        #expect(timing.unknownItemIds == [Self.item(22)])
        #expect(timing.isEstimated)
        let medley = try #require(timing.items[1].medley)
        #expect(medley.members.map(\.start) == [130, 190, 190])
        #expect(medley.members.map(\.startIsApproximate) == [false, false, true])
        #expect(timing.items[2].start == 260)
        #expect(timing.items[2].startIsApproximate)
        #expect(timing.member(Self.item(23))?.timeText == "~0:40")
    }

    @Test
    func `an empty medley is left out of timing`() {
        let entries = [
            SetlistEntry(itemId: Self.item(1), songId: Self.song(1)),
            Self.medley(2, members: 0),
            SetlistEntry(itemId: Self.item(3), songId: Self.song(3)),
        ]
        let timing = SetlistTiming(
            entries: entries,
            times: [Self.item(1): Self.known(100), Self.item(3): Self.known(200)],
            target: nil,
            changeover: 30,
        )
        #expect(timing.total == 330)
        #expect(timing.unknownCount == 0)
    }
}
