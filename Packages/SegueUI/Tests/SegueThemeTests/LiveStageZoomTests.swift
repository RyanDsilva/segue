import AppKit
import Foundation
@testable import SegueUI
import Shows
import Testing

/// The numbers behind E2E 4 and 7 (zoom memory and the minimum lyric size), on the real app
/// model, layout engine and stores: moved down from
/// `SegueLiveE2ETests.testZoomMemoryAndMinimumLyricSize`, which keeps the real keys and one
/// check of each (docs/test-performance.md, coverage mapping). The values asserted are the
/// stage body's accessibility value (`LiveView.bodyValue`), as the E2E suite reads it.
extension StageWindowSuites {
    @MainActor
    @Suite(.serialized)
    struct LiveStageZoomTests {
        @Test
        func `zoom and columns are remembered per song and the minimum size holds`() async throws {
            _ = NSApplication.shared
            let env = try TestEnvironment()
            let app = try await env.openApp()
            let fixture = try await LiveFixture(app: app, titles: ["Alpha", "Bravo"])
            let session = try #require(app.session)
            let long = try await session.library.createSong(
                source: LiveFixture.source(title: "Long", lines: 56),
            )
            await session.setlists.add(long.id, to: fixture.setlist.id)
            let setlist = try #require(session.setlists.setlist(fixture.setlist.id))
            app.liveSettings.settings.hiddenChecklistItems = Set(ChecklistItem.allCases)
            app.liveSettings.settings.minLyricSize = 30
            #expect(await app.startShow(setlist, kind: .gig))
            let live = try #require(app.live)
            defer { StageWindowController.shared.close() }
            // The stage window lays the song out for its real screen; wait until it has.
            let fitted = try await Self.settledLyricSize(live)
            let body = { try LiveView.bodyValue(#require(live.plan), fraction: 0) }

            // The fitted size respects the minimum.
            #expect(fitted >= 30)

            // Zoom song A; song B is unaffected; A keeps its zoom on return.
            live.dispatch(.zoomIn)
            let zoomed = try #require(live.plan?.lyricSize)
            #expect(zoomed != fitted)
            live.dispatch(.next)
            _ = try await env.waitFor { live.positionText == "2 of 3" ? true : nil }
            #expect(live.currentPrefs?.zoom == 1)
            live.dispatch(.previous)
            _ = try await env.waitFor { live.positionText == "1 of 3" ? true : nil }
            #expect(try await Self.settledLyricSize(live) == zoomed, "fitted \(fitted)")
            #expect(live.currentPrefs?.zoom == 1.1)

            // C cycles the song's columns (Auto -> 1 -> 2): a brief indicator, an immediate
            // re-layout, and the choice is remembered for the song.
            live.dispatch(.cycleColumns)
            #expect(live.indicator == "Columns: 1")
            #expect(try body().hasSuffix("columns 1"))
            live.dispatch(.cycleColumns)
            #expect(live.indicator == "Columns: 2")
            #expect(try body().hasSuffix("columns 2"))
            live.dispatch(.next)
            _ = try await env.waitFor { live.positionText == "2 of 3" ? true : nil }
            live.dispatch(.previous)
            _ = try await env.waitFor { live.positionText == "1 of 3" ? true : nil }
            #expect(try body().hasSuffix("columns 2"))
            // The indicator goes away on its own (1.5 s).
            let deadline = ContinuousClock.now + .seconds(5)
            while live.indicator != nil, ContinuousClock.now < deadline {
                try await Task.sleep(for: .milliseconds(50))
            }
            #expect(live.indicator == nil)

            // The 56-line song does not fit at 30pt: it renders at 30 and scrolls.
            live.dispatch(.next)
            live.dispatch(.next)
            _ = try await env.waitFor { live.positionText == "3 of 3" ? true : nil }
            let longBody = try body()
            #expect(longBody.contains("lyric 30 scrolls at minimum"), "\(longBody)")
        }

        /// The current plan's lyric size once it stops changing (the stage window sets its
        /// viewport as it appears).
        private static func settledLyricSize(_ live: LiveSession) async throws -> Double {
            var last: Double?
            for _ in 0 ..< 100 {
                try await Task.sleep(for: .milliseconds(50))
                let size = live.plan?.lyricSize
                if let size, size == last {
                    return size
                }
                last = size
            }
            return try #require(live.plan?.lyricSize)
        }
    }
}
