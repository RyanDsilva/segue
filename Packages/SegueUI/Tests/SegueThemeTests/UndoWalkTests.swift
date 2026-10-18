import Foundation
import Library
@testable import SegueUI
import Setlists
import Support
import Testing

/// Edit > Undo and Redo walked step by step on a real app session, with the files on disk
/// checked after every step (WS2a 3.9). Moved down from `SegueCoreUXE2ETests`
/// (`testSetlistBuilderUndoRedo`, `testSongMetadataUndo`), which keep one real Cmd-Z and one
/// Cmd-Shift-Z each through the window (docs/test-performance.md, coverage mapping).
@MainActor
struct UndoWalkTests {
    private static let harbourID = "01JC0000000000000000000H01"
    private static let riverID = "01JC0000000000000000000R01"
    private static let fridayID = "01JC0000000000000000000F01"

    @Test
    func `builder add rename and remove undo one by one and redo in order`() async throws {
        let env = try TestEnvironment()
        try Self.seedSong(env, "harbour-lights", "Harbour Lights", id: Self.harbourID)
        try Self.seedSong(env, "river-song", "River Song", id: Self.riverID)
        try Self.seedSetlist(env, songIDs: [Self.harbourID])
        let app = try await env.openApp()
        let session = try #require(app.session)
        let manager = UndoManager()
        manager.groupsByEvent = false
        session.undoManager = manager
        let setlists = session.setlists
        let friday = try SetlistID(#require(ULID(string: Self.fridayID)))
        let river = try SongID(#require(ULID(string: Self.riverID)))
        let file = "setlists/friday.setlist.json"

        try await step(manager) { _ = await setlists.add(river, to: friday) }
        #expect(try Self.entryCount(env, file) == 2)
        try await step(manager) { await setlists.rename(friday, to: "Friday Late") }
        #expect(try Self.name(env, file) == "Friday Late")
        try await step(manager) { await setlists.remove(in: friday, atOffsets: [0]) }
        #expect(try Self.entryCount(env, file) == 1)

        #expect(manager.undoActionName == "Remove Song")
        manager.undo()
        try await env.waitFor { (try? Self.entryCount(env, file)) == 2 ? true : nil }
        #expect(manager.undoActionName == "Rename Setlist")
        manager.undo()
        try await env.waitFor { (try? Self.name(env, file)) == "Friday" ? true : nil }
        #expect(manager.undoActionName == "Add Song")
        manager.undo()
        try await env.waitFor { (try? Self.entryCount(env, file)) == 1 ? true : nil }

        #expect(manager.redoActionName == "Add Song")
        manager.redo()
        try await env.waitFor { (try? Self.entryCount(env, file)) == 2 ? true : nil }
        #expect(manager.redoActionName == "Rename Setlist")
        manager.redo()
        try await env.waitFor { (try? Self.name(env, file)) == "Friday Late" ? true : nil }
        #expect(try Self.entryCount(env, file) == 2)
    }

    @Test
    func `song tag and proficiency undo one by one and redo in order`() async throws {
        let env = try TestEnvironment()
        try Self.seedSong(env, "harbour-lights", "Harbour Lights", id: nil)
        let app = try await env.openApp()
        let session = try #require(app.session)
        let manager = UndoManager()
        manager.groupsByEvent = false
        session.undoManager = manager
        let library = session.library
        let id = try #require(library.catalog.first?.id)
        let sidecar = "songs/harbour-lights.segue.json"

        try await step(manager) { await library.editMetadata(id: id) { $0.tags = ["opener"] } }
        #expect(try Self.field(env, sidecar, "tags") as? [String] == ["opener"])
        try await step(manager) { await library.editMetadata(id: id) { $0.proficiency = .ready } }
        #expect(try Self.field(env, sidecar, "proficiency") as? String == "ready")

        #expect(manager.undoActionName == "Change Proficiency")
        manager.undo()
        try await env.waitFor { (try? Self.field(env, sidecar, "proficiency")) == nil ? true : nil }
        #expect(try Self.field(env, sidecar, "tags") as? [String] == ["opener"])
        #expect(manager.undoActionName == "Edit Tags")
        manager.undo()
        try await env.waitFor {
            (try? Self.field(env, sidecar, "tags") as? [String])?.isEmpty == true ? true : nil
        }
        manager.redo()
        try await env.waitFor {
            (try? Self.field(env, sidecar, "tags") as? [String]) == ["opener"] ? true : nil
        }
        manager.redo()
        try await env.waitFor {
            (try? Self.field(env, sidecar, "proficiency") as? String) == "ready" ? true : nil
        }
    }

    /// One user action: one undo group, as one menu click or keystroke makes.
    private func step(_ manager: UndoManager, _ action: () async -> Void) async throws {
        manager.beginUndoGrouping()
        await action()
        manager.endUndoGrouping()
    }

    // MARK: Files, written and read as the E2E suite does

    private static func seedSong(
        _ env: TestEnvironment,
        _ slug: String,
        _ title: String,
        id: String?,
    ) throws {
        try FileManager.default.createDirectory(
            at: env.libraryURL.appending(path: "songs", directoryHint: .isDirectory),
            withIntermediateDirectories: true,
        )
        try env.write("{title: \(title)}\n[G]Lanterns on the [C]water\n", to: "songs/\(slug).cho")
        if let id {
            try env.write(
                #"{"schemaVersion": 3, "id": "\#(id)", "createdAt": "2026-10-01T10:00:00Z", "#
                    + #""updatedAt": "2026-10-01T10:00:00Z"}"#,
                to: "songs/\(slug).segue.json",
            )
        }
    }

    private static func seedSetlist(_ env: TestEnvironment, songIDs: [String]) throws {
        try FileManager.default.createDirectory(
            at: env.libraryURL.appending(path: "setlists", directoryHint: .isDirectory),
            withIntermediateDirectories: true,
        )
        let entries = songIDs.enumerated().map { offset, song in
            #"{"itemId": "01JC0000000000000000000T0\#(offset)", "songId": "\#(song)"}"#
        }
        try env.write(
            #"{"schemaVersion": 2, "id": "\#(fridayID)", "name": "Friday", "#
                + #""createdAt": "2026-10-10T10:00:00Z", "updatedAt": "2026-10-10T10:00:00Z", "#
                + #""entries": [\#(entries.joined(separator: ", "))]}"#,
            to: "setlists/friday.setlist.json",
        )
    }

    private static func field(_ env: TestEnvironment, _ path: String, _ key: String) throws
        -> Any?
    {
        let data = try Data(env.read(path).utf8)
        let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        return object[key]
    }

    private static func entryCount(_ env: TestEnvironment, _ path: String) throws -> Int {
        try #require(field(env, path, "entries") as? [Any]).count
    }

    private static func name(_ env: TestEnvironment, _ path: String) throws -> String? {
        try field(env, path, "name") as? String
    }
}
