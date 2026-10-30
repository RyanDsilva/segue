import AppKit
import Foundation
import Library
@testable import SegueUI
import Shows
import Support
import Testing

/// A failed End Show is offered again at once through the resume prompt (R154).
extension StageWindowSuites.LiveHardeningLifecycleTests {
    @Test
    func `a failed End Show offers the show again at once`() async throws {
        _ = NSApplication.shared
        let env = try TestEnvironment()
        let disk = ToggleFailingFileSystem()
        env.fileSystem = disk
        let app = try await env.openApp()
        let fixture = try await LiveFixture(app: app, titles: ["Alpha", "Bravo"])
        app.liveSettings.settings.hiddenChecklistItems = Set(ChecklistItem.allCases)
        #expect(await app.startShow(fixture.setlist, kind: .gig))
        let live = try #require(app.live)
        defer { StageWindowController.shared.close() }
        let id = live.state.record.id

        disk.failing = [LibraryRoot.showSuffix]
        live.dispatch(.endShow)
        live.confirmEnd()
        let offered = try await env.waitFor { app.pendingResume }
        #expect(app.live == nil)
        #expect(offered.id == id)
        #expect(!offered.isFinished)
        #expect(app.session?.library.errorMessage?.contains("It is still open") == true)

        // End Show in the prompt, with writes working again, closes it into the gig log.
        disk.failing = []
        await app.endPendingShow()
        #expect(app.pendingResume == nil)
        let ended = try #require(await app.session?.stores.shows.reloaded(id))
        #expect(ended.isFinished)
    }

    @Test
    func `a failed End Show from the prompt can be retried`() async throws {
        _ = NSApplication.shared
        let env = try TestEnvironment()
        let disk = ToggleFailingFileSystem()
        env.fileSystem = disk
        let app = try await env.openApp()
        let fixture = try await LiveFixture(app: app, titles: ["Alpha", "Bravo"])
        app.liveSettings.settings.hiddenChecklistItems = Set(ChecklistItem.allCases)
        #expect(await app.startShow(fixture.setlist, kind: .gig))
        let live = try #require(app.live)
        defer { StageWindowController.shared.close() }

        disk.failing = [LibraryRoot.showSuffix]
        live.dispatch(.endShow)
        live.confirmEnd()
        _ = try await env.waitFor { app.pendingResume }

        await app.endPendingShow()
        let again = try #require(app.pendingResume)
        #expect(!again.isFinished)

        disk.failing = []
        await app.endPendingShow()
        #expect(app.pendingResume == nil)
        #expect(try #require(await app.session?.stores.shows.reloaded(again.id)).isFinished)
    }
}
