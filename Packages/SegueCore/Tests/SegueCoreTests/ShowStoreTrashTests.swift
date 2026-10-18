import Foundation
import Library
import Setlists
import Shows
import Support
import Testing

/// Gig delete-to-Trash and restore (WS2a 3.3) on a real temp library.
struct ShowStoreTrashTests {
    @Test
    func `restoring a trashed gig re-projects its plays`() async throws {
        let harness = try await ShowHarness()
        let (setlist, songs) = try await harness.makeSet(2)
        let show = try await ShowController.start(
            setlist: setlist,
            kind: .gig,
            environment: harness.environment(),
        )
        harness.lib.clock.advance(by: 240)
        try await show.perform(.next)
        harness.lib.clock.advance(by: 200)
        let ending = try await show.end()
        let id = ending.record.id
        let bytes = try harness.lib.bytes(harness.showPath(id))
        let statsBefore = try await harness.library.playStats()
        #expect(statsBefore[songs[0].id]?.timesPlayed == 1)

        let receipt = try await harness.shows.delete(id)

        #expect(!harness.lib.exists(harness.showPath(id)))
        #expect(harness.lib.trashedNames() == ["\(id)\(LibraryRoot.showSuffix)"])
        #expect(try await harness.library.playStats().isEmpty)
        #expect(await harness.shows.gigLog().isEmpty)

        let restored = try await harness.shows.restore(receipt)

        #expect(restored == ending.record)
        #expect(try harness.lib.bytes(harness.showPath(id)) == bytes)
        #expect(try await harness.library.playStats() == statsBefore)
        #expect(await harness.shows.gigLog().map(\.id) == [id])
        #expect(await harness.shows.fileURL(for: id) == harness.lib.url(harness.showPath(id)))
    }

    @Test
    func `restore fails cleanly when the trash was emptied`() async throws {
        let harness = try await ShowHarness()
        let (setlist, _) = try await harness.makeSet(1)
        let show = try await ShowController.start(
            setlist: setlist,
            kind: .gig,
            environment: harness.environment(),
        )
        let ending = try await show.end()
        let receipt = try await harness.shows.delete(ending.record.id)
        try FileManager.default.removeItem(at: receipt.items[0].trashed)

        await #expect(throws: TrashRestoreError.goneFromTrash(receipt.items[0].trashed)) {
            try await harness.shows.restore(receipt)
        }
        #expect(await harness.shows.gigLog().isEmpty)
    }
}
