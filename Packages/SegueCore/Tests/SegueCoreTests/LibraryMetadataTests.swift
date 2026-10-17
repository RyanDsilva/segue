import Foundation
import Library
import SQLite3
import Support
import Testing

/// Phase 2 library metadata on a real library folder: tags, proficiency, notes and cues in
/// the sidecar, tag search through the real GRDB index (romanized-Hindi variants included),
/// live prefs, single-song reload and the index version bump.
struct LibraryMetadataTests {
    private static let pyaar = """
    {title: Pyaar Ka Safar}
    {artist: Fixture Band}
    [G]Dil mein tera [C]pyaar hai

    """

    private static let river = """
    {title: River Song}
    {artist: The Fixtures}
    [C]Down by the [G]water

    """

    @Test
    func `update metadata writes the sidecar only and survives a relaunch`() async throws {
        let lib = try TestLibrary()
        let store = try await lib.openStore()
        let song = try await store.createSong(source: Self.pyaar)
        let choBefore = try lib.read(song.relativePath)
        let choDate = try FileManager.default
            .attributesOfItem(atPath: lib.url(song.relativePath).path)[.modificationDate] as? Date

        lib.clock.advance(by: 120)
        let cue = SongCue(section: "Chorus", occurrence: 2, text: "watch Ravi for the stop")
        let metadata = SongMetadata(
            tags: ["  Sangeet ", "upbeat", "", "UPBEAT", "slow\n  burn", "   "],
            proficiency: .ready,
            notes: "Capo on 2 for Priya",
            cues: [cue],
        )
        let updated = try await store.updateMetadata(id: song.id, metadata)

        #expect(updated.sidecar.tags == ["Sangeet", "upbeat", "slow burn"])
        #expect(updated.sidecar.proficiency == .ready)
        #expect(updated.sidecar.notes == "Capo on 2 for Priya")
        #expect(updated.sidecar.cues == [cue])
        #expect(updated.sidecar.updatedAt == SegueJSON.stamp(lib.clock.now()))
        #expect(updated.revision.contentHash == song.revision.contentHash)
        #expect(updated.revision.sidecarHash != song.revision.sidecarHash)
        #expect(try lib.read(song.relativePath) == choBefore)
        let choAfter = try FileManager.default
            .attributesOfItem(atPath: lib.url(song.relativePath).path)[.modificationDate] as? Date
        #expect(choAfter == choDate)

        let sidecar = try lib.read("songs/pyaar-ka-safar.segue.json")
        #expect(sidecar.contains("\"proficiency\" : \"ready\""))
        #expect(sidecar.contains("\"text\" : \"watch Ravi for the stop\""))

        let relaunched = try await lib.openStore()
        let reloaded = try #require(try await relaunched.song(id: song.id))
        #expect(SongMetadata(reloaded.sidecar) == SongMetadata(updated.sidecar))
        #expect(try await relaunched.refresh() == RefreshSummary())

        // Blank notes are saved as none; clearing everything round-trips.
        let cleared = try await relaunched.updateMetadata(id: song.id, SongMetadata(notes: " \n"))
        #expect(SongMetadata(cleared.sidecar) == SongMetadata())
        #expect(try !(lib.read("songs/pyaar-ka-safar.segue.json").contains("notes")))
    }

    @Test
    func `quick search matches tags, romanized-Hindi variants included`() async throws {
        let lib = try TestLibrary()
        let store = try await lib.openStore()
        let pyaar = try await store.createSong(source: Self.pyaar)
        let river = try await store.createSong(source: Self.river)

        #expect(try await store.search(query: "sangeet").isEmpty)
        try await store.updateMetadata(id: river.id, SongMetadata(tags: ["Sangeet", "Upbeat"]))
        try await store.updateMetadata(id: pyaar.id, SongMetadata(tags: ["Deewana Mood"]))

        #expect(try await store.search(query: "sangeet").map(\.id) == [river.id])
        #expect(try await store.search(query: "upb").map(\.id) == [river.id]) // prefix
        // Romanization-tolerant: "diwana" and "deevaana" find the tag "Deewana Mood".
        #expect(try await store.search(query: "diwana").map(\.id) == [pyaar.id])
        #expect(try await store.search(query: "deevaana mood").map(\.id) == [pyaar.id])
        // Tags combine with other columns: every word must match somewhere.
        #expect(try await store.search(query: "river sangeet").map(\.id) == [river.id])
        #expect(try await store.search(query: "pyar sangeet").isEmpty)

        // The index is a projection: a relaunch and a full rebuild still find tags.
        let relaunched = try await lib.openStore()
        #expect(try await relaunched.search(query: "sangeet").map(\.id) == [river.id])
        try await relaunched.rebuildIndex()
        #expect(try await relaunched.search(query: "diwana").map(\.id) == [pyaar.id])

        // Removing the tag removes the match.
        try await relaunched.updateMetadata(id: river.id, SongMetadata(tags: ["Upbeat"]))
        #expect(try await relaunched.search(query: "sangeet").isEmpty)
        #expect(try await relaunched.search(query: "upbeat").map(\.id) == [river.id])
    }

    @Test
    func `tags edited in the sidecar outside Segue are reindexed on refresh`() async throws {
        let lib = try TestLibrary()
        let store = try await lib.openStore()
        let song = try await store.createSong(source: Self.river)
        let path = "songs/river-song.segue.json"
        let edited = try lib.read(path).replacingOccurrences(
            of: "\"tags\" : [\n\n  ]",
            with: "\"tags\" : [\"Monsoon\"]",
        )
        #expect(edited.contains("Monsoon"))
        lib.clock.advance(by: 5)
        try lib.write(edited, to: path)

        #expect(try await store.refresh() == RefreshSummary(updated: 1))
        #expect(try await store.search(query: "monsoon").map(\.id) == [song.id])
        #expect(try await store.allTags() == [TagCount(tag: "Monsoon", count: 1)])
    }

    @Test
    func `all tags counts songs case-insensitively, most used first`() async throws {
        let lib = try TestLibrary()
        let store = try await lib.openStore()
        let songs = try await Array(0 ..< 4).asyncMap { number in
            try await store.createSong(source: "{title: Song \(number)}\nLa\n").id
        }
        try await store.updateMetadata(id: songs[0], SongMetadata(tags: ["upbeat", "Wedding"]))
        try await store.updateMetadata(id: songs[1], SongMetadata(tags: ["Upbeat", "acoustic"]))
        try await store.updateMetadata(id: songs[2], SongMetadata(tags: ["Upbeat", "wedding"]))
        try await store.updateMetadata(id: songs[3], SongMetadata(tags: ["Bollywood"]))

        #expect(try await store.allTags() == [
            TagCount(tag: "Upbeat", count: 3),
            TagCount(tag: "Wedding", count: 2), // tie: code-point order
            TagCount(tag: "acoustic", count: 1),
            TagCount(tag: "Bollywood", count: 1),
        ])
        #expect(try await lib.openStore().allTags().map(\.count) == [3, 2, 1, 1])
    }

    @Test
    func `live prefs are written to the sidecar only and read back`() async throws {
        let lib = try TestLibrary()
        let store = try await lib.openStore()
        let song = try await store.createSong(source: Self.river)
        let prefs = LivePrefs(
            zoom: 1.2,
            columns: 2,
            scrollSpeedFactor: 1.1,
            collapseRepeats: false,
            autoStartScroll: true,
        )
        let updated = try await store.updateLivePrefs(id: song.id, prefs)
        #expect(updated.sidecar.live == prefs)
        #expect(updated.revision.contentHash == song.revision.contentHash)
        #expect(try lib.read(song.relativePath) == Self.river)
        #expect(try lib.read("songs/river-song.segue.json").contains("\"columns\" : 2"))
        #expect(try await lib.openStore().song(id: song.id)?.sidecar.live == prefs)
    }

    @Test
    func `metadata and live prefs are refused for read-only songs`() async throws {
        let lib = try TestLibrary()
        let id = SongID(lib.ids.next())
        try lib.write(Self.river, to: "songs/future.cho")
        let sidecar = "{\"schemaVersion\": 99, \"id\": \"\(id)\", \"tags\": [\"x\"]}"
        try lib.write(sidecar, to: "songs/future.segue.json")
        let store = try await lib.openStore()
        let reason = ReadOnlyReason.newerSchema(found: 99, supported: Sidecar.currentSchemaVersion)

        await #expect(throws: LibraryError.readOnly(id, reason)) {
            try await store.updateMetadata(id: id, SongMetadata(tags: ["y"]))
        }
        await #expect(throws: LibraryError.readOnly(id, reason)) {
            try await store.updateLivePrefs(id: id, LivePrefs(zoom: 2))
        }
        #expect(try lib.read("songs/future.segue.json") == sidecar)
        let missing = SongID(lib.ids.next())
        await #expect(throws: LibraryError.songNotFound(missing)) {
            try await store.updateMetadata(id: missing, SongMetadata())
        }
    }

    @Test
    func `metadata edits merge a sidecar changed on disk`() async throws {
        let lib = try TestLibrary()
        let store = try await lib.openStore()
        let song = try await store.createSong(source: Self.river)
        let path = "songs/river-song.segue.json"
        // Another app (or device) changed the display prefs since we loaded the song.
        let edited = try lib.read(path).replacingOccurrences(
            of: "\"transpose\" : 0",
            with: "\"transpose\" : 3",
        )
        try lib.write(edited, to: path)

        let updated = try await store.updateMetadata(id: song.id, SongMetadata(tags: ["calm"]))
        #expect(updated.sidecar.displayPrefs.transpose == 3)
        #expect(updated.sidecar.tags == ["calm"])
        let saved = try lib.read(path)
        #expect(saved.contains("\"transpose\" : 3") && saved.contains("\"calm\""))
    }

    @Test
    func `reload song applies an external edit and updates the index row`() async throws {
        let lib = try TestLibrary()
        let store = try await lib.openStore()
        let song = try await store.createSong(source: Self.river)

        // Unchanged: the same record.
        #expect(try await store.reloadSong(id: song.id) == song)

        let edited = Self.river.replacingOccurrences(of: "water", with: "harbour lights")
        try lib.write(edited, to: song.relativePath)
        let reloaded = try #require(try await store.reloadSong(id: song.id))
        #expect(reloaded.source == edited)
        #expect(reloaded.id == song.id)
        #expect(try await store.song(id: song.id) == reloaded)
        #expect(try await store.search(query: "harbour").map(\.id) == [song.id])
        #expect(try await store.search(query: "water").isEmpty)
        #expect(try await store.refresh() == RefreshSummary())

        // A sidecar tag edit is picked up too.
        let sidecarPath = "songs/river-song.segue.json"
        try lib.write(
            lib.read(sidecarPath).replacingOccurrences(
                of: "\"tags\" : [\n\n  ]",
                with: "\"tags\" : [\"Sangeet\"]",
            ),
            to: sidecarPath,
        )
        #expect(try await store.reloadSong(id: song.id)?.sidecar.tags == ["Sangeet"])
        #expect(try await store.search(query: "sangeet").map(\.id) == [song.id])
    }

    @Test
    func `reload song finds a renamed file and returns nil for a deleted one`() async throws {
        let lib = try TestLibrary()
        let store = try await lib.openStore()
        let song = try await store.createSong(source: Self.river)
        let other = try await store.createSong(source: Self.pyaar)

        let manager = FileManager.default
        try manager.moveItem(at: lib.url("songs/river-song.cho"), to: lib.url("songs/river.cho"))
        try manager.moveItem(
            at: lib.url("songs/river-song.segue.json"),
            to: lib.url("songs/river.segue.json"),
        )
        let moved = try #require(try await store.reloadSong(id: song.id))
        #expect(moved.relativePath == "songs/river.cho")
        #expect(moved.source == Self.river)

        try manager.removeItem(at: lib.url("songs/river.cho"))
        try manager.removeItem(at: lib.url("songs/river.segue.json"))
        #expect(try await store.reloadSong(id: song.id) == nil)
        #expect(try await store.song(id: song.id) == nil)
        #expect(try await store.search(query: "river").isEmpty)
        #expect(try await store.allSongs().map(\.id) == [other.id])
    }

    @Test
    func `reload song keeps the ID when the sidecar was deleted`() async throws {
        let lib = try TestLibrary()
        let store = try await lib.openStore()
        let song = try await store.createSong(source: Self.river)
        try FileManager.default.removeItem(at: lib.url("songs/river-song.segue.json"))

        let reloaded = try #require(try await store.reloadSong(id: song.id))
        #expect(reloaded.id == song.id)
        #expect(lib.exists("songs/river-song.segue.json"))
        #expect(try await lib.openStore().song(id: song.id) != nil)
    }

    @Test
    func `an index from the previous schema is dropped and rebuilt`() async throws {
        let lib = try TestLibrary()
        let song = try await {
            let store = try await lib.openStore()
            let song = try await store.createSong(source: Self.river)
            return try await store.updateMetadata(id: song.id, SongMetadata(tags: ["Sangeet"]))
        }()

        // Overwrite with a phase 0 index (schema 1, no tags column, no plays table).
        let url = lib.root.indexDatabase
        for suffix in ["", "-wal", "-shm"] {
            try? FileManager.default.removeItem(atPath: url.path(percentEncoded: false) + suffix)
        }
        try IndexProbe.execute(lib, """
        CREATE TABLE songs (id TEXT PRIMARY KEY NOT NULL, path TEXT NOT NULL);
        PRAGMA user_version = 1002;
        """)

        let relaunched = try await lib.openStore()
        #expect(try await relaunched.search(query: "sangeet").map(\.id) == [song.id])
        // Schema 3 (the loose search columns), normalizer rules 3.
        #expect(try IndexProbe.scalar(lib, "PRAGMA user_version") == "3003")
        #expect(try IndexProbe.scalar(lib, "SELECT tags FROM songs") == "Sangeet")
        #expect(try IndexProbe.scalar(lib, "SELECT COUNT(*) FROM plays") == "0")
    }

    /// Quick search (phase 2 acceptance): under 50 ms for a 2,000-song index with tags.
    @Test
    func `quick search over 2000 tagged songs stays under 50 ms`() async throws {
        let lib = try TestLibrary()
        let songCount = 2000
        for number in 0 ..< songCount {
            let source = RomanizedHindiFixtures.songs[number % RomanizedHindiFixtures.songs.count]
                .replacingOccurrences(of: "{title: ", with: "{title: \(number) ")
            try lib.write(source, to: "songs/song-\(number).cho")
        }
        let store = try await lib.openStore()
        let all = try await store.allSongs()
        for (offset, song) in all.enumerated() where offset.isMultiple(of: 10) {
            try await store.updateMetadata(id: song.id, SongMetadata(tags: ["Sangeet", "Pyaar"]))
        }

        let clock = ContinuousClock()
        var best = Duration.seconds(1)
        for query in ["pyar", "sangeet", "kabhi phir", "deewana dil", "river"] {
            for _ in 0 ..< 3 {
                let start = clock.now
                let results = try await store.search(query: query)
                best = min(best, clock.now - start)
                #expect(!results.isEmpty, "\(query)")
            }
        }
        var worst = Duration.zero
        for query in ["pyar", "sangeet", "kabhi phir"] {
            let start = clock.now
            _ = try await store.search(query: query)
            worst = max(worst, clock.now - start)
        }
        print("[perf] quick search over \(songCount) songs: best \(best), worst warm \(worst)")
        #expect(worst < .milliseconds(50), "worst warm search: \(worst)")
    }
}

/// Direct SQLite access to the index file, outside the store (inspection only).
enum IndexProbe {
    static func execute(_ lib: TestLibrary, _ sql: String) throws {
        let db = try open(lib, flags: SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE)
        defer { sqlite3_close(db) }
        guard sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK else {
            throw CocoaError(.fileWriteUnknown)
        }
    }

    /// The first column of the first row as text; nil when there is no row.
    static func scalar(_ lib: TestLibrary, _ sql: String) throws -> String? {
        let db = try open(lib, flags: SQLITE_OPEN_READONLY)
        defer { sqlite3_close(db) }
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw CocoaError(.fileReadCorruptFile)
        }
        defer { sqlite3_finalize(statement) }
        guard sqlite3_step(statement) == SQLITE_ROW,
              let text = sqlite3_column_text(statement, 0)
        else { return nil }
        return String(cString: text)
    }

    private static func open(_ lib: TestLibrary, flags: Int32) throws -> OpaquePointer? {
        var db: OpaquePointer?
        let path = lib.root.indexDatabase.path(percentEncoded: false)
        guard sqlite3_open_v2(path, &db, flags, nil) == SQLITE_OK else {
            sqlite3_close(db)
            throw CocoaError(.fileReadUnknown)
        }
        return db
    }
}
