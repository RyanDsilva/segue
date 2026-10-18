import Foundation
import Library
import Support
import Testing

/// Song metadata undo writes the old `SongMetadata` back (WS2a 3.9.1): the sidecar must come
/// back exactly, apart from `updatedAt`.
struct SongMetadataUndoTests {
    @Test
    func `restoring the old metadata writes the sidecar back exactly`() async throws {
        let lib = try TestLibrary()
        let store = try await lib.openStore()
        let song = try await store.createSong(source: "{title: Harbour}\nLine\n")
        let original = SongMetadata(
            tags: ["Opener", "upbeat"],
            proficiency: .ready,
            notes: "Watch the bridge",
            cues: [SongCue(section: "Chorus", text: "Big")],
        )
        let start = try await store.updateMetadata(id: song.id, original)
        let before = try lib.bytes("songs/harbour.segue.json")

        lib.clock.advance(by: 60)
        _ = try await store.updateMetadata(
            id: song.id,
            SongMetadata(tags: ["slow"], proficiency: .pro),
        )
        lib.clock.advance(by: 60)
        let restored = try await store.updateMetadata(id: song.id, SongMetadata(start.sidecar))

        #expect(SongMetadata(restored.sidecar) == original)
        var expected = start.sidecar
        expected.updatedAt = restored.sidecar.updatedAt
        #expect(restored.sidecar == expected)
        let after = try lib.bytes("songs/harbour.segue.json")
        let stamp = { (data: Data) in
            (String(bytes: data, encoding: .utf8) ?? "")
                .split(separator: "\n").filter { !$0.contains("updatedAt") }
        }
        #expect(stamp(after) == stamp(before))
        #expect(try await store.search(query: "opener").map(\.id) == [song.id])
    }
}
