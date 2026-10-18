import Foundation
import Library
import Support
import Testing

/// A new song's files follow its `{title}` while its editor session is open (WS2a 3.4, A18).
struct LibraryRenameTests {
    @Test
    func `rename moves both files, keeps the ID and updates the index path`() async throws {
        let lib = try TestLibrary()
        let store = try await lib.openStore()
        let song = try await store.createSong(source: "{title: Ha}\nLine\n")
        #expect(song.relativePath == "songs/ha.cho")
        let edited = try await store.updateSong(id: song.id, source: "{title: Harbour}\nLine\n")

        let renamed = try await store.renameSong(id: song.id, toSlugFor: "Harbour")

        #expect(renamed.id == song.id)
        #expect(renamed.relativePath == "songs/harbour.cho")
        #expect(!lib.exists("songs/ha.cho"))
        #expect(!lib.exists("songs/ha.segue.json"))
        #expect(try lib.read("songs/harbour.cho") == "{title: Harbour}\nLine\n")
        #expect(try lib.bytes("songs/harbour.segue.json").isEmpty == false)
        #expect(renamed.revision == edited.revision)
        #expect(try await store.search(query: "harbour")
            .map(\.relativePath) == ["songs/harbour.cho"])
        // A relaunch finds the same song (ID from the moved sidecar) at the new path.
        let reopened = try await lib.openStore()
        #expect(try await reopened.song(id: song.id)?.relativePath == "songs/harbour.cho")
        // Saving again after the rename is not a conflict.
        _ = try await store.updateSong(
            id: song.id,
            source: "{title: Harbour}\nMore\n",
            basedOn: renamed.revision,
        )
    }

    @Test
    func `rename picks the next free slug and is a no-op when nothing changes`() async throws {
        let lib = try TestLibrary()
        let store = try await lib.openStore()
        _ = try await store.createSong(source: "{title: Harbour}\nTaken\n")
        let song = try await store.createSong(source: "{title: Ha}\nMine\n")

        let renamed = try await store.renameSong(id: song.id, toSlugFor: "Harbour")
        #expect(renamed.relativePath == "songs/harbour-2.cho")
        let again = try await store.renameSong(id: song.id, toSlugFor: "Harbour")
        #expect(again.relativePath == "songs/harbour-2.cho")
        #expect(lib.exists("songs/harbour.cho"))
    }
}
