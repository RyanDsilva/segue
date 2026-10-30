import AppKit
import Foundation
import Library
import LiveLayout
@testable import SegueUI
import Shows
import Support
import Testing

/// The rehearsal loop (R148, P8-2 section 11) on a real stage with the manual clock as the
/// scroll clock: the wrap, its one-bar count-in, Page Down while looping, and what ends it.
extension StageWindowSuites {
    @MainActor
    @Suite(.serialized)
    struct StageLoopTests {
        /// R163: the bracket sits in the gutter gap, clear of the gutter and of the tint.
        @Test
        func `the loop bracket sits clear of the gutter and the section tint`() {
            let style = LayoutStyle.stage
            #expect(style.gutterGap == 18)
            let gutter = 96.0
            let x = StagePassOverlay.loopBracketX(gutterWidth: gutter, style: style)
            let tintStart = gutter + style.gutterGap - StagePlanView.tintLead
            #expect(x - gutter >= 3)
            #expect(tintStart - (x + StagePassOverlay.loopBracketWidth) >= 3)
        }

        @Test
        func `the loop key in a gig flashes and changes nothing`() async throws {
            let run = try await MetronomeRun(songs: [MapSong.source(), "{title: Two}\n[G]La\n"])
            let live = try await run.start(.gig)
            live.setViewport(MapSong.viewport)
            live.dispatch(.toggleLoop)
            #expect(live.indicator == "Loop works in rehearsals")
            #expect(live.loopPass == nil)
            #expect(KeyHelp.statusHints(live.context.bindings, kind: live.kind).contains("L loop")
                == false)
            try await run.end(live)
        }

        @Test
        func `the loop wraps with auto-scroll after a one-bar count-in`() async throws {
            let run = try await MetronomeRun(songs: [MapSong.source(), "{title: Two}\n[G]La\n"])
            let live = try await run.start(.rehearsal)
            live.setViewport(MapSong.viewport)
            let plan = try #require(live.plan)
            let clock = run.env.clock
            live.dispatch(.jumpToPass2)
            live.dispatch(.toggleLoop)
            #expect(live.loopPass == 1)
            #expect(live.loopedPass?.name.chipText == "Chorus 1/3")
            #expect(live.loopKey == "L")

            // Auto-scroll on: the wrap is due when the reading line reaches the pass's bottom.
            live.dispatch(.toggleAutoScroll)
            let instant = try #require(live.loopWrapInstant)
            let wrapOffset = StagePasses.wrapOffset(of: 1, in: plan)
            #expect(try abs(#require(live.scroller).offset(at: instant) - wrapOffset) < 0.01)
            clock.advance(by: instant.timeIntervalSince(clock.now()) - 0.5)
            live.wrapLoopIfDue()
            #expect(live.scrollOffset(at: clock.now()) > plan.passes[1].top)

            // The wrap: back above the pass, pinned, the grid restarted on beat 1 at the wrap,
            // the pips shown for the bar with the pulse off, and the scroll held for it.
            clock.advance(by: 0.5)
            live.wrapLoopIfDue()
            let wrapped = clock.now()
            let top = plan.passes[1].top - 14
            #expect(live.scrollOffset(at: wrapped) == top)
            #expect(live.currentPass(at: wrapped) == 1)
            let metronome = live.metronome
            #expect(!metronome.isOn)
            #expect(metronome.track?.start == wrapped)
            let bar = try #require(metronome.track).barDuration
            #expect(bar == 2)
            #expect(metronome.countInEnd == wrapped.addingTimeInterval(bar))
            #expect(metronome.showsPulse(at: wrapped.addingTimeInterval(1)))
            #expect(!metronome.showsPulse(at: wrapped.addingTimeInterval(bar + 0.1)))
            // The click sounds only when K is on: no audio path was made.
            #expect(run.outputs.made == 0)
            #expect(live.scrollOffset(at: wrapped.addingTimeInterval(bar - 0.1)) == top)
            #expect(live.scrollOffset(at: wrapped.addingTimeInterval(bar + 1)) > top)
            // The next wrap is scheduled again.
            #expect(try #require(live.loopWrapInstant) > wrapped.addingTimeInterval(bar))

            // L stops it.
            live.dispatch(.toggleLoop)
            #expect(live.loopPass == nil)
            #expect(live.loopWrapInstant == nil)
            try await run.end(live)
        }

        @Test
        func `a page down wraps a loop instead of leaving the pass`() async throws {
            let run = try await MetronomeRun(songs: [MapSong.source(), "{title: Two}\n[G]La\n"])
            let live = try await run.start(.rehearsal)
            live.setViewport(MapSong.viewport)
            let plan = try #require(live.plan)
            let now = run.env.clock.now()
            live.dispatch(.toggleLoop)
            #expect(live.loopPass == 0)
            // Each page that would take the reading line past Verse 1's bottom wraps.
            for _ in 0 ..< 4 {
                live.dispatch(.pageForward)
                let line = StagePasses.readLine(offset: live.scrollOffset(at: now), plan: plan)
                #expect(line <= plan.passes[0].bottom + 0.5)
            }
            #expect(live.currentPass(at: now) == 0)
            #expect(live.state.current?.item.title == "Harbour")
            // A song without a tempo would hold 2 s; this one holds a bar (2 s at 120 in 4/4).
            #expect(StageMetronome.tempolessHold == 2)

            // A jump elsewhere ends the loop.
            live.dispatch(.jumpToPass3)
            #expect(live.loopPass == nil)

            // Looping again, then a song change ends it.
            live.dispatch(.toggleLoop)
            #expect(live.loopPass == 2)
            live.dispatch(.next)
            _ = try await run.env.waitFor { live.positionText == "2 of 2" ? true : nil }
            #expect(live.loopPass == nil)
            #expect(live.pinnedPass == nil)
            try await run.end(live)
        }

        @Test
        func `in a song that fits every Page Down wraps`() async throws {
            let run = try await MetronomeRun(songs: [MapSong.source(), "{title: Two}\n[G]La\n"])
            let live = try await run.start(.rehearsal)
            live.setViewport(LayoutSize(width: 1390, height: 2400))
            #expect(live.plan?.needsScroll == false)
            live.dispatch(.jumpToPass5)
            live.dispatch(.toggleLoop)
            #expect(live.loopPass == 4)
            live.dispatch(.pageForward)
            live.dispatch(.pageForward)
            #expect(live.state.current?.item.title == "Harbour")
            #expect(live.currentPass(at: run.env.clock.now()) == 4)
            #expect(live.metronome.countInEnd != nil)
            try await run.end(live)
        }
    }
}
