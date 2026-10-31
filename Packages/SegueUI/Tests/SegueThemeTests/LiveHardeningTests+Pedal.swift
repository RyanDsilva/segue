import AppKit
import Foundation
import LiveLayout
@testable import SegueUI
import Shows
import Testing

/// Pedal safety (R154): held keys repeat only scroll and zoom, a page turn while a song
/// change is in flight is dropped, and Page Down at the last song stays put.
extension StageWindowSuites.LiveHardeningTests {
    @Test
    func `held scroll and zoom keys still repeat`() async throws {
        _ = NSApplication.shared
        let env = try TestEnvironment()
        let app = try await env.openApp()
        let fixture = try await LiveFixture(app: app, titles: ["Long"], lines: 240)
        app.liveSettings.settings.hiddenChecklistItems = Set(ChecklistItem.allCases)
        #expect(await app.startShow(fixture.setlist, kind: .rehearsal))
        let live = try #require(app.live)
        defer { StageWindowController.shared.close() }
        live.setViewport(LayoutSize(width: 1390, height: 700))
        #expect(try #require(live.plan).needsScroll)

        for _ in 0 ..< 3 {
            #expect(try LiveKeyInput.handle(Self.key(125, repeat: true), session: live))
        }
        _ = try await env.waitFor {
            live.scrollFraction(at: env.clock.now()) > 0 ? true : nil
        }
        #expect(try LiveKeyInput.handle(
            Self.key(24, "=", command: true, repeat: true),
            session: live,
        ))
        #expect(live.currentPrefs?.zoom == 1.1)
    }

    // MARK: Page turns while a song change is in flight (R154, R158 Q1)

    @Test
    func `a double page turn never moves two songs`() async throws {
        _ = NSApplication.shared
        let env = try TestEnvironment()
        let app = try await env.openApp()
        let fixture = try await LiveFixture(app: app, titles: ["Alpha", "Bravo", "Charlie"])
        app.liveSettings.settings.hiddenChecklistItems = Set(ChecklistItem.allCases)
        #expect(await app.startShow(fixture.setlist, kind: .gig))
        let live = try #require(app.live)
        defer { StageWindowController.shared.close() }

        live.dispatch(.pageForward)
        live.dispatch(.pageForward)
        _ = try await env.waitFor { live.positionText == "2 of 3" ? true : nil }
        try await Task.sleep(for: .milliseconds(200))
        #expect(live.positionText == "2 of 3")

        live.perform(.next)
        _ = try await env.waitFor { live.positionText == "3 of 3" ? true : nil }
        live.dispatch(.pageBack)
        live.dispatch(.pageBack)
        _ = try await env.waitFor { live.positionText == "2 of 3" ? true : nil }
        try await Task.sleep(for: .milliseconds(200))
        #expect(live.positionText == "2 of 3")
    }

    @Test
    func `page forward at the bottom of the last song stays put`() async throws {
        _ = NSApplication.shared
        let env = try TestEnvironment()
        let app = try await env.openApp()
        let fixture = try await LiveFixture(app: app, titles: ["Alpha", "Bravo", "Charlie"])
        app.liveSettings.settings.hiddenChecklistItems = Set(ChecklistItem.allCases)
        #expect(await app.startShow(fixture.setlist, kind: .gig))
        let live = try #require(app.live)
        defer { StageWindowController.shared.close() }

        live.perform(.next)
        live.perform(.next)
        _ = try await env.waitFor { live.positionText == "3 of 3" ? true : nil }
        let request = try await #require(app.session).library.createSong(
            source: LiveFixture.source(title: "Yankee Request", lines: 4),
        )
        live.perform(.addRequest(request.id, note: nil))
        _ = try await env.waitFor { live.queuedRequests.count == 1 ? true : nil }
        let advanced = live.state.record.events.count { $0.kind == .advanced }

        live.dispatch(.pageForward)
        #expect(live.indicator == "Last song")
        try await Task.sleep(for: .milliseconds(200))
        #expect(live.positionText == "3 of 3")
        #expect(live.state.record.events.count { $0.kind == .advanced } == advanced)

        // An explicit Next still ends the chart.
        live.dispatch(.next)
        _ = try await env.waitFor { live.positionText == "End of 3" ? true : nil }
    }
}
