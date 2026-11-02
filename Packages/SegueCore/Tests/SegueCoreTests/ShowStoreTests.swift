import Foundation
import Library
import Setlists
import Shows
import Support
import Testing

/// `ShowStore` and the gig log on a real temp library.
struct ShowStoreTests {
    /// Plays two shows; returns the harness and both endings (oldest first).
    private struct TwoGigs {
        var harness: ShowHarness
        var endings: [ShowEnding]
        var songs: [SongRecord]
    }

    private func twoGigs() async throws -> TwoGigs {
        let harness = try await ShowHarness()
        let (setlist, songs) = try await harness.makeSet(3)
        var endings: [ShowEnding] = []
        for _ in 0 ..< 2 {
            let show = try await ShowController.start(
                setlist: setlist,
                kind: .gig,
                environment: harness.environment(),
            )
            harness.lib.clock.advance(by: 240)
            try await show.perform(.next)
            harness.lib.clock.advance(by: 200)
            try await endings.append(show.end())
            harness.lib.clock.advance(by: 86400)
        }
        return TwoGigs(harness: harness, endings: endings, songs: songs)
    }

    @Test
    func `gig log lists newest first and edits persist`() async throws {
        let gigs = try await twoGigs()
        let (harness, endings, songs) = (gigs.harness, gigs.endings, gigs.songs)
        let log = await harness.shows.gigLog()
        #expect(log.map(\.id) == endings.reversed().map(\.record.id))
        #expect(log.first?.played.map(\.item.title) == ["Song 1", "Song 2"])
        let stats = try await harness.library.playStats()
        #expect(stats[songs[0].id]?.timesPlayed == 2)
        #expect(stats[songs[2].id] == nil)

        let id = endings[0].record.id
        let details = GigDetails(
            venue: "  The Anchor ",
            date: CalendarDay("2026-10-24"),
            notes: " ",
            rating: 4,
        )
        let updated = try await harness.shows.updateGigDetails(details, of: id)
        #expect(updated.gig == GigDetails(
            venue: "The Anchor",
            date: CalendarDay("2026-10-24"),
            rating: 4,
        ))
        await #expect(throws: ShowError.invalidRating(6)) {
            try await harness.shows.updateGigDetails(GigDetails(rating: 6), of: id)
        }
        try await harness.relaunch()
        #expect(await harness.shows.show(id: id)?.gig == updated.gig)
        // Played times survive a relaunch (projection rebuilt from the files).
        #expect(try await harness.library.playStats()[songs[0].id]?.timesPlayed == 2)

        try await harness.shows.delete(id)
        #expect(!harness.lib.exists(harness.showPath(id)))
        #expect(harness.lib.trashedNames() == ["\(id)\(LibraryRoot.showSuffix)"])
        #expect(await harness.shows.gigLog().map(\.id) == [endings[1].record.id])
        #expect(try await harness.library.playStats()[songs[0].id]?.timesPlayed == 1)
        await #expect(throws: ShowError.showNotFound(id)) {
            try await harness.shows.delete(id)
        }
    }

    @Test
    func `unfinished shows cannot be edited in the gig log`() async throws {
        let harness = try await ShowHarness()
        let (setlist, _) = try await harness.makeSet(2)
        let show = try await ShowController.start(
            setlist: setlist,
            kind: .gig,
            environment: harness.environment(),
        )
        let id = await show.state.record.id
        await #expect(throws: ShowError.notFinished(id)) {
            try await harness.shows.updateGigDetails(GigDetails(rating: 3), of: id)
        }
        let unloaded = ShowStore(
            fileSystem: harness.fileSystem,
            clock: harness.lib.clock,
            playHistory: nil,
        )
        await #expect(throws: ShowError.notLoaded) {
            try await unloaded.save(show.state.record)
        }
    }

    /// Unreadable files are reported and left alone; a show from a newer Segue opens
    /// read-only (listed, never rewritten or resumed).
    @Test
    func `unreadable and newer show files are reported, never rewritten`() async throws {
        let gigs = try await twoGigs()
        let (harness, endings) = (gigs.harness, gigs.endings)
        let newerPath = harness.showPath(endings[1].record.id)
        let original = try harness.lib.read(newerPath)
        let newer = original.replacingOccurrences(
            of: "\"schemaVersion\" : \(ShowRecord.currentSchemaVersion)",
            with: "\"schemaVersion\" : 9",
        )
        try harness.lib.write(newer, to: newerPath)
        let brokenID = ShowID(harness.lib.ids.next())
        try harness.lib.write("{ not json", to: harness.showPath(brokenID))

        let store = ShowStore(
            fileSystem: harness.fileSystem,
            clock: harness.lib.clock,
            playHistory: nil,
        )
        let issues = try await store.load(root: harness.lib.root, state: harness.lib.state)
        #expect(issues.map(\.relativePath) == [harness.showPath(brokenID)])
        let readOnly = try #require(await store.show(id: endings[1].record.id))
        #expect(readOnly.readOnly == .newerSchema(
            found: 9,
            supported: ShowRecord.currentSchemaVersion,
        ))
        #expect(await store.gigLog().count == 2)
        await #expect(throws: ShowError.readOnly(
            readOnly.id,
            .newerSchema(found: 9, supported: ShowRecord.currentSchemaVersion),
        )) {
            try await store.updateGigDetails(GigDetails(rating: 2), of: readOnly.id)
        }
        #expect(try harness.lib.read(newerPath) == newer)
        #expect(try harness.lib.read(harness.showPath(brokenID)) == "{ not json")
    }

    @Test
    func `show file has the expected shape`() async throws {
        let harness = try await ShowHarness()
        let (setlist, _) = try await harness.makeSet(1)
        let show = try await ShowController.start(
            setlist: setlist,
            kind: .gig,
            environment: harness.environment(),
        )
        harness.lib.clock.advance(by: 61.5)
        let record = try await show.end().record
        let json = try harness.lib.read(harness.showPath(record.id))
        let object = try #require(
            JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any],
        )
        // `currentItemId` is absent once the show has ended.
        #expect(Set(object.keys) == [
            "closure", "endedAt", "events", "gig", "id", "items", "kind", "planned",
            "requests", "schemaVersion", "scrollPosition", "setlistId", "setlistName",
            "startedAt", "updatedAt",
        ])
        #expect(object["endedAt"] as? String == "2026-01-01T00:01:01.500Z")
        #expect(object["kind"] as? String == "gig")
        #expect((object["gig"] as? [String: Any])?["date"] as? String == "2026-10-23")
        #expect(json.hasSuffix("}\n"))
    }
}

/// Pure logic: the planned-vs-performed diff.
struct ReorderDiffTests {
    private func record(_ order: [Int], inserted: Set<Int> = [], planned count: Int) -> ShowRecord {
        let ids = (0 ..< max(count, (order.max() ?? 0) + 1)).map { index in
            ShowItemID(ULID(
                milliseconds: 1,
                randomness: [UInt8](repeating: UInt8(index), count: 10),
            ))
        }
        let planned = (0 ..< count)
            .map { SetlistEntry(itemId: ids[$0], songId: SongID(ids[$0].ulid)) }
        let items = order.map { index in
            ShowItem(
                itemId: ids[index],
                songId: SongID(ids[index].ulid),
                title: "\(index)",
                origin: inserted.contains(index) ? .request : .setlist,
            )
        }
        let now = Date(timeIntervalSince1970: 0)
        return ShowRecord(
            id: ShowID(ULID(milliseconds: 9, randomness: [UInt8](repeating: 9, count: 10))),
            kind: .gig,
            setlistId: SetlistID(ULID(
                milliseconds: 8,
                randomness: [UInt8](repeating: 8, count: 10),
            )),
            setlistName: "Set",
            planned: planned,
            items: items,
            currentItemId: nil,
            startedAt: now,
            updatedAt: now,
        )
    }

    @Test
    func `planned order with nothing inserted has no diff`() {
        #expect(ReorderDiff.compute(record([0, 1, 2, 3], planned: 4)) == nil)
    }

    @Test
    func `only items outside the longest kept run are moved`() throws {
        // 7 dragged to the front: everything else keeps planned order.
        let diff = try #require(ReorderDiff.compute(record([7, 0, 1, 2, 3, 4, 5, 6], planned: 8)))
        #expect(diff.performed.map(\.change) == [.moved(fromPosition: 7)] + Array(
            repeating: .unchanged,
            count: 7,
        ))
        let swapped = try #require(ReorderDiff.compute(record([1, 0, 3, 2], planned: 4)))
        #expect(swapped.performed.filter { $0.change != .unchanged }.count == 2)
        let saved = swapped.entries(including: [])
        #expect(saved.map(\.itemId) == swapped.performed.map(\.item.itemId))
    }

    @Test
    func `inserted rows are written only when included`() throws {
        let diff = try #require(ReorderDiff.compute(record(
            [0, 4, 1, 2, 3],
            inserted: [4],
            planned: 4,
        )))
        #expect(diff.performed[1].change == .inserted(.request))
        #expect(diff.entries(including: []).map(\.itemId) == diff.planned.map(\.itemId))
        #expect(diff.entries(including: diff.defaultIncluded).map(\.itemId)
            == diff.performed.map(\.item.itemId))
    }
}
