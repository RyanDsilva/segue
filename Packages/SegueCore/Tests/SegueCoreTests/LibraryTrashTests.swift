import Foundation
import Library
import Support
import Testing

/// Delete Song and its undo (WS2a 3.3) on a real library folder. Trashed files go to the
/// test library's stand-in Trash folder; one test uses the real Trash and empties its result.
struct LibraryTrashTests {
    private static let harbour = "{title: Harbour Lights}\n[G]Lanterns on the [C]water\n"

    @Test
    func `delete moves both files to the trash and the song leaves index and search`(
    ) async throws {
        let lib = try TestLibrary()
        let store = try await lib.openStore()
        let song = try await store.createSong(source: Self.harbour)
        let sidecarBytes = try lib.bytes("songs/harbour-lights.segue.json")

        let receipt = try await store.deleteSong(id: song.id)

        #expect(!lib.exists("songs/harbour-lights.cho"))
        #expect(!lib.exists("songs/harbour-lights.segue.json"))
        #expect(lib.trashedNames() == ["harbour-lights.cho", "harbour-lights.segue.json"])
        #expect(receipt.items.map(\.original.lastPathComponent)
            == ["harbour-lights.cho", "harbour-lights.segue.json"])
        #expect(receipt.leftBehind.isEmpty)
        #expect(try await store.song(id: song.id) == nil)
        #expect(try await store.search(query: "lanterns").isEmpty)
        try await store.refresh()
        #expect(try await store.allSongs().isEmpty)
        // A relaunch (fresh index scan) does not resurrect it either.
        #expect(try await lib.openStore().allSongs().isEmpty)

        let restored = try #require(try await store.restoreSong(receipt))
        #expect(restored.id == song.id)
        #expect(restored.relativePath == "songs/harbour-lights.cho")
        #expect(try lib.read("songs/harbour-lights.cho") == Self.harbour)
        #expect(try lib.bytes("songs/harbour-lights.segue.json") == sidecarBytes)
        #expect(try await store.search(query: "lanterns").map(\.id) == [song.id])
        #expect(lib.trashedNames().isEmpty)
    }

    @Test
    func `restore under a reused slug lands as slug-2 with the same ID`() async throws {
        let lib = try TestLibrary()
        let store = try await lib.openStore()
        let song = try await store.createSong(source: Self.harbour)
        let receipt = try await store.deleteSong(id: song.id)
        let other = try await store.createSong(source: "{title: Harbour Lights}\nNew words\n")
        #expect(other.relativePath == "songs/harbour-lights.cho")

        let restored = try #require(try await store.restoreSong(receipt))

        #expect(restored.id == song.id)
        #expect(restored.relativePath == "songs/harbour-lights-2.cho")
        #expect(try lib.read("songs/harbour-lights-2.cho") == Self.harbour)
        #expect(lib.exists("songs/harbour-lights-2.segue.json"))
        #expect(try await store.allSongs().map(\.id).sorted() == [song.id, other.id].sorted())
    }

    @Test
    func `restore fails cleanly when the trashed file is gone`() async throws {
        let lib = try TestLibrary()
        let store = try await lib.openStore()
        let song = try await store.createSong(source: Self.harbour)
        let receipt = try await store.deleteSong(id: song.id)
        try FileManager.default.removeItem(at: receipt.items[0].trashed)

        await #expect(throws: TrashRestoreError.goneFromTrash(receipt.items[0].trashed)) {
            try await store.restoreSong(receipt)
        }
        // Nothing moved: the sidecar is still in the trash, no song came back.
        #expect(lib.trashedNames() == ["harbour-lights.segue.json"])
        #expect(!lib.exists("songs/harbour-lights.segue.json"))
        #expect(try await store.allSongs().isEmpty)
    }

    @Test
    func `a sidecar that cannot be trashed is left behind and the song is still deleted`(
    ) async throws {
        let lib = try TestLibrary()
        let fileSystem = InstrumentedFileSystem()
        let store = try await lib.openStore(fileSystem: fileSystem)
        let song = try await store.createSong(source: Self.harbour)
        fileSystem.fail(.trash, suffix: ".segue.json")

        let receipt = try await store.deleteSong(id: song.id)

        #expect(receipt.items.map(\.original.lastPathComponent) == ["harbour-lights.cho"])
        #expect(receipt.leftBehind == [lib.url("songs/harbour-lights.segue.json")])
        #expect(!lib.exists("songs/harbour-lights.cho"))
        #expect(try await store.song(id: song.id) == nil)
        // The stray sidecar is not a song.
        try await store.refresh()
        #expect(try await store.allSongs().isEmpty)
    }

    @Test
    func `a read-only song can be deleted`() async throws {
        let lib = try TestLibrary()
        let id = SongID(lib.ids.next())
        try lib.write(Self.harbour, to: "songs/future.cho")
        try lib.write("{\"schemaVersion\": 99, \"id\": \"\(id)\"}", to: "songs/future.segue.json")
        let store = try await lib.openStore()
        #expect(try await store.song(id: id)?.isReadOnly == true)

        let receipt = try await store.deleteSong(id: id)

        #expect(receipt.items.count == 2)
        #expect(try await store.allSongs().isEmpty)
        await #expect(throws: LibraryError.songNotFound(id)) {
            try await store.deleteSong(id: id)
        }
    }

    @Test
    func `the system trash returns the item's new URL`() throws {
        let folder = FileManager.default.temporaryDirectory
            .appending(path: "SegueTrashProbe-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let file = folder.appending(path: "probe.cho")
        try Data("probe".utf8).write(to: file)

        let trashed = try LiveFileSystem(trash: .system).trashItem(at: file)
        // Leave the user's Trash as it was.
        defer { try? FileManager.default.removeItem(at: trashed) }

        #expect(!FileManager.default.fileExists(atPath: file.path(percentEncoded: false)))
        #expect(try Data(contentsOf: trashed) == Data("probe".utf8))
    }

    @Test
    func `the stand-in trash folder never overwrites an earlier item`() throws {
        let lib = try TestLibrary()
        try lib.write("one", to: "songs/a.segue.json")
        let first = try lib.fileSystem.trashItem(at: lib.url("songs/a.segue.json"))
        try lib.write("two", to: "songs/a.segue.json")
        let second = try lib.fileSystem.trashItem(at: lib.url("songs/a.segue.json"))

        #expect(first.lastPathComponent == "a.segue.json")
        #expect(second.lastPathComponent == "a 2.segue.json")
        #expect(try String(contentsOf: first, encoding: .utf8) == "one")
        #expect(try String(contentsOf: second, encoding: .utf8) == "two")
    }
}
