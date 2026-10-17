import Foundation
import Library
import Support
import Testing

/// Regression tests for the phase 0 review (docs/reviews/phase0-review.md), one or more per
/// finding, on real files in a temp folder with the real GRDB index.
struct LibraryHardeningTests {
    private static let song = "{title: Harbour Lights}\n[G]Lights along the [C]harbour\n"

    // MARK: #1 external edits are never silently overwritten

    @Test
    func `saving over an external edit throws conflict and keeps the edit on disk`() async throws {
        let lib = try TestLibrary()
        let store = try await lib.openStore()
        let loaded = try await store.createSong(source: Self.song)
        // The editor opens on `loaded`; meanwhile another app edits the file.
        let external = "{title: Harbour Lights}\nEdited in another app\n"
        try lib.write(external, to: "songs/harbour-lights.cho")

        await #expect(throws: LibraryError.conflict(loaded.id, .sourceChanged)) {
            try await store.updateSong(id: loaded.id, source: "{title: Mine}\n")
        }
        // Even after a refresh taught the store the new text, the editor's base is stale.
        try await store.refresh()
        await #expect(throws: LibraryError.conflict(loaded.id, .sourceChanged)) {
            try await store.updateSong(
                id: loaded.id,
                source: "{title: Mine}\n",
                basedOn: loaded.revision,
            )
        }
        #expect(try lib.read("songs/harbour-lights.cho") == external)

        // Save as Copy: a new song, the external edit untouched.
        let copy = try await store.createSong(source: "{title: Harbour Lights}\nMine\n")
        #expect(copy.relativePath == "songs/harbour-lights-2.cho")
        #expect(try lib.read("songs/harbour-lights.cho") == external)

        // Overwrite: the user's text wins, same ID and file.
        let overwritten = try await store.overwriteSong(id: loaded.id, source: "{title: Mine}\n")
        #expect(overwritten.id == loaded.id)
        #expect(try lib.read("songs/harbour-lights.cho") == "{title: Mine}\n")

        // Reload: a save based on the current revision goes through.
        let current = try #require(try await store.song(id: loaded.id))
        let saved = try await store.updateSong(
            id: loaded.id,
            source: "{title: Mine again}\n",
            basedOn: current.revision,
        )
        #expect(saved.revision != current.revision)
        #expect(try lib.read("songs/harbour-lights.cho") == "{title: Mine again}\n")
    }

    @Test
    func `metadata edited elsewhere is merged into a save, not overwritten`() async throws {
        let lib = try TestLibrary()
        let store = try await lib.openStore()
        let loaded = try await store.createSong(source: Self.song)
        let sidecar = try lib.read("songs/harbour-lights.segue.json")
        try lib.write(
            sidecar.replacingOccurrences(
                of: "\"tags\" : [\n\n  ]",
                with: "\"tags\" : [\"wedding\"]",
            ),
            to: "songs/harbour-lights.segue.json",
        )

        let saved = try await store.updateSong(
            id: loaded.id,
            source: "{title: Harbour Lights}\nNew words\n",
            basedOn: loaded.revision,
        )

        #expect(saved.sidecar.tags == ["wedding"])
        #expect(try lib.read("songs/harbour-lights.segue.json").contains("\"wedding\""))
        #expect(try lib.read("songs/harbour-lights.cho") == "{title: Harbour Lights}\nNew words\n")
    }

    @Test
    func `a sidecar that became unreadable is a conflict and is left alone`() async throws {
        let lib = try TestLibrary()
        let store = try await lib.openStore()
        let loaded = try await store.createSong(source: Self.song)
        let garbage = "{\"id\": oops"
        try lib.write(garbage, to: "songs/harbour-lights.segue.json")

        for save in [
            { try await store.updateSong(id: loaded.id, source: "x\n") },
            { try await store.overwriteSong(id: loaded.id, source: "x\n") },
        ] {
            await #expect(throws: LibraryError.conflict(loaded.id, .metadataChanged)) {
                try await save()
            }
        }
        #expect(try lib.read("songs/harbour-lights.segue.json") == garbage)
        #expect(try lib.read("songs/harbour-lights.cho") == Self.song)
    }

    // MARK: #10 external delete while editing

    @Test
    func `saving a song deleted on disk throws conflict deleted and recreates nothing`(
    ) async throws {
        let lib = try TestLibrary()
        let store = try await lib.openStore()
        let loaded = try await store.createSong(source: Self.song)
        try FileManager.default.removeItem(at: lib.url("songs/harbour-lights.cho"))

        await #expect(throws: LibraryError.conflict(loaded.id, .deleted)) {
            try await store.updateSong(id: loaded.id, source: "{title: Harbour Lights}\nMine\n")
        }
        #expect(!lib.exists("songs/harbour-lights.cho"))
        // After a refresh the song is gone from the store: save as new instead.
        try await store.refresh()
        await #expect(throws: LibraryError.songNotFound(loaded.id)) {
            try await store.updateSong(id: loaded.id, source: "x\n", basedOn: loaded.revision)
        }
        let recreated = try await store.createSong(source: "{title: Harbour Lights}\nMine\n")
        #expect(recreated.id != loaded.id)
        #expect(try lib.read(recreated.relativePath) == "{title: Harbour Lights}\nMine\n")
    }

    // MARK: #2 one bad file never fails the whole library

    @Test
    func `an unreadable cho is reported and the rest of the library opens`() async throws {
        let lib = try TestLibrary()
        try lib.write("{title: Good}\nFine\n", to: "songs/good.cho")
        try lib.write("{title: Locked}\nSecret\n", to: "songs/locked.cho")
        try lib.setPermissions(0o000, of: "songs/locked.cho")
        defer { try? lib.setPermissions(0o644, of: "songs/locked.cho") }

        let store = try await lib.openStore()

        #expect(try await store.allSongs().titles == ["Good"])
        let issues = await store.loadIssues
        #expect(issues.map(\.relativePath) == ["songs/locked.cho"])
        #expect(issues.first?.message.isEmpty == false)

        try lib.setPermissions(0o644, of: "songs/locked.cho")
        try await store.refresh()
        #expect(try await store.allSongs().titles == ["Good", "Locked"])
        #expect(await store.loadIssues.isEmpty)
    }

    @Test
    func `a song that turns unreadable keeps its last loaded version`() async throws {
        let lib = try TestLibrary()
        let store = try await lib.openStore()
        let record = try await store.createSong(source: Self.song)
        try lib.write("{title: Harbour Lights}\nChanged and locked\n", to: record.relativePath)
        try lib.setPermissions(0o000, of: record.relativePath)
        defer { try? lib.setPermissions(0o644, of: record.relativePath) }

        try await store.refresh()

        #expect(try await store.song(id: record.id)?.source == Self.song)
        #expect(try await store.search(query: "harbour").map(\.id) == [record.id])
        #expect(await store.loadIssues.map(\.relativePath) == [record.relativePath])
    }

    @Test
    func `an orphan whose sidecar can't be written still loads with a stable id`() async throws {
        let lib = try TestLibrary()
        try lib.write("{title: Orphan}\nNo sidecar\n", to: "songs/orphan.cho")
        try lib.setPermissions(0o555, of: "songs")
        defer { try? lib.setPermissions(0o755, of: "songs") }

        let store = try await lib.openStore()
        let orphan = try #require(try await store.allSongs().first)
        #expect(orphan.hasDerivedID)
        #expect(await store.loadIssues.map(\.relativePath) == ["songs/orphan.segue.json"])
        #expect(!lib.exists("songs/orphan.segue.json"))
        // Relaunching while the folder is still read-only gives the same ID.
        #expect(try await lib.openStore().allSongs().map(\.id) == [orphan.id])

        // Once the folder is writable the sidecar is created with that same ID.
        try lib.setPermissions(0o755, of: "songs")
        try await store.refresh()
        #expect(await store.loadIssues.isEmpty)
        #expect(try lib.read("songs/orphan.segue.json").contains(orphan.id.description))
        let adopted = try #require(try await store.song(id: orphan.id))
        #expect(!adopted.hasDerivedID)
    }

    // MARK: #3 the original keeps its ID, never the copy

    @Test
    func `on a cold launch a finder copy never steals the original's id`() async throws {
        let lib = try TestLibrary()
        let original: SongRecord
        do {
            let store = try await lib.openStore()
            original = try await store.createSong(source: "{title: Original}\nCopy me\n")
        }
        // Finder names the copy "original copy", which sorts before "original" by path.
        lib.clock.advance(by: 60)
        try lib.write(lib.read("songs/original.cho"), to: "songs/original copy.cho")
        try lib.write(lib.read("songs/original.segue.json"), to: "songs/original copy.segue.json")

        let relaunched = try await lib.openStore()

        #expect(try await relaunched.song(id: original.id)?.relativePath == "songs/original.cho")
        let copy = try #require(try await relaunched.allSongs().first { $0.id != original.id })
        #expect(copy.relativePath == "songs/original copy.cho")
        #expect(copy.sidecar.createdAt == lib.clock.now())
        #expect(try lib.read("songs/original copy.segue.json").contains(copy.id.description))
        // Stable from then on.
        let again = try await lib.openStore()
        #expect(try await again.song(id: original.id)?.relativePath == "songs/original.cho")
        #expect(try await again.song(id: copy.id)?.relativePath == "songs/original copy.cho")
    }

    @Test
    func `with equal creation dates the shortest slug keeps the id`() async throws {
        let lib = try TestLibrary()
        let original: SongRecord
        do {
            let store = try await lib.openStore()
            original = try await store.createSong(source: "{title: Song}\nWords\n")
        }
        // Both copies sort before the original by path; neither is the shortest name.
        let copies = ["a copy of song", "song 2"]
        for copy in copies {
            try lib.write(lib.read("songs/song.cho"), to: "songs/\(copy).cho")
            try lib.write(lib.read("songs/song.segue.json"), to: "songs/\(copy).segue.json")
        }
        let created = Date(timeIntervalSince1970: 1_700_000_000)
        for name in ["song"] + copies {
            try FileManager.default.setAttributes(
                [.creationDate: created],
                ofItemAtPath: lib.url("songs/\(name).cho").path(percentEncoded: false),
            )
        }

        let relaunched = try await lib.openStore()

        #expect(try await relaunched.song(id: original.id)?.relativePath == "songs/song.cho")
        #expect(try await Set(relaunched.allSongs().map(\.id)).count == 3)
    }

    // MARK: #4 unchanged files are not read again

    @Test
    func `refresh skips files whose mtime and size are unchanged`() async throws {
        let lib = try TestLibrary()
        let fileSystem = InstrumentedFileSystem()
        let store = try await lib.openStore(fileSystem: fileSystem)
        let first = try await store.createSong(source: "{title: First}\nOne\n")
        _ = try await store.createSong(source: "{title: Second}\nTwo\n")

        fileSystem.resetCounts()
        #expect(try await store.refresh() == RefreshSummary())
        #expect(fileSystem.readCount == 0, "reads: \(fileSystem.reads)")

        // An external edit changes mtime (and here size): only that pair is read.
        try lib.write("{title: First}\nOne, edited elsewhere\n", to: "songs/first.cho")
        fileSystem.resetCounts()
        #expect(try await store.refresh() == RefreshSummary(updated: 1))
        #expect(fileSystem.reads == ["first.cho": 1])
        #expect(try await store.search(query: "elsewhere").map(\.id) == [first.id])

        // Same size, new mtime: still picked up.
        try lib.write("{title: First}\nOne, edited ELSEWHERE\n", to: "songs/first.cho")
        try FileManager.default.setAttributes(
            [.modificationDate: Date(timeIntervalSinceNow: 5)],
            ofItemAtPath: lib.url("songs/first.cho").path(percentEncoded: false),
        )
        #expect(try await store.refresh() == RefreshSummary(updated: 1))
        #expect(try await store.song(id: first.id)?.source.contains("ELSEWHERE") == true)
    }

    // MARK: #8 a sidecar without a recoverable id gets a stable derived id

    @Test
    func `unreadable sidecar without an id gets the same derived id every launch`() async throws {
        let lib = try TestLibrary()
        let garbage = "{\"schemaVersion\": 1, \"tags\": [oops"
        try lib.write("{title: Mystery}\nWho am I\n", to: "songs/mystery.cho")
        try lib.write(garbage, to: "songs/mystery.segue.json")

        let first = try await lib.openStore()
        let record = try #require(try await first.allSongs().first)
        #expect(record.hasDerivedID)
        guard case .unreadableSidecar = record.readOnly else {
            Issue.record("expected unreadableSidecar, got \(String(describing: record.readOnly))")
            return
        }
        try await first.refresh()
        try await first.rebuildIndex()
        #expect(try await first.allSongs().map(\.id) == [record.id])
        #expect(try await lib.openStore().allSongs().map(\.id) == [record.id])
        #expect(try await lib.openStore().search(query: "mystery").map(\.id) == [record.id])
        #expect(try lib.read("songs/mystery.segue.json") == garbage)
    }

    // MARK: #11 non-UTF-8 files open read-only

    @Test
    func `a latin-1 file opens read-only with its text intact and is never rewritten`(
    ) async throws {
        let lib = try TestLibrary()
        let text = "{title: Café Crème}\nVoilà, déjà vu\n"
        let latin1 = try #require(text.data(using: .isoLatin1))
        try lib.writeBytes(latin1, to: "songs/cafe.cho")

        let store = try await lib.openStore()
        let record = try #require(try await store.allSongs().first)

        let reason = ReadOnlyReason.notUTF8(encoding: "Windows Latin 1")
        #expect(record.readOnly == reason)
        #expect(record.document.metadata.title == "Café Crème")
        #expect(record.source == text)
        #expect(try await store.search(query: "creme").map(\.id) == [record.id])
        await #expect(throws: LibraryError.readOnly(record.id, reason)) {
            try await store.updateSong(id: record.id, source: "{title: Cafe}\n")
        }
        try await store.refresh()
        _ = try await lib.openStore()
        #expect(try lib.bytes("songs/cafe.cho") == latin1)
        // Its sidecar is still created: the ID is stable.
        #expect(lib.exists("songs/cafe.segue.json"))
    }

    // MARK: #13 a failed index rebuild leaves the library usable

    @Test
    func `a failed index rebuild keeps search working and can be retried`() async throws {
        let lib = try TestLibrary()
        let fileSystem = InstrumentedFileSystem()
        let store = try await lib.openStore(fileSystem: fileSystem)
        let record = try await store.createSong(source: Self.song)

        fileSystem.fail(.remove, suffix: "index.sqlite")
        await #expect(throws: InstrumentedFileSystem.InjectedFailure.self) {
            try await store.rebuildIndex()
        }

        #expect(try await store.search(query: "harbour").map(\.id) == [record.id])
        let another = try await store.createSong(source: "{title: After Failure}\nStill works\n")
        #expect(try await store.search(query: "failure").map(\.id) == [another.id])

        fileSystem.heal()
        try await store.rebuildIndex()
        #expect(try await store.search(query: "harbour").map(\.id) == [record.id])
        #expect(try await store.search(query: "failure").map(\.id) == [another.id])
    }
}
