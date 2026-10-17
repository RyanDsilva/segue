import AppKit
import CoreText
import Foundation
import Library
import LiveLayout
@testable import SegueUI
import Setlists
import Shows
import Support
import SwiftUI
import Synchronization
import Testing

/// Regression tests for the phase 2 review (docs/reviews/phase2-review.md) at the app
/// layer, part 2: ending, quitting, claims, unreadable songs, library switching, scroll.
extension StageWindowSuites {
    @MainActor
    @Suite(.serialized)
    struct LiveHardeningLifecycleTests {
        // MARK: #10 Cmd-W / Cmd-Q on stage ask first; ends run the end Shortcut

        @Test
        func `closing or quitting the stage goes through the end confirmation`() async throws {
            _ = NSApplication.shared
            let env = try TestEnvironment()
            let app = try await env.openApp()
            let fixture = try await LiveFixture(app: app, titles: ["Alpha", "Bravo"])
            app.liveSettings.settings.hiddenChecklistItems = Set(ChecklistItem.allCases)
            #expect(await app.startShow(fixture.setlist, kind: .gig))
            let live = try #require(app.live)
            defer { StageWindowController.shared.close() }

            #expect(try LiveKeyInput.handle(
                LiveHardeningTests.key(13, "w", command: true),
                session: live,
            ))
            #expect(live.overlay == .endConfirm)
            #expect(!live.quitsAfterEnding)
            #expect(app.live === live)
            #expect(try LiveKeyInput.handle(
                LiveHardeningTests.key(53, repeat: false),
                session: live,
            ))
            #expect(live.overlay == nil)

            #expect(try LiveKeyInput.handle(
                LiveHardeningTests.key(12, "q", command: true),
                session: live,
            ))
            #expect(live.overlay == .endConfirm)
            #expect(live.quitsAfterEnding)
            live.cancelEnd()
            #expect(!live.quitsAfterEnding)

            // A quit from the menu or Dock: cancelled, the confirmation shows instead.
            UnsavedChangesGuard.shared.app = app
            #expect(UnsavedChangesGuard.shared.shouldTerminate() == .terminateCancel)
            #expect(live.overlay == .endConfirm)
            #expect(live.quitsAfterEnding)
            live.cancelEnd()
        }

        @Test
        func `a stale show closed at launch runs the end Shortcut`() async throws {
            _ = NSApplication.shared
            let env = try TestEnvironment()
            let app = try await env.openApp()
            let fixture = try await LiveFixture(app: app, titles: ["Alpha", "Bravo"])
            app.liveSettings.settings.hiddenChecklistItems = Set(ChecklistItem.allCases)
            #expect(await app.startShow(fixture.setlist, kind: .gig))
            let id = try #require(app.live?.state.record.id)
            // The stage goes away without ending (as after a crash).
            StageWindowController.shared.close()
            #expect(app.live == nil)
            try await LiveHardeningTests.waitUntilReleased(id, env: env)
            #expect(try env.shortcutsRun() == ["Gig Mode On"])

            env.clock.advance(by: 13 * 60 * 60)
            let relaunched = try await env.openApp()
            #expect(relaunched.pendingResume == nil)
            #expect(try env.shortcutsRun() == ["Gig Mode On", "Gig Mode Off"])
        }

        @Test
        func `a stale rehearsal runs the end Shortcut only when rehearsals run Shortcuts`(
        ) async throws {
            _ = NSApplication.shared
            let env = try TestEnvironment()
            let app = try await env.openApp()
            let fixture = try await LiveFixture(app: app, titles: ["Alpha", "Bravo"])
            app.liveSettings.settings.hiddenChecklistItems = Set(ChecklistItem.allCases)
            #expect(await app.startShow(fixture.setlist, kind: .rehearsal))
            let id = try #require(app.live?.state.record.id)
            StageWindowController.shared.close()
            try await LiveHardeningTests.waitUntilReleased(id, env: env)

            env.clock.advance(by: 13 * 60 * 60)
            _ = try await env.openApp()
            #expect(try env.shortcutsRun().isEmpty)
        }

        // MARK: #9 one run per show, across app instances on the same library

        @Test
        func `a show on stage is never offered for resume by another instance`() async throws {
            _ = NSApplication.shared
            let env = try TestEnvironment()
            let app = try await env.openApp()
            let fixture = try await LiveFixture(app: app, titles: ["Alpha", "Bravo"])
            app.liveSettings.settings.hiddenChecklistItems = Set(ChecklistItem.allCases)
            #expect(await app.startShow(fixture.setlist, kind: .gig))
            let id = try #require(app.live?.state.record.id)

            let second = try await env.openApp()
            #expect(second.pendingResume == nil)

            StageWindowController.shared.close()
            try await LiveHardeningTests.waitUntilReleased(id, env: env)
            let third = try await env.openApp()
            #expect(third.pendingResume?.id == id)
            #expect(await third.resumePendingShow())
            let live = try #require(third.live)
            live.confirmEnd()
            _ = try await env.waitFor { third.live == nil ? true : nil }
        }

        // MARK: #11 a current song that never loaded

        @Test
        func `a song that cannot be read says so instead of a blank stage`() async throws {
            _ = NSApplication.shared
            let env = try TestEnvironment()
            let app = try await env.openApp()
            let fixture = try await LiveFixture(app: app, titles: ["Alpha", "Bravo", "Charlie"])
            app.liveSettings.settings.hiddenChecklistItems = Set(ChecklistItem.allCases)
            #expect(await app.startShow(fixture.setlist, kind: .gig))
            let live = try #require(app.live)
            defer { StageWindowController.shared.close() }
            live.setViewport(LayoutSize(width: 1390, height: 700))
            let bravo = fixture.songs[1]
            try FileManager.default
                .removeItem(at: env.libraryURL.appending(path: bravo.relativePath))
            _ = try await fixture.library.refresh()

            live.dispatch(.next)
            _ = try await env.waitFor { live.positionText == "2 of 3" ? true : nil }
            #expect(live.state.current?.song == nil)
            #expect(live.currentModel == nil)
            #expect(live.plan == nil)
            try LiveHardeningTests.renderStage(live, name: "song-unavailable")
            live.dispatch(.next)
            _ = try await env.waitFor { live.positionText == "3 of 3" ? true : nil }
            #expect(live.plan != nil)
        }

        // MARK: #13 no library switch mid-show

        @Test
        func `the library cannot be switched while a show is on stage`() async throws {
            _ = NSApplication.shared
            let env = try TestEnvironment()
            let app = try await env.openApp()
            let fixture = try await LiveFixture(app: app, titles: ["Alpha"])
            app.liveSettings.settings.hiddenChecklistItems = Set(ChecklistItem.allCases)
            #expect(app.canSwitchLibrary)
            #expect(await app.startShow(fixture.setlist, kind: .gig))
            let live = try #require(app.live)
            defer { StageWindowController.shared.close() }
            let session = try #require(app.session)
            #expect(!app.canSwitchLibrary)
            await app.chooseLibrary()
            await app.createLibrary()
            #expect(app.live === live)
            #expect(app.session === session)
            #expect(live.isKeepingAwake)
        }

        // MARK: #14 auto-scroll settles at the bottom

        @Test
        func `auto-scroll settles at the bottom and one press starts it over`() async throws {
            _ = NSApplication.shared
            let env = try TestEnvironment()
            let app = try await env.openApp()
            let fixture = try await LiveFixture(
                app: app,
                titles: ["Long"],
                lines: 240,
                duration: "3:00",
            )
            app.liveSettings.settings.hiddenChecklistItems = Set(ChecklistItem.allCases)
            #expect(await app.startShow(fixture.setlist, kind: .rehearsal))
            let live = try #require(app.live)
            defer { StageWindowController.shared.close() }
            live.setViewport(LayoutSize(width: 1390, height: 700))
            live.dispatch(.toggleAutoScroll)
            env.clock.advance(by: 400)
            #expect(live.scrollFraction(at: env.clock.now()) == 1)
            // The flush tick records the end: the display stops ticking.
            live.settleScroll()
            #expect(!live.isAutoScrolling)
            #expect(live.scrollStatus(at: env.clock.now()) == "Scroll at end")
            live.dispatch(.toggleAutoScroll)
            #expect(live.isAutoScrolling)
            #expect(live.scrollFraction(at: env.clock.now()) == 0)

            // Without the tick having run, one press at the bottom still starts over.
            env.clock.advance(by: 400)
            live.dispatch(.toggleAutoScroll)
            #expect(live.isAutoScrolling)
            #expect(live.scrollFraction(at: env.clock.now()) == 0)
        }

        // MARK: #15 auto-scroll runs on a monotonic clock

        @Test
        func `live mode scrolls on a monotonic clock by default`() throws {
            let env = try TestEnvironment()
            let live = LiveDependencies(settings: LiveSettingsStore(defaults: env.defaults))
            #expect(live.scrollClock is MonotonicClock)
        }

        // MARK: Nits: scroll durability, bindings schema notice

        @Test
        func `a scroll change reaches disk within a second`() async throws {
            let env = try TestEnvironment()
            let app = try await env.openApp()
            let stores = try #require(app.session?.stores)
            let environment = ShowEnvironment(
                store: stores.shows,
                songs: stores.library,
                clock: stores.clock,
                ids: stores.ids,
            )
            #expect(LiveSession.flushTick + .seconds(environment.scrollWriteInterval)
                <= .seconds(1))
        }

        @Test
        func `a bindings file from a newer Segue is applied as far as it can be`(
        ) async throws {
            _ = NSApplication.shared
            let env = try TestEnvironment()
            let url = env.scratch.appending(path: "bindings.json")
            try Data("""
            {"schemaVersion": 2, "bindings": [
              {"trigger": {"key": "pageDown"}, "command": "next"},
              {"trigger": {"pedal": 1}, "command": "next"}
            ]}
            """.utf8).write(to: url)
            env.bindingsURL = url
            let app = try await env.openApp()
            let fixture = try await LiveFixture(app: app, titles: ["Alpha", "Bravo"])
            app.liveSettings.settings.hiddenChecklistItems = Set(ChecklistItem.allCases)
            #expect(await app.startShow(fixture.setlist, kind: .gig))
            let live = try #require(app.live)
            defer { StageWindowController.shared.close() }
            #expect(live.context.bindings.command(for: .key(KeyStroke(KeyStroke.pageDown)))
                == .next)
            let message = try #require(app.session?.library.errorMessage)
            #expect(message.contains("newer version of Segue"))
        }
    }
}
