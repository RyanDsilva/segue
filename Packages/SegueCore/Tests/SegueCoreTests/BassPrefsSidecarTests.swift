import Editing
import Foundation
import Library
import MusicTheory
import Support
import Testing

/// Sidecar schema 5 (P8-4 section 8.10): the `bass` object, its migration from v4 and its
/// lenient decoding. Real files, real index.
struct BassPrefsSidecarTests {
    static let pick = """
    {"section": "Verse", "occurrence": 1, "fp": "1a2b3c4d", "chord": 3, \
    "from": "G", "to": "C", "pick": "scaleWalk", "offsets": [-3, -1]}
    """

    @Test
    func `a v4 sidecar migrates to 5 with empty bass and keeps everything else`() async throws {
        let lib = try TestLibrary()
        let store = try await lib.openStore()
        let song = try await store.createSong(source: "{title: Old}\n[G]Hello\n")
        let old = """
        {"id": "\(song.id)", "schemaVersion": 4, "tags": ["gig"], "notes": "Start soft", \
        "cues": [], "displayPrefs": {"transpose": 2}, "live": {}, \
        "createdAt": "2026-01-01T00:00:00Z", "updatedAt": "2026-01-01T00:00:00Z"}
        """
        try lib.write(old, to: "songs/old.segue.json")
        try await store.refresh()
        let record = try #require(try await store.song(id: song.id))
        #expect(record.readOnly == nil)
        #expect(record.sidecar.bass == BassPrefs())
        #expect(record.sidecar.tags == ["gig"])
        #expect(record.sidecar.notes == "Start soft")
        #expect(record.sidecar.displayPrefs.transpose == 2)
        // The next save writes schema 5 with the bass object.
        _ = try await store.updateBassPrefs(id: song.id, BassPrefs(genre: .rock))
        let written = try lib.read("songs/old.segue.json")
        #expect(written.contains("\"schemaVersion\" : 5"))
        #expect(written.contains("\"genre\" : \"rock\""))
        #expect(written.contains("\"tags\""))
    }

    @Test
    func `bass round-trips and bad entries are dropped one by one`() throws {
        let json = """
        {"genre": "jazz", "walkUps": [\(Self.pick),
          {"section": "Verse", "fp": "x", "chord": 0, "from": "G", "to": "C", "pick": "solo"},
          {"section": "Verse", "fp": "x", "chord": 0, "from": "G", "to": "C", "pick": "fifth",
           "offsets": [1, 2, 3, 4, 5, 6]},
          {"section": "Verse", "fp": "x", "chord": 0, "from": "G", "to": "C", "pick": "fifth",
           "offsets": [12]},
          {"to": "C", "pick": "fifth", "offsets": [-5]}],
         "timing": {"rule": {"each": "fortnight"}, "chords": 7}}
        """
        let prefs = try JSONDecoder().decode(BassPrefs.self, from: Data(json.utf8))
        #expect(prefs.genre == nil)
        #expect(prefs.walkUps.count == 1)
        #expect(prefs.walkUps.first?.kind == .scaleWalk)
        #expect(prefs.walkUps.first?.offsets == [-3, -1])
        #expect(prefs.timing == ChordTiming())
        let again = try JSONDecoder().decode(
            BassPrefs.self,
            from: JSONEncoder().encode(prefs),
        )
        #expect(again == prefs)
    }

    @Test
    func `timing is preserved`() throws {
        let json = """
        {"walkUps": [], "timing": {"rule": {"line": 2}, "chords": [
          {"section": "Chorus", "occurrence": 1, "fp": "9f8e7d6c", "chord": 0, "from": "C",
           "beats": 2},
          {"section": "Chorus", "fp": "9f8e7d6c", "chord": 0, "from": "C", "beats": 40}]}}
        """
        let prefs = try JSONDecoder().decode(BassPrefs.self, from: Data(json.utf8))
        #expect(prefs.timing.rule == .line(2))
        #expect(prefs.timing.chords.map(\.beats) == [2])
        let again = try JSONDecoder().decode(BassPrefs.self, from: JSONEncoder().encode(prefs))
        #expect(again == prefs)
    }

    @Test
    func `a malformed bass object reads empty and the song stays editable`() async throws {
        let lib = try TestLibrary()
        let store = try await lib.openStore()
        let song = try await store.createSong(source: "{title: Odd}\n[G]Hello\n")
        try lib.write(
            """
            {"id": "\(song.id)", "schemaVersion": 5, "bass": "oops", "notes": "Keep"}
            """,
            to: "songs/odd.segue.json",
        )
        try await store.refresh()
        let record = try #require(try await store.song(id: song.id))
        #expect(record.readOnly == nil)
        #expect(record.sidecar.bass == BassPrefs())
        #expect(record.sidecar.notes == "Keep")
    }

    @Test
    func `a v6 sidecar opens read-only and is never rewritten`() async throws {
        let lib = try TestLibrary()
        let store = try await lib.openStore()
        let song = try await store.createSong(source: "{title: New}\n[G]Hello\n")
        let newer = """
        {"id": "\(song.id)", "schemaVersion": 6, "bass": {"walkUps": [\(Self.pick)]}}
        """
        try lib.write(newer, to: "songs/new.segue.json")
        try await store.refresh()
        let record = try #require(try await store.song(id: song.id))
        #expect(record.readOnly != nil)
        await #expect(throws: (any Error).self) {
            try await store.updateBassPrefs(id: song.id, BassPrefs(genre: .pop))
        }
        #expect(try lib.read("songs/new.segue.json") == newer)
    }

    @Test
    func `updateBassPrefs writes the sidecar only`() async throws {
        let lib = try TestLibrary()
        let store = try await lib.openStore()
        let song = try await store.createSong(source: "{title: Only}\n[G]Hello\n")
        let cho = try lib.read("songs/only.cho")
        let choDate = try FileManager.default
            .attributesOfItem(atPath: lib.url("songs/only.cho").path)[.modificationDate] as? Date
        let saved = try await store.updateBassPrefs(id: song.id, BassPrefs(genre: .worship))
        #expect(saved.sidecar.bass.genre == .worship)
        #expect(try lib.read("songs/only.cho") == cho)
        let after = try FileManager.default
            .attributesOfItem(atPath: lib.url("songs/only.cho").path)[.modificationDate] as? Date
        #expect(after == choDate)
        let reopened = try #require(try await lib.openStore().song(id: song.id))
        #expect(reopened.sidecar.bass.genre == .worship)
    }
}
