import Diagrams
import Editing
import Foundation
import Library
import MusicTheory
import Testing

/// Sidecar schema 2 (phase 1 display prefs): migration from older files, lenient prefs on
/// the migrated and newer-schema paths, and prefs-only writes.
struct EditingSidecarTests {
    @Test
    func `version 1 sidecar migrates to the current version and keeps its display prefs`(
    ) async throws {
        let lib = try TestLibrary()
        let id = SongID(lib.ids.next())
        let v1 = """
        {"schemaVersion": 1, "id": "\(id)", "tags": ["wedding"],
         "displayPrefs": {"transpose": 3, "nashville": "yes", "capoMode": "concert"},
         "createdAt": "2025-06-01T10:00:00.000Z", "updatedAt": "2025-06-02T10:00:00.000Z"}
        """
        try lib.write("{title: Old Prefs}\n[G]La\n", to: "songs/old-prefs.cho")
        try lib.write(v1, to: "songs/old-prefs.segue.json")

        let store = try await lib.openStore()
        let record = try #require(try await store.song(id: id))
        #expect(record.readOnly == nil)
        #expect(record.sidecar.schemaVersion == Sidecar.currentSchemaVersion)
        #expect(record.sidecar.tags == ["wedding"])
        // Readable fields survive; the unreadable one takes its default.
        #expect(record.sidecar.displayPrefs == DisplayPrefs(transpose: 3, capoMode: .concert))
        #expect(try lib.read("songs/old-prefs.segue.json") == v1)

        _ = try await store.updateSong(id: id, source: "{title: Old Prefs}\n[G]La la\n")
        let saved = try lib.read("songs/old-prefs.segue.json")
        #expect(saved.contains("\"schemaVersion\" : \(Sidecar.currentSchemaVersion)"))
        #expect(saved.contains("\"transpose\" : 3"))
        #expect(saved.contains("\"capoMode\" : \"concert\""))
    }

    @Test
    func `version 0 and malformed prefs fall back to defaults field by field`() async throws {
        let lib = try TestLibrary()
        let legacy = SongID(lib.ids.next())
        let broken = SongID(lib.ids.next())
        try lib.write("{title: Legacy}\n", to: "songs/legacy.cho")
        try lib.write(
            #"{"id": "\#(legacy)", "displayPrefs": {"instrument": "piano"}}"#,
            to: "songs/legacy.segue.json",
        )
        try lib.write("{title: Broken}\n", to: "songs/broken.cho")
        try lib.write(
            #"{"schemaVersion": 1, "id": "\#(broken)", "tags": [], "displayPrefs": 7,"#
                + #" "createdAt": "2025-06-01T10:00:00Z", "updatedAt": "2025-06-01T10:00:00Z"}"#,
            to: "songs/broken.segue.json",
        )
        let store = try await lib.openStore()
        let migrated = try #require(try await store.song(id: legacy))
        #expect(migrated.sidecar.displayPrefs == DisplayPrefs(instrument: .piano))
        let defaulted = try #require(try await store.song(id: broken))
        #expect(defaulted.readOnly == nil)
        #expect(defaulted.sidecar.displayPrefs == DisplayPrefs())
    }

    @Test
    func `newer sidecar keeps its display prefs while read-only`() async throws {
        let lib = try TestLibrary()
        let id = SongID(lib.ids.next())
        let future = """
        {"schemaVersion": 99, "id": "\(id)", "tags": [],
         "displayPrefs": {"transpose": -4, "nashville": true, "hologram": "on"},
         "createdAt": "2030-01-01T00:00:00.000Z", "updatedAt": "2030-01-01T00:00:00.000Z"}
        """
        try lib.write("{title: Future}\n[C]Ahead\n", to: "songs/future.cho")
        try lib.write(future, to: "songs/future.segue.json")
        let store = try await lib.openStore()
        let record = try #require(try await store.song(id: id))
        #expect(record.readOnly == .newerSchema(found: 99, supported: Sidecar.currentSchemaVersion))
        #expect(record.sidecar.displayPrefs == DisplayPrefs(transpose: -4, nashville: true))

        let newer = ReadOnlyReason.newerSchema(found: 99, supported: Sidecar.currentSchemaVersion)
        await #expect(throws: LibraryError.readOnly(id, newer)) {
            try await store.updateDisplayPrefs(id: id, DisplayPrefs(transpose: 1))
        }
        #expect(try lib.read("songs/future.segue.json") == future)
        let missing = SongID(lib.ids.next())
        await #expect(throws: LibraryError.songNotFound(missing)) {
            try await store.updateDisplayPrefs(id: missing, DisplayPrefs())
        }
    }

    @Test
    func `display prefs encode every field and decode leniently`() throws {
        let prefs = DisplayPrefs(
            transpose: 7,
            capoMode: .concert,
            nashville: true,
            showDiagrams: false,
            instrument: .piano,
            tuning: .openG,
        )
        let data = try JSONEncoder().encode(prefs)
        #expect(try JSONDecoder().decode(DisplayPrefs.self, from: data) == prefs)
        let empty = try JSONDecoder().decode(DisplayPrefs.self, from: Data("{}".utf8))
        #expect(empty == DisplayPrefs())
        #expect(empty.displayOptions == DisplayOptions())
    }

    @Test
    func `display prefs persist in the sidecar only and survive a relaunch`() async throws {
        let lib = try TestLibrary()
        let store = try await lib.openStore()
        let record = try await store
            .createSong(source: EditingFixtures.load("basic-verse-chorus.cho"))
        let choBefore = try Data(contentsOf: lib.url(record.relativePath))
        let choDate = try FileManager.default
            .attributesOfItem(atPath: lib.url(record.relativePath).path)[.modificationDate] as? Date

        let prefs = DisplayPrefs(
            transpose: -3,
            capoMode: .concert,
            nashville: true,
            showDiagrams: false,
            instrument: .piano,
            tuning: .dropD,
        )
        lib.clock.advance(by: 60)
        let updated = try await store.updateDisplayPrefs(id: record.id, prefs)
        #expect(updated.sidecar.displayPrefs == prefs)
        #expect(updated.sidecar.updatedAt > record.sidecar.updatedAt)
        #expect(try Data(contentsOf: lib.url(record.relativePath)) == choBefore)
        let choDateAfter = try FileManager.default
            .attributesOfItem(atPath: lib.url(record.relativePath).path)[.modificationDate] as? Date
        #expect(choDateAfter == choDate)

        let reopened = try #require(try await lib.openStore().song(id: record.id))
        #expect(reopened.sidecar.displayPrefs == prefs)
        #expect(reopened.sidecar.displayPrefs.displayOptions == DisplayOptions(
            transpose: -3,
            capoMode: .concert,
            nashville: true,
            showDiagrams: false,
            instrument: .piano,
            tuning: .dropD,
        ))
        #expect(DisplayPrefs(prefs.displayOptions) == prefs)
        let sidecar = try lib.read(record.relativePath.replacingOccurrences(
            of: ".cho",
            with: ".segue.json",
        ))
        #expect(sidecar.contains("\"nashville\" : true"))
        #expect(sidecar.contains("\"instrument\" : \"piano\""))
    }
}
