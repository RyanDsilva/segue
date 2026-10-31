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
        // The next save writes the current schema with the bass object.
        _ = try await store.updateBassPrefs(id: song.id, BassPrefs(genre: .rock))
        let written = try lib.read("songs/old.segue.json")
        #expect(written.contains("\"schemaVersion\" : \(Sidecar.currentSchemaVersion)"))
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
    func `a song's scale round-trips, and an unknown one reads as the default`() throws {
        let saved = try JSONDecoder().decode(
            BassPrefs.self,
            from: Data(#"{"genre": "bollywood", "mode": "bhairav"}"#.utf8),
        )
        #expect(saved.mode == .bhairav)
        let again = try JSONDecoder().decode(BassPrefs.self, from: JSONEncoder().encode(saved))
        #expect(again == saved)
        let unknown = try JSONDecoder().decode(
            BassPrefs.self,
            from: Data(#"{"genre": "rock", "mode": "dorian"}"#.utf8),
        )
        #expect(unknown == BassPrefs(genre: .rock))
        let plain = try JSONEncoder().encode(BassPrefs(genre: .rock))
        #expect(String(bytes: plain, encoding: .utf8)?.contains("mode") == false)
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
    func `ticks, push, source and dismissals round-trip in schema 5`() throws {
        let json = """
        {"timing": {"rule": {"each": "bar"}, "chords": [
          {"section": "Chorus", "occurrence": 1, "fp": "9f8e7d6c", "chord": 0, "from": "C",
           "beats": 2},
          {"section": "Verse", "occurrence": 1, "fp": "1a2b3c4d", "chord": 2, "from": "D",
           "beats": 3, "ticks": 1200, "push": "8", "source": "tap"}],
         "dismissedKeys": [{"section": "Chorus", "occurrence": 3, "fp": "5e6f7a8b",
           "key": "A"}]}}
        """
        let prefs = try JSONDecoder().decode(BassPrefs.self, from: Data(json.utf8))
        let chords = prefs.timing.chords
        #expect(chords.map(\.beats) == [2, 3])
        #expect(chords.map(\.ticks) == [nil, 1200])
        #expect(chords.map(\.push) == [nil, .eighth])
        #expect(chords.map(\.source) == [nil, .tap])
        #expect(try prefs.timing.dismissedKeys == [KeyChangeDismissal(
            section: .section(SectionRef(label: "Chorus", occurrence: 3)),
            fingerprint: "5e6f7a8b",
            key: #require(SongKey(parsing: "A")),
        )])
        let encoded = try JSONEncoder().encode(prefs)
        #expect(try JSONDecoder().decode(BassPrefs.self, from: encoded) == prefs)
        // An old-shape override writes no new fields, and no dismissals write none.
        let plain = try JSONEncoder().encode(ChordTiming(chords: [chords[0]]))
        let text = String(bytes: plain, encoding: .utf8) ?? ""
        #expect(!text.contains("ticks") && !text.contains("push") && !text.contains("source"))
        #expect(!text.contains("dismissedKeys"))
    }

    @Test
    func `a bad push, ticks or source drops only that field`() throws {
        let json = """
        {"chords": [
          {"section": "Verse", "fp": "x", "chord": 0, "from": "G", "beats": 4, "push": "4"},
          {"section": "Verse", "fp": "x", "chord": 1, "from": "C", "beats": 4, "ticks": 0},
          {"section": "Verse", "fp": "x", "chord": 2, "from": "D", "beats": 4,
           "ticks": "long", "source": "guess", "push": "16"}],
         "dismissedKeys": [{"section": "Chorus", "fp": "y", "key": "H"}, 3]}
        """
        let timing = try JSONDecoder().decode(ChordTiming.self, from: Data(json.utf8))
        #expect(timing.chords.count == 3)
        #expect(timing.chords.map(\.push) == [nil, nil, .sixteenth])
        #expect(timing.chords.allSatisfy { $0.ticks == nil && $0.source == nil })
        #expect(timing.dismissedKeys.isEmpty)
    }

    @Test
    func `a sub-beat correction writes its rounded beats beside the ticks`() {
        let anchor = ChordAnchor(
            section: .section(SectionRef(label: "Verse", occurrence: 1)),
            fingerprint: "x",
            chord: 0,
            from: "G",
        )
        let override = ChordBeatsOverride(anchor: anchor, ticks: 1200, meter: .common)
        #expect(override.beats == 3)
        let sixEight = ChordBeatsOverride(anchor: anchor, ticks: 1080, meter: Meter(time: "6/8"))
        #expect(sixEight.beats == 2)
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
    func `a newer sidecar opens read-only and is never rewritten`() async throws {
        let lib = try TestLibrary()
        let store = try await lib.openStore()
        let song = try await store.createSong(source: "{title: New}\n[G]Hello\n")
        let newer = """
        {"id": "\(song.id)", "schemaVersion": 7, "bass": {"walkUps": [\(Self.pick)]}}
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
