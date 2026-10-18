import Foundation
import Library
import Setlists
import Support
import Testing

/// Setlist delete-to-Trash, restore, and the whole-value `replace` that undo writes back
/// (WS2a 3.3, 3.9), on a real library folder.
struct SetlistStoreTrashUndoTests {
    private static func friday(_ lib: TestLibrary) async throws -> (SetlistStore, Setlist) {
        let library = try await lib.openStore()
        let first = try await library.createSong(source: "{title: One}\nLa\n")
        let second = try await library.createSong(source: "{title: Two}\nLa\n")
        let (store, _) = try await lib.loadSetlists()
        let setlist = try await store.create(name: "Friday")
        return try await (store, store.insertSongs([first.id, second.id], into: setlist.id))
    }

    @Test
    func `restore brings back the identical setlist`() async throws {
        let lib = try TestLibrary()
        let (store, setlist) = try await Self.friday(lib)
        let bytes = try lib.bytes("setlists/friday.setlist.json")

        let receipt = try await store.delete(setlist.id)
        let restored = try await store.restore(receipt)

        #expect(restored == setlist)
        #expect(await store.setlist(id: setlist.id) == setlist)
        #expect(try lib.bytes("setlists/friday.setlist.json") == bytes)
        #expect(lib.trashedNames().isEmpty)
        let (reloaded, _) = try await lib.loadSetlists()
        #expect(await reloaded.setlist(id: setlist.id) == setlist)
    }

    @Test
    func `restore under a reused name gets the next free slug`() async throws {
        let lib = try TestLibrary()
        let (store, setlist) = try await Self.friday(lib)
        let receipt = try await store.delete(setlist.id)
        _ = try await store.create(name: "Friday")

        let restored = try await store.restore(receipt)

        #expect(restored?.id == setlist.id)
        #expect(lib.exists("setlists/friday-2.setlist.json"))
        #expect(await store.fileURL(for: setlist.id) == lib.url("setlists/friday-2.setlist.json"))
    }

    @Test
    func `restore after the trash was emptied changes nothing`() async throws {
        let lib = try TestLibrary()
        let (store, setlist) = try await Self.friday(lib)
        let receipt = try await store.delete(setlist.id)
        try FileManager.default.removeItem(at: receipt.items[0].trashed)

        await #expect(throws: TrashRestoreError.goneFromTrash(receipt.items[0].trashed)) {
            try await store.restore(receipt)
        }
        #expect(await store.all().isEmpty)
    }

    @Test
    func `replace writes the snapshot back and stamps only updatedAt`() async throws {
        let lib = try TestLibrary()
        let (store, before) = try await Self.friday(lib)
        let snapshotBytes = try lib.bytes("setlists/friday.setlist.json")
        try await store.rename(before.id, to: "Saturday")
        try await store.remove(in: before.id, atOffsets: [0])
        lib.clock.advance(by: 60)

        let replaced = try await store.replace(before)

        var expected = before
        expected.updatedAt = SegueJSON.stamp(lib.clock.now())
        #expect(replaced == expected)
        #expect(await store.fileURL(for: before.id) == lib.url("setlists/friday.setlist.json"))
        // Byte-for-byte the snapshot's file, apart from the new updatedAt.
        var onDisk = try #require(try JSONSerialization.jsonObject(
            with: lib.bytes("setlists/friday.setlist.json"),
        ) as? [String: Any])
        var snapshot = try #require(try JSONSerialization.jsonObject(with: snapshotBytes)
            as? [String: Any])
        #expect(onDisk["updatedAt"] as? String != snapshot["updatedAt"] as? String)
        onDisk["updatedAt"] = nil
        snapshot["updatedAt"] = nil
        #expect(NSDictionary(dictionary: onDisk) == NSDictionary(dictionary: snapshot))
    }

    @Test
    func `replace refuses a read-only setlist`() async throws {
        let lib = try TestLibrary()
        let id = SetlistID(lib.ids.next())
        let future = #"{"schemaVersion": 7, "id": "\#(id)", "name": "Future", "entries": []}"#
        try lib.write(future, to: "setlists/future.setlist.json")
        let (store, _) = try await lib.loadSetlists()
        let setlist = try #require(await store.setlist(id: id))
        let reason = ReadOnlyReason.newerSchema(found: 7, supported: Setlist.currentSchemaVersion)

        await #expect(throws: SetlistError.readOnly(id, reason)) {
            try await store.replace(setlist)
        }
        #expect(try lib.read("setlists/future.setlist.json") == future)
    }
}
