import AppKit
import Foundation
import LiveLayout
@testable import SegueUI
import Shows
import Testing

/// The Singer Screen on a second display (P9-2c 6.13, 16.5) with a fake display list: when
/// Window > Singer Screen is enabled, which display it takes, that it lays out its own singer
/// plan and follows the stage, and that it closes when its display goes or the show ends.
extension StageWindowSuites {
    @MainActor
    @Suite(.serialized)
    struct SingerScreenTests {
        @MainActor
        final class FakeDisplays: SingerDisplayList {
            var displays: [SingerDisplay]
            var stageDisplay: SingerDisplay?

            init(_ names: [String]) {
                displays = names.enumerated().map { index, name in
                    SingerDisplay(
                        name: name,
                        frame: CGRect(x: Double(index) * 1920, y: 0, width: 1920, height: 1080),
                    )
                }
                stageDisplay = displays.first
            }
        }

        static func run() async throws -> MetronomeRun {
            try await MetronomeRun(
                songs: [StageSingerViewTests.song, StageSingerViewTests.next],
                recordsAnalytics: true,
            )
        }

        @Test
        func `it needs a second display and a session, and opens beside the stage`(
        ) async throws {
            let run = try await Self.run()
            let displays = FakeDisplays(["Built-in Retina Display"])
            let screen = SingerScreenController(testing: displays)
            #expect(!screen.canOpen(run.app))
            let live = try await run.start(.gig)
            #expect(!screen.canOpen(run.app))
            displays.displays = FakeDisplays(["Built-in Retina Display", "LG UltraFine"]).displays
            #expect(screen.canOpen(run.app))
            #expect(screen.choices.isEmpty)

            screen.open(run.app)
            #expect(screen.isOpen)
            #expect(screen.display?.name == "LG UltraFine")
            #expect(run.app.liveSettings.settings.singerScreenDisplay == "LG UltraFine")
            #expect(run.analytics?.log.entries().contains { entry in
                let params = entry["params"] as? [String: String]
                return params?["segue.feature"] == "singerView"
                    && params?["segue.context"] == "screen"
            } == true)
            // The main stage keeps its chords; the setting is untouched.
            #expect(live.planView == .chart)
            #expect(!run.app.liveSettings.settings.singerView)

            // Unplugged: it closes quietly, and does not come back by itself.
            displays.displays.removeLast()
            screen.displaysChanged()
            #expect(!screen.isOpen)
            displays.displays = FakeDisplays(["Built-in Retina Display", "LG UltraFine"]).displays
            screen.displaysChanged()
            #expect(!screen.isOpen)
            try await run.end(live)
        }

        @Test
        func `the remembered display wins when it is connected`() async throws {
            let run = try await Self.run()
            let displays = FakeDisplays(["Built-in", "Left", "Right"])
            let screen = SingerScreenController(testing: displays)
            run.app.liveSettings.settings.singerScreenDisplay = "Right"
            let live = try await run.start(.rehearsal)
            #expect(screen.choices.map(\.name) == ["Left", "Right"])
            screen.open(run.app)
            #expect(screen.display?.name == "Right")
            screen.close()
            // Not connected: the first display other than the stage's.
            run.app.liveSettings.settings.singerScreenDisplay = "Gone"
            screen.open(run.app)
            #expect(screen.display?.name == "Left")
            // A chosen display from the submenu is remembered.
            screen.open(run.app, on: displays.displays[2])
            #expect(run.app.liveSettings.settings.singerScreenDisplay == "Right")
            try await run.end(live)
        }

        @Test
        func `it lays out its own singer plan and follows the stage's pass`() async throws {
            let run = try await Self.run()
            let screen = SingerScreenController(testing: FakeDisplays(["Built-in", "Wedge"]))
            let live = try await run.start(.gig)
            screen.open(run.app)
            let model = try #require(screen.screen)
            model.setViewport(LayoutSize(width: 1840, height: 900))
            let plan = try #require(model.plan)
            #expect(plan.passes.map(\.name) == live.plan?.passes.map(\.name))
            #expect(!StageSingerViewTests.hasChords(plan))
            #expect(plan.lyricSize >= 28)
            #expect(plan.blocks.allSatisfy { block in
                if case .notes = block.content {
                    return false
                }
                return true
            })
            #expect(model.keyLine == "Key A, 96")
            // The stage's own zoom, V and B never reach it (it uses the singer zoom).
            live.dispatch(.zoomIn)
            live.dispatch(.toggleBassNotes)
            live.dispatch(.toggleSingerView)
            #expect(model.plan == plan)
            live.dispatch(.toggleSingerView)
            live.dispatch(.toggleBassNotes)
            live.dispatch(.resetZoom)

            // A jump on the stage: the screen shows that pass.
            live.jump(toPass: 3)
            let now = run.env.clock.now()
            let offset = model.offset(in: plan, at: now)
            if plan.needsScroll, StagePasses.followsScroll(plan) {
                let current = StagePasses.current(in: plan, offset: offset, pinned: nil)
                #expect(current == 3)
            }
            // The next song: a new plan, laid out at once.
            live.dispatch(.next)
            _ = try await run.env.waitFor { live.positionText == "2 of 2" ? true : nil }
            #expect(model.title == "Next")
            #expect(model.plan?.passes.count != plan.passes.count)
            try await run.end(live)
        }

        @Test
        func `ending the show closes it`() async throws {
            let run = try await Self.run()
            let shared = SingerScreenController.shared
            let saved = (shared.displays, shared.makesWindows)
            defer {
                shared.displays = saved.0
                shared.makesWindows = saved.1
            }
            shared.displays = FakeDisplays(["Built-in", "Wedge"])
            shared.makesWindows = false
            let live = try await run.start(.gig)
            shared.open(run.app)
            #expect(shared.isOpen)
            try await run.end(live)
            #expect(!shared.isOpen)
        }
    }
}

extension LayoutPlan {
    fileprivate var blocks: [LayoutBlock] {
        columns.flatMap(\.blocks)
    }
}
