import AppKit
import Foundation
import Library
import LiveLayout
import Playback
@testable import SegueUI
import Shows
import Support
import Testing

/// Rehearsal play-along on a real stage (P8-6 10.4, 15.2) with the manual clock as scroll and
/// sound clock and a recording output: `P` plays the played passes from the current pass, the
/// audio drives the scroll, `L` loops the pass with a count-in at every wrap, a jump restarts
/// at that pass, song changes and End stop it, `K` stays silent meanwhile, and a gig only
/// flashes.
extension StageWindowSuites {
    @MainActor
    @Suite(.serialized)
    struct StagePlayAlongTests {
        /// MapSong is at 120 in 4/4: a bar is 2 s, each pass 12 chords of one bar (24 s).
        static func start(_ kind: ShowKind = .rehearsal) async throws
            -> (MetronomeRun, LiveSession)
        {
            let run = try await MetronomeRun(
                songs: [MapSong.source(), "{title: Two}\n{tempo: 100}\n[A]La\n"],
                recordsAnalytics: true,
            )
            let live = try await run.start(kind)
            live.setViewport(MapSong.viewport)
            return (run, live)
        }

        /// Moves the clock in 0.1 s steps, pumping the player and the follow scroll.
        static func run(_ run: MetronomeRun, _ live: LiveSession, for seconds: Double) {
            for _ in 0 ..< Int((seconds * 10).rounded()) {
                run.env.clock.advance(by: 0.1)
                run.app.sound.player?.pump()
                live.followPlayAlong()
            }
        }

        static func bass(_ run: MetronomeRun, from start: Date) -> [String] {
            (run.sounds.last?.played ?? []).filter { $0.event.voice == .bass }.map { played in
                let at = ((played.at - start.timeIntervalSinceReferenceDate) * 1000).rounded()
                    / 1000
                return "\(played.event.note)@\(at)"
            }
        }

        @Test
        func `p plays the passes from the current one and the audio drives the scroll`()
            async throws
        {
            let (run, live) = try await Self.start()
            let plan = try #require(live.plan)
            live.dispatch(.jumpToPass2)
            live.dispatch(.toggleAutoScroll)
            #expect(live.isAutoScrolling)
            let start = run.env.clock.now()
            live.dispatch(.togglePlayAlong)
            #expect(live.isPlayingAlong)
            #expect(live.playAlong?.timeline.passes == 1 ..< 6)
            #expect(run.analytics?.features.contains("playAlong") == true)
            // Auto-scroll paused: the audio is the clock.
            #expect(live.scroller?.phase == .paused)
            // The count-in bar shows on the pips.
            Self.run(run, live, for: 1)
            #expect(live.metronome.countInEnd != nil)
            #expect(live.scrollOffset(at: run.env.clock.now())
                == StagePasses.jumpOffset(to: 1, in: plan))
            // From 2 s the chorus plays: G on beats 1 and 3, then C.
            Self.run(run, live, for: 4.4)
            #expect(Self.bass(run, from: start).prefix(3) == ["31@2.0", "31@3.0", "36@4.0"])
            // At 6.5 s the third chord (line 2's G) sounds: its line sits at the reading line.
            let line = try #require(live.playAlong?.timeline.timeline.chords[2].line)
            let top = try #require(StagePasses.lineTop(line, pass: 1, in: plan))
            let target = try #require(StagePasses.offset(readingAt: top, in: plan))
            Self.run(run, live, for: 1.5)
            #expect(abs(live.scrollOffset(at: run.env.clock.now()) - target) < 0.5)
            #expect(live.currentPass(at: run.env.clock.now()) == 1)

            // P again stops it, and auto-scroll runs again.
            live.dispatch(.togglePlayAlong)
            #expect(!live.isPlayingAlong)
            #expect(live.scroller?.phase == .running)
            try await run.end(live)
        }

        @Test
        func `with L the pass loops and every wrap counts in from the audio`() async throws {
            let (run, live) = try await Self.start()
            let plan = try #require(live.plan)
            live.dispatch(.jumpToPass2)
            live.dispatch(.toggleLoop)
            live.dispatch(.togglePlayAlong)
            #expect(live.playAlong?.loops == true)
            #expect(live.playAlong?.timeline.passes == 1 ..< 2)
            #expect(live.loopWrapInstant == nil)
            // Count-in, the pass (24 s), then the next wrap's count-in.
            Self.run(run, live, for: 2 + 24 + 1)
            #expect(live.playAlong?.pass == 2)
            let wrapCountIn = try #require(live.metronome.countInEnd)
            #expect(wrapCountIn > run.env.clock.now())
            #expect(live.scrollOffset(at: run.env.clock.now())
                == StagePasses.jumpOffset(to: 1, in: plan))
            // L off stops it.
            live.dispatch(.toggleLoop)
            #expect(!live.isPlayingAlong)
            try await run.end(live)
        }

        @Test
        func `a jump restarts at that pass, and a song change and End stop it`() async throws {
            let (run, live) = try await Self.start()
            live.dispatch(.togglePlayAlong)
            Self.run(run, live, for: 3)
            live.dispatch(.jumpToPass4)
            #expect(live.isPlayingAlong)
            #expect(live.playAlong?.timeline.passes.lowerBound == 3)
            live.dispatch(.next)
            _ = try await run.env.waitFor { live.state.current?.position == 1 ? true : nil }
            #expect(!live.isPlayingAlong)
            live.dispatch(.togglePlayAlong)
            #expect(live.isPlayingAlong)
            live.dispatch(.endShow)
            live.confirmEnd()
            #expect(!live.isPlayingAlong)
            _ = try await run.env.waitFor { run.app.live == nil ? true : nil }
        }

        @Test
        func `the K click is muted while play-along clicks`() async throws {
            let (run, live) = try await Self.start()
            live.dispatch(.toggleMetronomeClick)
            #expect(live.metronome.clicks)
            live.dispatch(.togglePlayAlong)
            #expect(live.metronome.muted)
            live.dispatch(.togglePlayAlong)
            #expect(!live.metronome.muted)
            // Without the Click voice the K click carries on.
            run.app.sound.settings.update { $0.playAlongClick = false }
            live.dispatch(.togglePlayAlong)
            #expect(!live.metronome.muted)
            try await run.end(live)
        }

        @Test
        func `fills from the hook play in a rehearsal`() async throws {
            let (run, live) = try await Self.start()
            run.app.sound.settings.update {
                $0.playAlongChords = false
                $0.playAlongClick = false
            }
            live.playAlong?.fillProvider = { _ in
                [PlayAlongFill(region: 960 ..< 1920, notes: [
                    PlayAlongFill.Note(tick: 960, length: 960, midi: 40),
                ])]
            }
            let start = run.env.clock.now()
            live.dispatch(.togglePlayAlong)
            Self.run(run, live, for: 4.5)
            #expect(Self.bass(run, from: start).prefix(3) == ["31@2.0", "40@3.0", "36@4.0"])
            try await run.end(live)
        }

        @Test
        func `p in a gig only flashes, and the keys list P in a rehearsal`() async throws {
            let (run, live) = try await Self.start(.gig)
            #expect(live.playAlong == nil)
            live.dispatch(.togglePlayAlong)
            #expect(live.indicator == "Play-along works in rehearsals")
            #expect(run.sounds.made == 0)
            let table = live.context.bindings
            #expect(!KeyHelp.statusHints(table, kind: .gig).contains("P play along"))
            #expect(KeyHelp.statusHints(table, kind: .rehearsal).contains("P play along"))
            let sections = try #require(KeyHelp.groups(table).first { $0.title == "Sections" })
            #expect(sections.rows.contains {
                $0.title == "Play Along (Rehearsal)" && $0.keys == ["P"]
            })
            try await run.end(live)
        }
    }
}
