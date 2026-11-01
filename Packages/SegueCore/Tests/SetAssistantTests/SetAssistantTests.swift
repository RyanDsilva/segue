import Foundation
import Library
@testable import SetAssistant
import Setlists
import Support
import Testing

/// The builder over the seeded 300-song fixture (spec 7, 14): property checks over many
/// seeds, Rebuild around locks and break rows, and the breakdown arithmetic.
struct SetAssistantTests {
    static let fixture = AssistantFixture()
    static let lexicon = SetRequestLexicon(tags: AssistantFixture.tags)
    static let requests = [
        "30 min set, songs I know well",
        "45 min, no covers, finish big",
        "an hour, upbeat start, under 140 bpm",
        "10 songs in G or D or Em",
        "20 minutes of hindi songs I know cold",
        "40 mins including learning, end with a ballad",
    ]
    static let seeds: [UInt64] = Array(1 ... 25)

    static func build(
        _ text: String,
        seed: UInt64,
        layout: RebuildLayout = .empty,
        changeover: TimeInterval = 30,
    ) -> (SetRequest, SetDraft) {
        let request = SetRequest(kinds: lexicon.parse(text).chips)
        let draft = SetBuilder().build(
            request,
            library: fixture.library,
            layout: layout,
            changeover: changeover,
            seed: seed,
            newItemID: AssistantFixture.itemIDs(seed: seed),
        )
        return (request, draft)
    }

    @Test(arguments: requests)
    func `properties hold over many seeds`(_ text: String) {
        let library = Self.fixture.library
        let songs = Dictionary(uniqueKeysWithValues: library.songs.map { ($0.id, $0) })
        for seed in Self.seeds {
            let (request, draft) = Self.build(text, seed: seed)
            let ids = draft.songIDs
            #expect(Set(ids).count == ids.count, "a song twice (seed \(seed))")
            #expect(draft.isWithinTolerance, "\(draft.timing.totalText) (seed \(seed))")
            for id in ids {
                guard let song = songs[id] else {
                    Issue.record("unknown song \(id)")
                    continue
                }
                #expect(SetBuilder.admits(song, request, smartFilterMatches: [:]))
                if request.proficiency != .anything {
                    #expect(song.proficiency != .learning, "Learning picked (seed \(seed))")
                }
                if draft.target != nil {
                    #expect(song.time != nil, "no-time song packed (seed \(seed))")
                }
            }
            // Changeover counted: times + 30 s between songs (one part).
            if draft.target != nil {
                let times = ids.compactMap { songs[$0]?.time }.reduce(0, +)
                #expect(abs(draft.timing.total - (times + 30 * Double(max(ids.count - 1, 0))))
                    < 1e-6)
            }
            // Breakdowns: one per song slot, every signal listed, summing to the total.
            #expect(draft.breakdowns.count == ids.count)
            for breakdown in draft.breakdowns.values {
                #expect(breakdown.contributions.map(\.signal) == ScoreSignal.allCases)
                let sum = breakdown.contributions.map(\.value).reduce(0, +)
                #expect(abs(sum - breakdown.total) < 1e-12)
            }
            // Same seed, same set.
            #expect(Self.build(text, seed: seed).1 == draft)
        }
    }

    @Test
    func `different seeds offer different sets`() {
        let sets = Set(Self.seeds.map { Self.build("30 min set", seed: $0).1.songIDs })
        #expect(sets.count > 5)
    }

    @Test
    func `songs with no time are left out of a length target and named`() {
        let (request, draft) = Self.build("30 min set", seed: 1)
        let library = Self.fixture.library
        let expected = library.songs
            .filter { $0.time == nil && SetBuilder.admits($0, request, smartFilterMatches: [:]) }
        #expect(!expected.isEmpty)
        #expect(Set(draft.leftOutNoTime) == Set(expected.map(\.id)))
        // A count request packs them (no length target).
        let (_, counted) = Self.build("40 songs", seed: 1)
        #expect(counted.leftOutNoTime.isEmpty)
        #expect(counted.songIDs.count == 40)
    }

    @Test
    func `opener and closer tags only when asked (R92)`() throws {
        for seed in Self.seeds {
            let (_, draft) = Self.build("45 min, upbeat start, finish big", seed: seed)
            let first = try #require(draft.songIDs.first.flatMap(Self.fixture.song))
            let last = try #require(draft.songIDs.last.flatMap(Self.fixture.song))
            #expect(first.tags.contains("upbeat"))
            #expect(last.tags.contains("crowd pleaser"))
            let opener = try #require(draft.breakdowns[draft.entries[0].itemId])
            #expect(opener.value(of: .slot) == AssistantConfig.standard.weights.slot)
        }
        let (_, plain) = Self.build("45 min", seed: 3)
        #expect(plain.breakdowns.values.allSatisfy { $0.value(of: .slot) == 0 })
    }

    @Test
    func `tempo filters and never scores (R92)`() throws {
        let (request, draft) = Self.build("an hour under 120 bpm", seed: 4)
        #expect(request.tempo == TempoRange(max: 120))
        for id in draft.songIDs {
            let tempo = Self.fixture.song(id)?.tempo
            #expect(try tempo != nil && #require(tempo) <= 120)
        }
        #expect(ScoreSignal.allCases.allSatisfy { $0.rawValue != "tempo" })
    }

    @Test
    func `key flow avoids the same key back to back`() {
        var sameKeyPairs = 0
        var pairs = 0
        for seed in Self.seeds {
            let (_, draft) = Self.build("an hour", seed: seed)
            let keys = draft.songIDs.map { Self.fixture.song($0)?.key }
            for (left, right) in zip(keys, keys.dropFirst()) where left != nil {
                pairs += 1
                sameKeyPairs += left == right ? 1 : 0
            }
        }
        // 15 keys at random would repeat about 1 pair in 15; flow keeps it near zero.
        #expect(Double(sameKeyPairs) / Double(pairs) < 0.02)
    }

    @Test(arguments: Array(seeds.prefix(10)))
    func `rebuild keeps locked songs and break rows in place`(seed: UInt64) throws {
        let (_, first) = Self.build("an hour, songs I know well", seed: seed)
        var entries = first.entries
        let ids = AssistantFixture.itemIDs(seed: seed + 1000)
        let breakEntry = SetlistEntry(itemId: ids(), break: SetlistBreak(label: "Set 2"))
        let breakAt = entries.count / 2
        entries.insert(breakEntry, at: breakAt)
        let locked: Set = [entries[1].itemId, entries[entries.count - 2].itemId]
        let layout = RebuildLayout(entries: entries, locked: locked)

        let (_, rebuilt) = Self.build("an hour, songs I know well", seed: seed + 1, layout: layout)
        for (index, entry) in entries.enumerated() where locked.contains(entry.itemId) {
            #expect(rebuilt.entries.firstIndex(of: entry) == index)
        }
        #expect(rebuilt.entries.contains(breakEntry))
        let breakIndex = try #require(rebuilt.entries.firstIndex(of: breakEntry))
        #expect(breakIndex == breakAt)
        #expect(Set(rebuilt.songIDs).count == rebuilt.songIDs.count)
        #expect(rebuilt.isWithinTolerance, "\(rebuilt.timing.totalText)")
        // Changeovers within each part only.
        let times = rebuilt.songIDs.compactMap { Self.fixture.song($0)?.seconds }.reduce(0, +)
        let parts = rebuilt.timing.parts.filter { !$0.songItemIds.isEmpty }.count
        #expect(abs(rebuilt.timing.total
                - (times + 30 * Double(rebuilt.songIDs.count - parts))) < 1e-6)
    }

    @Test
    func `locks are saved in the setlist and Rebuild honours them after reopening (R115)`()
        async throws
    {
        let test = try TestLibrary()
        let (store, _) = try await test.loadSetlists()
        let created = try await store.create(name: "Locks")
        let (_, first) = Self.build("an hour", seed: 2)
        try await store.replaceEntries(first.entries, in: created.id)
        let pinned: Set = [first.entries[0].itemId, first.entries[3].itemId]
        try await store.setLocked(pinned, true, in: created.id)
        #expect(try test.read("setlists/locks.setlist.json").contains("\"locked\" : true"))

        let (reopened, _) = try await test.loadSetlists()
        let saved = try #require(await reopened.setlist(id: created.id))
        #expect(Set(saved.entries.filter(\.locked).map(\.itemId)) == pinned)
        let (_, rebuilt) = Self.build(
            "an hour",
            seed: 77,
            layout: RebuildLayout(entries: saved.entries),
        )
        #expect(rebuilt.entries[0] == saved.entries[0])
        #expect(rebuilt.entries[3] == saved.entries[3])
        #expect(rebuilt.entries.filter(\.locked).count == 2)
        try await reopened.setLocked([saved.entries[0].itemId], false, in: created.id)
        #expect(await reopened.setlist(id: created.id)?.entries.filter(\.locked).count == 1)
    }

    @Test
    func `rebuild keeps a re-picked song's item, overrides and note`() {
        let (_, first) = Self.build("30 min set", seed: 9)
        var entries = first.entries
        entries[0].note = "start soft"
        entries[0].overrides = SetlistOverrides(transpose: 2)
        let (_, rebuilt) = Self.build(
            "30 min set",
            seed: 9,
            layout: RebuildLayout(entries: entries),
        )
        let kept = rebuilt.entries.first { $0.songId == entries[0].songId }
        #expect(kept == nil || kept == entries[0])
    }

    @Test
    func `rebuild keeps an arranged slot whole (R122)`() throws {
        let (_, first) = Self.build("an hour, songs I know well", seed: 4)
        var entries = first.entries
        let anchor = SectionAnchor.section(SectionRef(label: "Chorus", occurrence: 1))
        entries[1].arrangement = SlotArrangement(
            passes: [ArrangementPass(anchor: anchor), ArrangementPass(anchor: anchor)],
        )
        entries[1].locked = true
        let (_, rebuilt) = Self.build(
            "an hour, songs I know well",
            seed: 5,
            layout: RebuildLayout(entries: entries),
        )
        #expect(rebuilt.entries[1] == entries[1])
        let slot = try #require(rebuilt.timing.items.first { $0.itemId == entries[1].itemId })
        #expect(slot.time?.source == .arrangement)
    }

    @Test
    func `a request no song meets builds an empty set and says so`() {
        let (_, draft) = Self.build("30 min of hindi in Bb under 61 bpm I know cold", seed: 1)
        #expect(draft.matchingCount < 3)
        #expect(!draft.isWithinTolerance)
    }

    @Test
    func `the breakdown names its reasons`() {
        let song = AssistantSong(
            id: SongID(ULIDGenerator(clock: ManualClock(), seed: 1).next()),
            title: "One",
            tags: ["Upbeat"],
            proficiency: .pro,
            lastPlayed: AssistantFixture.now.addingTimeInterval(-30 * 86400),
        )
        let scorer = Scorer(
            config: .standard,
            request: SetRequest(includeTags: ["upbeat", "rock"], openerTag: "upbeat"),
            now: AssistantFixture.now,
        )
        let breakdown = scorer.score(song, in: SlotContext(isOpener: true))
        #expect(breakdown.contribution(of: .proficiency)?.reason == "Pro")
        #expect(breakdown.contribution(of: .tags)?.reason == "1 of 2 tags")
        #expect(breakdown.contribution(of: .recent)?.reason == "Played 30 days ago")
        #expect(abs(breakdown.value(of: .recent) + 0.8 * 0.5) < 1e-9)
        #expect(breakdown.contribution(of: .slot)?.reason == "Opens with upbeat")
        #expect(abs(breakdown.total - (1.0 + 0.5 - 0.4 + 1.5)) < 1e-9)
    }

    @Test
    func `config files override only what they name`() throws {
        let json = #"{"weights": {"proficiency": 2, "tags": 1, "recent": 0, "slot": 1, "#
            + #""keyFlow": 1, "variety": 0}, "toleranceSeconds": 60}"#
        let data = Data(json.utf8)
        let config = try AssistantConfig.decode(data)
        #expect(config.weights.proficiency == 2)
        #expect(config.toleranceSeconds == 60)
        #expect(config.recentHalfLifeDays == AssistantConfig.standard.recentHalfLifeDays)
    }
}

/// Medleys and the reprise in the set assistant (P9-3 11, R178, R181).
struct SetAssistantMedleyTests {
    /// A first build with slots 1 ... 3 made into a medley (unlocked) and the medley's first
    /// song added again at the end as an unlocked reprise, plus a locked reprise of its
    /// last song.
    private struct Layout {
        var layout: RebuildLayout
        var medley: SetlistEntry
        var members: [SongID]
    }

    private static func layout(seed: UInt64) -> Layout {
        let (_, first) = SetAssistantTests.build("an hour, songs I know well", seed: seed)
        var entries = first.entries
        let ids = AssistantFixture.itemIDs(seed: seed + 500)
        let members = entries[1 ... 3].compactMap { MedleyMember(slot: $0) }
        let medley = SetlistEntry(itemId: ids(), medley: SetlistMedley(members: members))
        entries.replaceSubrange(1 ... 3, with: [medley])
        let unlocked = SetlistEntry(itemId: ids(), songId: members[0].songId)
        var locked = SetlistEntry(itemId: ids(), songId: members[2].songId)
        locked.locked = true
        entries += [unlocked, locked]
        return Layout(
            layout: RebuildLayout(entries: entries),
            medley: medley,
            members: members.map(\.songId),
        )
    }

    @Test(arguments: [UInt64(3), 8, 13])
    func `rebuild keeps the medley in place and drops only the unlocked reprise`(seed: UInt64)
        throws
    {
        let fixture = Self.layout(seed: seed)
        let (layout, medley, members) = (fixture.layout, fixture.medley, fixture.members)
        let (_, rebuilt) = SetAssistantTests.build(
            "an hour, songs I know well",
            seed: seed + 1,
            layout: layout,
        )
        #expect(rebuilt.entries[1] == medley)
        // Member songs are never candidates for another slot; the locked reprise stays.
        let slotSongs = rebuilt.entries.compactMap(\.songId)
        #expect(!slotSongs.contains(members[0]))
        #expect(!slotSongs.contains(members[1]))
        #expect(slotSongs.filter { $0 == members[2] }.count == 1)
        #expect(rebuilt.leftOutReprises == [members[0]])
        // Time counts the medley's members, one changeover after it.
        let item = try #require(rebuilt.timing.items.first { $0.itemId == medley.itemId })
        let sum = members.compactMap { SetAssistantTests.fixture.song($0)?.seconds }.reduce(0, +)
        #expect(item.time.map { abs($0.seconds - sum) < 1e-6 } ?? (sum == 0))
        #expect(rebuilt.songIDs.filter { $0 == members[2] }.count == 2)
    }

    @Test
    func `flow runs into the medley's first member and on from its last`() throws {
        let fixture = Self.layout(seed: 21)
        let (layout, medley, members) = (fixture.layout, fixture.medley, fixture.members)
        let (_, rebuilt) = SetAssistantTests.build("an hour", seed: 22, layout: layout)
        let index = try #require(rebuilt.entries.firstIndex(of: medley))
        let after = try #require(rebuilt.entries[(index + 1)...].first { $0.songId != nil })
        let breakdown = try #require(rebuilt.breakdowns[after.itemId])
        let songs = Dictionary(
            SetAssistantTests.fixture.library.songs.map { ($0.id, $0) },
        ) { first, _ in first }
        let last = try #require(songs[members[2]])
        let next = try #require(after.songId.flatMap { songs[$0] })
        let scorer = Scorer(config: .standard, request: SetRequest(), now: Date(), variety: [:])
        let flow = scorer.flow(from: last, to: next).1
        #expect(flow.isEmpty || breakdown.contributions.contains { $0.reason == flow })
        #expect(rebuilt.breakdowns[medley.itemId] == nil)
    }
}
