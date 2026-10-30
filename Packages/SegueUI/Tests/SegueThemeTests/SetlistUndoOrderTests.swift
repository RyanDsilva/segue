import Foundation
import Library
@testable import SegueUI
import Setlists
import Testing

/// Setlist writes are serialized (R154): two edits in flight undo as two correct steps,
/// and an Undo pressed while an edit is in flight restores the snapshot that edit left.
@MainActor
struct SetlistUndoOrderTests {
    private struct Fixture {
        let app: AppModel
        let setlists: SetlistsViewModel
        let manager: UndoManager
        let id: SetlistID
        let titles: [SongID: String]
    }

    private static func fixture(_ env: TestEnvironment) async throws -> Fixture {
        let app = try await env.openApp()
        let session = try #require(app.session)
        let setlists = session.setlists
        let created = try #require(await setlists.create(name: "Friday"))
        var titles: [SongID: String] = [:]
        for title in ["Alpha", "Bravo", "Charlie", "Delta"] {
            let song = try await session.library.createSong(source: "{title: \(title)}\nLa\n")
            titles[song.id] = title
            await setlists.add(song.id, to: created.id)
        }
        // Set after seeding: the seeding steps are not under test.
        let manager = UndoManager()
        manager.groupsByEvent = false
        session.undoManager = manager
        return Fixture(
            app: app,
            setlists: setlists,
            manager: manager,
            id: created.id,
            titles: titles,
        )
    }

    private static func titles(_ fixture: Fixture) async -> [String] {
        await fixture.setlists.writeWork?.value
        let setlist = await fixture.setlists.store.setlist(id: fixture.id)
        return (setlist?.entries ?? []).compactMap { $0.songId.flatMap { fixture.titles[$0] } }
    }

    @Test
    func `two edits in flight undo and redo as two ordered snapshots`() async throws {
        let env = try TestEnvironment()
        let fixture = try await Self.fixture(env)
        let setlists = fixture.setlists
        let id = fixture.id

        fixture.manager.beginUndoGrouping()
        async let moved: Void = setlists.move(in: id, fromOffsets: [3], toOffset: 0)
        async let removed: Void = setlists.remove(in: id, atOffsets: [1])
        _ = await (moved, removed)
        fixture.manager.endUndoGrouping()
        let edited = await Self.titles(fixture)
        #expect(edited.count == 3)

        fixture.manager.undo()
        #expect(await Self.titles(fixture) == ["Alpha", "Bravo", "Charlie", "Delta"])
        fixture.manager.redo()
        #expect(await Self.titles(fixture) == edited)
    }

    @Test
    func `undo during an edit in flight restores the snapshot it registered`() async throws {
        let env = try TestEnvironment()
        let fixture = try await Self.fixture(env)
        let setlists = fixture.setlists
        let id = fixture.id

        fixture.manager.beginUndoGrouping()
        await setlists.move(in: id, fromOffsets: [3], toOffset: 0)
        fixture.manager.endUndoGrouping()
        #expect(await Self.titles(fixture) == ["Delta", "Alpha", "Bravo", "Charlie"])

        // The Remove is in flight when Undo (of the Move) is pressed: the Undo runs after
        // it, writing the Move's before-snapshot, so the file never mixes the two.
        let removal = Task { await setlists.remove(in: id, atOffsets: [1]) }
        await Task.yield()
        fixture.manager.undo()
        fixture.manager.beginUndoGrouping()
        await removal.value
        fixture.manager.endUndoGrouping()
        #expect(await Self.titles(fixture) == ["Alpha", "Bravo", "Charlie", "Delta"])
    }
}
