import Foundation
import Library
import ModelPort
@testable import SetAssistant
import Setlists
import Support
import Testing

/// End to end in Core (spec 14): the seeded 300-song fixture written to a fresh library
/// through the real stores -> lexicon chips -> the async pass replayed from recorded real
/// Foundation Models answers -> accepted chips -> builder -> draft setlist written and
/// reloaded.
@Suite(.serialized)
struct SetAssistantIntegrationTests {
    /// A fresh library holding the fixture's songs (tags and proficiency in the sidecars),
    /// the play history by song, and a "Wedding set" smart filter.
    struct Loaded {
        let test: TestLibrary
        let library: LibraryStore
        let records: [SongRecord]
        let playStats: [SongID: PlayStats]
        let filters: [SmartFilter]
    }

    static func load(_ fixture: AssistantFixture = AssistantFixture()) async throws -> Loaded {
        let test = try TestLibrary()
        let library = try await test.openStore()
        var stats: [SongID: PlayStats] = [:]
        for song in fixture.songs {
            let record = try await library.createSong(source: song.source)
            try await library.updateMetadata(
                id: record.id, SongMetadata(tags: song.tags, proficiency: song.proficiency),
            )
            if let days = song.lastPlayedDaysAgo {
                stats[record.id] = PlayStats(
                    timesPlayed: 1,
                    lastPlayed: AssistantFixture.now.addingTimeInterval(-Double(days) * 86400),
                )
            }
        }
        let filterStore = SmartFilterStore(
            fileSystem: test.fileSystem,
            clock: test.clock,
            ids: test.ids,
        )
        _ = try await filterStore.load(root: test.root)
        let wedding = try await filterStore.create(
            name: "Wedding set",
            conditions: SmartFilterConditions(anyTags: ["wedding", "crowd pleaser"]),
        )
        return try await Loaded(
            test: test,
            library: library,
            records: library.allSongs(),
            playStats: stats,
            filters: [wedding],
        )
    }

    static func recordedFM() throws -> ScriptedProvider {
        let directory = try #require(Bundle.module.url(
            forResource: "fm", withExtension: nil, subdirectory: "Fixtures/setRequests/recorded",
        ))
        return try ScriptedProvider(
            id: .foundationModels,
            directory: directory,
            onMissing: { Issue.record("no recording for \($0)") },
        )
    }

    /// Instant lexicon chips, then the async pass replayed from the recorded real FM answer
    /// (slot and proficiency guesses dropped), then the suggestion accepted.
    static func chips(for text: String, lexicon: SetRequestLexicon, tags: [String])
        async throws -> SetRequest
    {
        // Instant chips.
        let parsed = lexicon.parse(text)
        #expect(parsed.chips == [.length(1800), .proficiency(.ready)])
        #expect(parsed.leftover == ["pub", "night"])
        var chips = parsed.chips.map { RequestChip($0, origin: .lexicon) }

        // The async pass: replayed real FM answer, slot and proficiency guesses dropped.
        let fm = try Self.recordedFM()
        let task = try #require(SuggestedChips.task(for: parsed, libraryTags: tags))
        let routed = await Router(providers: [fm]).run(task)
        let output = try #require(routed.output)
        let suggested = SuggestedChips.suggestions(
            from: output, words: task.words, libraryTags: tags, existing: chips,
        )
        #expect(suggested == [RequestChip(.tag("upbeat"), origin: .suggested)])
        for chip in suggested {
            chips.merge(chip)
        }
        // A suggestion applies only once accepted.
        #expect(SetRequest(chips: chips).includeTags.isEmpty)
        chips.merge(RequestChip(.tag("upbeat"), origin: .confirmed))
        let request = SetRequest(chips: chips)
        #expect(request.includeTags == ["upbeat"])
        #expect(request.proficiency == .ready)
        return request
    }

    /// Writes `draft` as a new setlist through the real store, then loads it back from disk.
    static func saveAndReload(_ draft: SetDraft, in test: TestLibrary, changeover: Int)
        async throws -> Setlist
    {
        let (setlists, _) = try await test.loadSetlists()
        let created = try await setlists.create(name: "Pub night")
        try await setlists.updateDetails(
            SetlistDetails(targetDuration: draft.target, changeoverSeconds: changeover),
            of: created.id,
        )
        try await setlists.replaceEntries(draft.entries, in: created.id)
        let (reloaded, issues) = try await test.loadSetlists()
        #expect(issues.isEmpty)
        return try #require(await reloaded.setlist(id: created.id))
    }

    @Test
    func `request to chips to suggestions to a draft written and reloaded`() async throws {
        let loaded = try await Self.load()
        let tags = try await loaded.library.allTags().map(\.tag)
        let filterNames = loaded.filters.map { SmartFilterName(id: $0.id, name: $0.name) }
        let lexicon = SetRequestLexicon(tags: tags, smartFilters: filterNames)

        let request = try await Self.chips(
            for: "30 min set, songs I know well, pub night",
            lexicon: lexicon,
            tags: tags,
        )

        // Build against the real index's records, write, reload.
        let library = AssistantLibrary(
            records: loaded.records,
            playStats: loaded.playStats,
            filters: loaded.filters,
            now: AssistantFixture.now,
        )
        let draft = SetBuilder().build(
            request,
            library: library,
            changeover: 20,
            seed: 42,
            newItemID: { SetlistItemID(loaded.test.ids.next()) },
        )
        #expect(draft.isWithinTolerance, "\(draft.timing.totalText)")
        let saved = try await Self.saveAndReload(draft, in: loaded.test, changeover: 20)
        #expect(saved.entries == draft.entries)
        #expect(saved.targetDuration == 1800)
        let byID = Dictionary(uniqueKeysWithValues: loaded.records.map { ($0.id, $0) })
        let lengths = Dictionary(uniqueKeysWithValues: saved.songEntries.compactMap { entry in
            entry.songId.flatMap { id in
                byID[id].flatMap(SetlistTiming.directiveLength(of:)).map { (id, $0) }
            }
        })
        let timing = SetlistTiming(
            entries: saved.entries,
            lengths: lengths,
            target: saved.targetDuration,
            changeover: TimeInterval(saved.changeoverSeconds ?? 0),
        )
        #expect(timing.total == draft.timing.total)
        #expect(abs(timing.total - 1800) <= 180)
        for id in saved.entries.compactMap(\.songId) {
            let record = try #require(byID[id])
            #expect(record.sidecar.tags.contains("upbeat"))
            #expect(record.sidecar.proficiency == .ready || record.sidecar.proficiency == .pro)
        }
    }

    @Test
    func `a smart filter chip narrows the set to its songs`() async throws {
        let loaded = try await Self.load()
        let filter = try #require(loaded.filters.first)
        let lexicon = SetRequestLexicon(
            tags: AssistantFixture.tags,
            smartFilters: [SmartFilterName(id: filter.id, name: filter.name)],
        )
        let request = SetRequest(kinds: lexicon.parse("from Wedding set, 25 minutes").chips)
        #expect(request.smartFilters == [filter.id])
        let library = AssistantLibrary(
            records: loaded.records,
            playStats: loaded.playStats,
            filters: loaded.filters,
            now: AssistantFixture.now,
        )
        let draft = SetBuilder().build(
            request,
            library: library,
            seed: 1,
            newItemID: { SetlistItemID(loaded.test.ids.next()) },
        )
        let allowed = try #require(library.smartFilterMatches[filter.id])
        #expect(!draft.songIDs.isEmpty)
        #expect(draft.songIDs.allSatisfy(allowed.contains))
    }

    @Test
    func `no model is asked during a show or with AI off`() async throws {
        let parsed = SetRequestLexicon(tags: AssistantFixture.tags).parse("45 min, pub night")
        let task = try #require(SuggestedChips.task(
            for: parsed,
            libraryTags: AssistantFixture.tags,
        ))
        let fm = try Self.recordedFM()
        let duringShow = await Router(providers: [fm], isShowRunning: { true }).run(task)
        #expect(duringShow.output == nil)
        #expect(duringShow.report.skipped == .duringShow)
        let aiOff = await Router(providers: [fm], isEnabled: { false }).run(task)
        #expect(aiOff.report.skipped == .aiOff)
        #expect(fm.calls.isEmpty)
        // Nothing left to map: no call at all.
        #expect(SuggestedChips.task(for: LexiconResult(chips: [.length(60)]), libraryTags: ["a"])
            == nil)
    }
}
