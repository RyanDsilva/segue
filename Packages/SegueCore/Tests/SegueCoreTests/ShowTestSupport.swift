import Foundation
import Library
import Setlists
import Shows
import Support

/// A real temp library wired for shows: real `LibraryStore` (GRDB index, parser), real
/// `SetlistStore` and `ShowStore` on the same folder, a frozen clock and seeded IDs.
/// `relaunch()` drops the stores and opens fresh ones, as a new process would after a kill.
final class ShowHarness {
    let lib: TestLibrary
    let fileSystem: any FileSystem
    var library: LibraryStore
    var setlists: SetlistStore
    var shows: ShowStore

    init(seed: UInt64 = 7, fileSystem: (any FileSystem)? = nil) async throws {
        lib = try TestLibrary(seed: seed)
        self.fileSystem = fileSystem ?? lib.fileSystem
        library = try await lib.openStore(fileSystem: self.fileSystem)
        setlists = SetlistStore(fileSystem: self.fileSystem, clock: lib.clock, ids: lib.ids)
        shows = ShowStore(fileSystem: self.fileSystem, clock: lib.clock, playHistory: library)
        try await loadStores()
    }

    private func loadStores() async throws {
        try await setlists.load(root: lib.root)
        try await shows.load(root: lib.root)
    }

    /// Fresh stores on the same folder ("kill -9, relaunch").
    func relaunch() async throws {
        library = try await lib.openStore(fileSystem: fileSystem)
        setlists = SetlistStore(fileSystem: fileSystem, clock: lib.clock, ids: lib.ids)
        shows = ShowStore(fileSystem: fileSystem, clock: lib.clock, playHistory: library)
        try await loadStores()
    }

    func environment() -> ShowEnvironment {
        ShowEnvironment(store: shows, songs: library, clock: lib.clock, ids: lib.ids)
    }

    /// Creates `count` songs titled "Song 1"... and a setlist of them, in order.
    func makeSet(
        _ count: Int,
        name: String = "Friday - The Anchor",
    ) async throws -> (Setlist, [SongRecord]) {
        var songs: [SongRecord] = []
        for number in 1 ... count {
            try await songs.append(song("Song \(number)"))
        }
        var setlist = try await setlists.create(name: name)
        setlist = try await setlists.insertSongs(songs.map(\.id), into: setlist.id)
        setlist = try await setlists.updateDetails(
            SetlistDetails(venue: "The Anchor", date: CalendarDay("2026-10-23")),
            of: setlist.id,
        )
        return (setlist, songs)
    }

    func song(_ title: String, line: String = "[G]Hello [C]there") async throws -> SongRecord {
        try await library.createSong(source: "{title: \(title)}\n{key: G}\n\(line)\n")
    }

    /// The show file as a fresh store reads it back.
    func reloadedShow(_ id: ShowID) async throws -> ShowRecord? {
        let store = ShowStore(fileSystem: fileSystem, clock: lib.clock, playHistory: nil)
        try await store.load(root: lib.root)
        return await store.show(id: id)
    }

    func showPath(_ id: ShowID) -> String {
        "shows/\(id)\(LibraryRoot.showSuffix)"
    }
}

extension ShowState {
    var currentTitle: String? {
        current?.item.title
    }

    func titles(_ state: ItemState) -> [String] {
        record.items.filter { $0.state == state }.map(\.title)
    }
}

/// Deterministic random numbers for the property test (SplitMix64).
struct SeededGenerator: RandomNumberGenerator {
    var state: UInt64

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var mixed = state
        mixed = (mixed ^ (mixed >> 30)) &* 0xBF58_476D_1CE4_E5B9
        mixed = (mixed ^ (mixed >> 27)) &* 0x94D0_49BB_1331_11EB
        return mixed ^ (mixed >> 31)
    }
}

extension PlayedSong {
    /// How long the engine recorded the song as current (its start and end stamps; the
    /// gig log no longer shows it per song, R174).
    var elapsed: TimeInterval {
        endedAt.timeIntervalSince(startedAt)
    }
}
