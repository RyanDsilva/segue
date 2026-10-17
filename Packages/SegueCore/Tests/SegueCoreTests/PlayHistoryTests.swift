import Foundation
import Library
import Support
import Testing

/// The play projection behind "last played" / "times played", through the real GRDB index:
/// per-show replacement, whole-set replacement, and survival across a rebuild and relaunch.
struct PlayHistoryTests {
    private struct Fixture {
        let lib: TestLibrary
        let store: LibraryStore
        let songs: [SongID]
        let base: Date

        func play(
            _ song: Int,
            show: ULID,
            at minutes: Double,
            request: Bool = false,
        ) -> PlayRecord {
            PlayRecord(
                songId: songs[song],
                showId: show,
                startedAt: base.addingTimeInterval(minutes * 60),
                endedAt: base.addingTimeInterval(minutes * 60 + 200),
                fromRequest: request,
            )
        }
    }

    private static func fixture() async throws -> Fixture {
        let lib = try TestLibrary()
        let store = try await lib.openStore()
        let songs = try await Array(0 ..< 3).asyncMap { number in
            try await store.createSong(source: "{title: Song \(number)}\nLa\n").id
        }
        // Millisecond stamps with a fractional part, as shows write them.
        let base = SegueJSON.stamp(Date(timeIntervalSince1970: 1_792_000_000.123))
        return Fixture(lib: lib, store: store, songs: songs, base: base)
    }

    @Test
    func `plays per show give times played and last played`() async throws {
        let fix = try await Self.fixture()
        let friday = fix.lib.ids.next()
        let saturday = fix.lib.ids.next()
        #expect(try await fix.store.playStats().isEmpty)

        try await fix.store.replacePlays(forShow: friday, with: [
            fix.play(0, show: friday, at: 0),
            fix.play(1, show: friday, at: 4),
            fix.play(0, show: friday, at: 8, request: true), // played twice in one show
        ])
        try await fix.store.replacePlays(forShow: saturday, with: [
            fix.play(1, show: saturday, at: 1440),
        ])

        let stats = try await fix.store.playStats()
        #expect(stats == [
            fix.songs[0]: PlayStats(timesPlayed: 2, lastPlayed: fix.base.addingTimeInterval(480)),
            fix.songs[1]: PlayStats(timesPlayed: 2, lastPlayed: fix.base.addingTimeInterval(86400)),
        ])
        #expect(stats[fix.songs[2]] == nil)

        // Re-projecting a show replaces only its plays; an empty list removes them.
        try await fix.store.replacePlays(forShow: friday, with: [fix.play(2, show: friday, at: 2)])
        #expect(try await fix.store.playStats() == [
            fix.songs[1]: PlayStats(timesPlayed: 1, lastPlayed: fix.base.addingTimeInterval(86400)),
            fix.songs[2]: PlayStats(timesPlayed: 1, lastPlayed: fix.base.addingTimeInterval(120)),
        ])
        try await fix.store.replacePlays(forShow: saturday, with: [])
        #expect(try await fix.store.playStats().keys.sorted() == [fix.songs[2]])
    }

    @Test
    func `replace all plays swaps the whole projection`() async throws {
        let fix = try await Self.fixture()
        let old = fix.lib.ids.next()
        let new = fix.lib.ids.next()
        try await fix.store.replacePlays(forShow: old, with: [fix.play(0, show: old, at: 0)])
        try await fix.store.replaceAllPlays([
            fix.play(1, show: new, at: 10),
            fix.play(2, show: new, at: 14),
        ])
        #expect(try await fix.store.playStats().keys.sorted() == [fix.songs[1], fix.songs[2]])
        try await fix.store.replaceAllPlays([])
        #expect(try await fix.store.playStats().isEmpty)
    }

    @Test
    func `the projection survives a rebuild and a relaunch`() async throws {
        let fix = try await Self.fixture()
        let show = fix.lib.ids.next()
        try await fix.store.replacePlays(forShow: show, with: [
            fix.play(0, show: show, at: 0),
            fix.play(1, show: show, at: 4),
        ])
        let expected = try await fix.store.playStats()
        #expect(expected.count == 2)

        try await fix.store.rebuildIndex()
        #expect(try await fix.store.playStats() == expected)

        // A relaunch reuses the index file, plays included (ShowStore.load re-projects too).
        let relaunched = try await fix.lib.openStore()
        #expect(try await relaunched.playStats() == expected)
        // ...and a rebuild before the shows are loaded again keeps nothing it never saw.
        try await relaunched.rebuildIndex()
        #expect(try await relaunched.playStats().isEmpty)
        try await relaunched.replaceAllPlays([fix.play(0, show: show, at: 0)])
        try await relaunched.rebuildIndex()
        #expect(try await relaunched.playStats()[fix.songs[0]]?.timesPlayed == 1)
    }

    @Test
    func `plays are stored under the show they are replaced for`() async throws {
        let fix = try await Self.fixture()
        let show = fix.lib.ids.next()
        let stray = fix.lib.ids.next()
        try await fix.store.replacePlays(forShow: show, with: [fix.play(0, show: stray, at: 0)])
        try await fix.store.replacePlays(forShow: show, with: [])
        #expect(try await fix.store.playStats().isEmpty)
    }

    @Test
    func `play history of a removed song is kept for when it comes back`() async throws {
        let fix = try await Self.fixture()
        let show = fix.lib.ids.next()
        try await fix.store.replacePlays(forShow: show, with: [fix.play(2, show: show, at: 0)])
        try FileManager.default.removeItem(at: fix.lib.url("songs/song-2.cho"))
        try await fix.store.refresh()
        #expect(try await fix.store.song(id: fix.songs[2]) == nil)
        #expect(try await fix.store.playStats()[fix.songs[2]]?.timesPlayed == 1)
    }

    @Test
    func `play history before open throws notOpen`() async throws {
        let lib = try TestLibrary()
        let store = LibraryStore(fileSystem: lib.fileSystem, clock: lib.clock, ids: lib.ids)
        await #expect(throws: LibraryError.notOpen) { try await store.playStats() }
        await #expect(throws: LibraryError.notOpen) { try await store.replaceAllPlays([]) }
    }
}
