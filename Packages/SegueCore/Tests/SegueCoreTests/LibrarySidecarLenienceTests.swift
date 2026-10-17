import Foundation
import Library
import Support
import Testing

// Integration suite for `LibraryStore`: real files in a temp folder, real GRDB index, real
// ChordPro parser (docs/phases/0-walking-skeleton.md, "Test strategy").

/// Sidecars are decoded field by field at every version, so a missing optional field never
/// makes a song read-only.
struct LibrarySidecarLenienceTests {
    /// A current-version sidecar missing optional fields (`displayPrefs`, `live`, `cues`,
    /// `tags`, dates), e.g. hand-written or from another tool, opens editable with defaults
    /// and the next save writes the full form.
    @Test
    func `a current sidecar missing optional fields opens editable`() async throws {
        let lib = try TestLibrary()
        let store = try await lib.openStore()
        let song = try await store.createSong(source: "{title: Sparse}\nFew fields\n")
        let sparse = """
        {"id": "\(song.id)", "schemaVersion": \(Sidecar.currentSchemaVersion), \
        "proficiency": "ready", "notes": "Start soft"}
        """
        try lib.write(sparse, to: "songs/sparse.segue.json")
        try await store.refresh()

        for current in try await [store, lib.openStore()] {
            let record = try #require(try await current.song(id: song.id))
            #expect(record.readOnly == nil)
            #expect(record.sidecar.proficiency == .ready)
            #expect(record.sidecar.notes == "Start soft")
            #expect(record.sidecar.displayPrefs == DisplayPrefs())
            #expect(record.sidecar.live == LivePrefs())
            #expect(record.sidecar.cues.isEmpty)
            #expect(record.sidecar.tags.isEmpty)
        }
        let saved = try await store.updateSong(id: song.id, source: "{title: Sparse}\nMore\n")
        #expect(saved.sidecar.proficiency == .ready)
        let written = try lib.read("songs/sparse.segue.json")
        #expect(written.contains("\"displayPrefs\""))
        #expect(written.contains("\"live\""))
    }
}
