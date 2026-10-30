import AppKit
import Foundation
import Library
import LiveLayout
@testable import SegueUI
import Shows
import Support
import Testing

/// A long song for the stage map: verses, two written choruses and a `{chorus}` repeat, at
/// 120 BPM, so it scrolls in one column on a narrow stage.
enum MapSong {
    static func source(title: String = "Harbour") -> String {
        func block(_ open: String, _ close: String, _ word: String) -> String {
            let lines = (1 ... 6).map { "[G]\(word) line \($0) of the [C]song" }
            return "{\(open)}\n" + lines.joined(separator: "\n") + "\n{\(close)}\n"
        }
        return "{title: \(title)}\n{tempo: 120}\n\n"
            + block("start_of_verse: Verse 1", "end_of_verse", "First") + "\n"
            + block("start_of_chorus", "end_of_chorus", "Harbour") + "\n"
            + block("start_of_verse: Verse 2", "end_of_verse", "Second") + "\n"
            + "{chorus}\n\n"
            + block("start_of_bridge", "end_of_bridge", "Bridge") + "\n"
            + block("start_of_chorus", "end_of_chorus", "Final")
    }

    /// One column that scrolls.
    static let viewport = LayoutSize(width: 700, height: 300)
}

/// The section map, the current pass and section jump on a real stage (P8-2 sections 7,
/// 9 and 10).
extension StageWindowSuites {
    @MainActor
    @Suite(.serialized)
    struct StageMapTests {
        @Test
        func `the map lists the shown passes and follows the scroll`() async throws {
            let run = try await MetronomeRun(songs: [MapSong.source(), "{title: Two}\n[G]La\n"])
            let live = try await run.start(.gig)
            live.setViewport(MapSong.viewport)
            let plan = try #require(live.plan)
            #expect(plan.columns.count == 1)
            #expect(plan.needsScroll)
            #expect(live.mapPasses.map(\.name.chipText) == [
                "Verse 1", "Chorus 1/3", "Verse 2", "Chorus 2/3", "Bridge", "Chorus 3/3",
            ])
            #expect(StageMapChip.spokenLabel(live.mapPasses[3]) == "Chorus, 2 of 3")
            #expect(StageMapChip.modeLine(.full) == "\u{00A0}")
            #expect(StageMapChip.modeLine(.chordsOnly) == "CHORDS")

            // At the top the first pass is current; at the end, the last.
            let now = run.env.clock.now()
            #expect(live.currentPass(at: now) == 0)
            live.dispatch(.scrollPageDown)
            let paged = try #require(live.currentPass(at: now))
            #expect(paged > 0)
            #expect(paged == StagePasses.current(
                in: plan,
                offset: live.scrollOffset(at: now),
                pinned: nil,
            ))
            for _ in 0 ..< 20 {
                live.dispatch(.scrollPageDown)
            }
            #expect(live.currentPass(at: now) == 5)
            #expect(live.passProgress(at: now) == 1)

            // The viewport loses the map's 58 pt band.
            let size = CGSize(width: 1512, height: 982)
            let viewport = LiveView.viewport(for: size, topInset: 0)
            #expect(viewport.height == 982 - 76 - 58 - 64 - 20 - 46)
            #expect(LiveView.mapHeight == 58)
            try await run.end(live)
        }

        @Test
        func `the map stays empty for a song of one pass and in a break`() async throws {
            let run = try await MetronomeRun(
                songs: ["{title: One}\n[G]Only loose lines\n", MapSong.source()],
                breakBefore: 1,
            )
            let live = try await run.start(.gig)
            live.setViewport(MapSong.viewport)
            #expect(live.mapPasses.isEmpty)
            live.dispatch(.next)
            _ = try await run.env.waitFor { live.state.record.currentBreak != nil ? true : nil }
            #expect(live.mapPasses.isEmpty)
            try await run.end(live)
        }

        @Test
        func `chip widths follow pass length with a floor, or scroll when they cannot fit`() {
            let metrics = StageMapStrip.Style.stage.metrics
            // 408 pt less two 4 pt gaps: 400 shared by weight.
            #expect(StageMapStrip.widths([1, 1, 2], in: 408, metrics: metrics) == [100, 100, 200])
            // A short pass keeps the 52 pt floor; the others share the rest by weight.
            let floored = StageMapStrip.widths([0.1, 1, 1], in: 308, metrics: metrics)
            #expect(floored == [52, 124, 124])
            // Ten chips need 556 pt: 500 scrolls.
            #expect(StageMapStrip.widths(Array(repeating: 1, count: 10), in: 500, metrics: metrics)
                == nil)
            #expect(StageMapStrip.Style.stage.height == 58)
            #expect(StageMapStrip.Style.preview.height == 40)
        }

        @Test
        func `keys 1-9 and a chip click jump, with a confirmation; a missing pass flashes`(
        ) async throws {
            let run = try await MetronomeRun(songs: [MapSong.source(), "{title: Two}\n[G]La\n"])
            let live = try await run.start(.gig)
            live.setViewport(MapSong.viewport)
            let plan = try #require(live.plan)
            let now = run.env.clock.now()

            live.dispatch(.jumpToPass4)
            #expect(live.scrollOffset(at: now) == plan.passes[3].top - 14)
            #expect(live.pinnedPass == 3)
            #expect(live.currentPass(at: now) == 3)
            #expect(live.jumpToast?.text == "Jumped to Chorus · 2 of 3")

            // A click on the map does the same.
            live.jump(toPass: 4)
            #expect(live.currentPass(at: now) == 4)
            #expect(live.jumpToast?.text == "Jumped to Bridge")

            // Near the bottom the seek clamps, but the pass is still current (pinned).
            live.dispatch(.jumpToPass6)
            #expect(live.scrollOffset(at: now) == min(plan.passes[5].top - 14, plan.overflow))
            #expect(live.currentPass(at: now) == 5)

            // A page step lets the scroll decide again.
            live.dispatch(.restartScroll)
            #expect(live.pinnedPass == nil)
            #expect(live.currentPass(at: now) == 0)

            // A digit past the last pass flashes and does not move.
            live.dispatch(.jumpToPass9)
            #expect(live.indicator == "No section 9")
            #expect(live.scrollOffset(at: now) == 0)
            #expect(live.pinnedPass == nil)
            try await run.end(live)
        }

        @Test
        func `a jump in a song that fits only changes the current pass`() async throws {
            let run = try await MetronomeRun(songs: [MapSong.source(), "{title: Two}\n[G]La\n"])
            let live = try await run.start(.gig)
            live.setViewport(LayoutSize(width: 1390, height: 2400))
            let plan = try #require(live.plan)
            #expect(!plan.needsScroll)
            let now = run.env.clock.now()
            #expect(live.currentPass(at: now) == 0)
            live.dispatch(.jumpToPass3)
            #expect(live.scrollOffset(at: now) == 0)
            #expect(live.currentPass(at: now) == 2)
            try await run.end(live)
        }
    }
}
