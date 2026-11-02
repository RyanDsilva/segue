import AppKit
import Foundation
import Library
import LiveLayout
@testable import SegueUI
import Setlists
import Shows
import Support
import SwiftUI
import Testing

/// A medley on a real stage (P9-3 9.1-9.6): one plan through every member, the header chip,
/// the member groups on the map, the footer, the follow model and the keys; rendered for
/// the visual review.
@MainActor
enum MedleyStage {
    static func song(_ title: String, key: String, tempo: Int, words: String) -> String {
        func block(_ open: String, _ close: String, _ tag: String) -> String {
            let lines = (1 ... 4).map { "[\(key)]\(words) \(tag) line \($0) [D]here" }
            return "{\(open)}\n" + lines.joined(separator: "\n") + "\n{\(close)}\n"
        }
        return "{title: \(title)}\n{key: \(key)}\n{tempo: \(tempo)}\n\n"
            + block("start_of_verse: Verse 1", "end_of_verse", "verse") + "\n"
            + block("start_of_chorus", "end_of_chorus", "chorus")
    }

    static let songs = [
        song("Kesariya", key: "G", tempo: 92, words: "Kesariya tera"),
        song("Tum Hi Ho", key: "A", tempo: 120, words: "Har pal saath"),
        song("Channa Mereya", key: "D", tempo: 120, words: "Raaste badalte"),
        "{title: Harbour Lights}\n{key: G}\n{tempo: 96}\n[G]Lights on the [C]water\n",
    ]

    /// Slots 1-3 made into "Love medley": a transition and capo 2 on member 2.
    static func run(songs: [String] = songs, recordsAnalytics: Bool = false) async throws
        -> (MetronomeRun, Setlist)
    {
        let run = try await MetronomeRun(songs: songs, recordsAnalytics: recordsAnalytics)
        let store = try #require(run.app.session).stores.setlists
        let id = run.setlist.id
        let (made, medley) = try await store.makeMedley(
            from: run.setlist.entries.prefix(3).map(\.itemId),
            in: id,
        )
        _ = try await store.renameMedley(medley, to: "Love medley", in: id)
        var member = try #require(made.entries[0].medley?.members[1])
        member.overrides = SetlistOverrides(capo: 2)
        _ = try await store.updateMember(member, in: id)
        let setlist = try await store.setTransition(
            "Hold the D, drums fill, straight into the chorus",
            member: member.itemId,
            in: id,
        )
        await run.app.session?.setlists.reload()
        return (run, setlist)
    }

    static func start(_ run: MetronomeRun, _ setlist: Setlist, kind: ShowKind = .gig)
        async throws -> LiveSession
    {
        #expect(await run.app.startShow(setlist, kind: kind))
        let live = try #require(run.app.live)
        live.setViewport(LayoutSize(width: 700, height: 300))
        return live
    }

    /// Waits until the stage window's own viewport report has landed (no change for
    /// 150 ms, at most 2 s).
    static func settleViewport(_ live: LiveSession) async throws {
        var last = live.viewport
        var stable = 0
        for _ in 0 ..< 40 where stable < 3 {
            try await Task.sleep(for: .milliseconds(50))
            stable = live.viewport == last ? stable + 1 : 0
            last = live.viewport
        }
    }
}

extension StageWindowSuites {
    @MainActor
    @Suite(.serialized)
    struct StageMedleyTests {
        @Test
        func `a medley is one plan with headers, the chip, the map groups and the footer`()
            async throws
        {
            let (run, setlist) = try await MedleyStage.run()
            let live = try await MedleyStage.start(run, setlist)
            let plan = try #require(live.plan)
            #expect(live.state.medley.count == 3)
            #expect(Set(plan.passes.map(\.segment)) == [0, 1, 2])
            #expect(live.medleyChipText == "Medley 1 of 3")
            #expect(live.medleyChipLabel == "Love medley, song 1 of 3")
            #expect(live.mapMembers == ["Kesariya", "Tum Hi Ho", "Channa Mereya"])
            let headers = plan.columns.flatMap(\.blocks).compactMap(\.memberHeader)
            #expect(headers.map(\.header.title) == ["Kesariya", "Tum Hi Ho", "Channa Mereya"])
            #expect(headers[1].header.transition?.hasPrefix("Hold the D") == true)
            #expect(headers[1].header.changes.contains { $0.kind == .capo })
            #expect(live.nextInMedley?.slot.item.title == "Tum Hi Ho")
            try await run.end(live)
        }

        @Test
        func `next moves member by member without a new plan, then leaves the medley`()
            async throws
        {
            let (run, setlist) = try await MedleyStage.run()
            let live = try await MedleyStage.start(run, setlist)
            let now = run.env.clock.now()
            let slot = live.state.current?.item.medley?.slot
            live.dispatch(.next)
            _ = try await run.env.waitFor { live.medleyChipText == "Medley 2 of 3" ? true : nil }
            // The scroll landed at member 2's header; the medley's layout (and its scroller)
            // stayed.
            let plan = try #require(live.plan)
            let header = try #require(MedleyFollow.seekOffset(to: 1, in: plan))
            #expect(abs(live.scrollOffset(at: now) - header) < 0.5)
            #expect(live.laidOutMedley == slot)
            #expect(live.laidOutItem == live.state.current?.item.itemId)
            #expect(live.state.record.items[0].state == .played)
            // x skips member 2 and lands on member 3.
            live.dispatch(.skipCurrent)
            _ = try await run.env.waitFor { live.medleyChipText == "Medley 3 of 3" ? true : nil }
            #expect(live.state.record.items[1].state == .skipped)
            #expect(live.nextInMedley == nil)
            // ← goes back to member 2's header first when past it.
            live.dispatch(.next)
            _ = try await run.env.waitFor { live.state.current?.item.medley == nil ? true : nil }
            #expect(live.state.current?.item.title == "Harbour Lights")
            #expect(live.medleySegments.isEmpty)
            try await run.end(live)
        }

        @Test
        func `the reading line commits a member after a second; page down leaves at the end`()
            async throws
        {
            let (run, setlist) = try await MedleyStage.run()
            let live = try await MedleyStage.start(run, setlist)
            let plan = try #require(live.plan)
            #expect(StagePasses.followsScroll(plan))
            let target = try #require(MedleyFollow.seekOffset(to: 1, in: plan))
            let now = run.env.clock.now()
            live.scroller?.seek(to: target + 30, at: now)
            live.followMedley()
            #expect(live.medleyChipText == "Medley 1 of 3")
            run.env.clock.advance(by: 1.2)
            live.followMedley()
            _ = try await run.env.waitFor { live.medleyChipText == "Medley 2 of 3" ? true : nil }
            #expect(live.state.record.items[0].state == .played)
            // Page Down to the bottom of the medley, then once more: the next slot.
            for _ in 0 ..< 40 where live.state.current?.item.medley != nil {
                live.dispatch(.pageForward)
                _ = try await run.env.waitFor { live.songChangesInFlight == 0 ? true : nil }
            }
            #expect(live.state.current?.item.title == "Harbour Lights")
            #expect(live.state.record.items.prefix(3).allSatisfy { $0.state == .played })
            try await run.end(live)
        }

        @Test
        func `insert next during a medley flashes that it plays after the medley`() async throws {
            let (run, setlist) = try await MedleyStage.run()
            let live = try await MedleyStage.start(run, setlist)
            let extra = try await run.app.session?.library
                .createSong(source: "{title: Extra}\n[G]La\n")
            try live.perform(.insertNext(#require(extra).id))
            #expect(live.indicator == "Plays after the medley")
            _ = try await run.env.waitFor {
                live.state.record.items.count == 5 ? true : nil
            }
            #expect(live.state.record.items.map(\.title)[3] == "Extra")
            try await run.end(live)
        }

        @Test
        func `the stage records the medley feature once per run`() async throws {
            let (run, setlist) = try await MedleyStage.run(recordsAnalytics: true)
            let live = try await MedleyStage.start(run, setlist)
            live.dispatch(.next)
            _ = try await run.env.waitFor { live.medleyChipText == "Medley 2 of 3" ? true : nil }
            live.setViewport(LayoutSize(width: 800, height: 400))
            #expect(run.analytics?.features.filter { $0 == "medley" }.count == 1)
            try await run.end(live)
        }

        @Test
        func `each member scrolls at its own speed`() async throws {
            let (run, setlist) = try await MedleyStage.run()
            let live = try await MedleyStage.start(run, setlist)
            let plan = try #require(live.plan)
            let segments = try #require(live.scroller?.segments)
            #expect(segments.count == 3)
            // Tum Hi Ho's stretch, from its header at the reading line to Channa Mereya's,
            // scrolls over its own time (120 BPM), not the medley's average.
            let starts = try (1 ... 2).map { segment in
                let top = try #require(MedleyFollow.headerTop(of: segment, in: plan))
                return try #require(StagePasses.offset(readingAt: top, in: plan))
            }
            #expect(segments.map(\.fromOffset).dropFirst()
                .elementsEqual(starts) { abs($0 - $1) < 0.5 })
            let song = try #require(live.state.medley[1].song)
            let time = try #require(SlotTimes.slot(song, arrangement: nil).seconds)
            live.dispatch(.toggleAutoScroll)
            let into = try #require(live.scroller?.instant(reaching: starts[0]))
            let out = try #require(live.scroller?.instant(reaching: starts[1]))
            #expect(abs(out.timeIntervalSince(into) - time) < 0.01)
            #expect(!live.needsTempoHint)
            live.dispatch(.toggleAutoScroll)
            // ] scales every segment, and it is saved on the opener even from member 2.
            live.dispatch(.next)
            _ = try await run.env.waitFor { live.medleyChipText == "Medley 2 of 3" ? true : nil }
            live.dispatch(.scrollFaster)
            let nudged = try #require(live.scroller?.segments)
            for (before, after) in zip(segments, nudged) {
                #expect(abs(after.speed - before.speed * ScrollSpeedModel.nudgeStep) < 1e-6)
            }
            try await run.end(live)
        }

        @Test
        func `the metronome switches at the member boundary, not on the commit`() async throws {
            let (run, setlist) = try await MedleyStage.run()
            let live = try await MedleyStage.start(run, setlist)
            // The stage window reports its own size a moment later and relays the plan out:
            // let that land, then set the test's single-column size again, so the seek below
            // keeps the reading line in member 2.
            try await MedleyStage.settleViewport(live)
            live.setViewport(LayoutSize(width: 700, height: 300))
            let plan = try #require(live.plan)
            #expect(live.metronome.track?.bpm == 92)
            let target = try #require(MedleyFollow.seekOffset(to: 1, in: plan))
            let now = run.env.clock.now()
            live.scroller?.seek(to: target + 30, at: now)
            live.noteCurrentPass(live.currentPass(at: now))
            // The reading line is in Tum Hi Ho: its 120 from beat 1 of the boundary.
            #expect(live.medleyChipText == "Medley 1 of 3")
            let switched = try #require(live.metronome.track)
            #expect(switched.bpm == 120)
            #expect(switched.start == now)
            // The commit a second later keeps the grid running.
            live.followMedley()
            run.env.clock.advance(by: 1.2)
            live.followMedley()
            _ = try await run.env.waitFor { live.medleyChipText == "Medley 2 of 3" ? true : nil }
            #expect(live.metronome.track == switched)
            try await run.end(live)
        }

        /// Moves the clock in 0.1 s steps, pumping the player, the follow scroll and the
        /// member follow.
        static func play(_ run: MetronomeRun, _ live: LiveSession, for seconds: Double) {
            for _ in 0 ..< Int((seconds * 10).rounded()) {
                run.env.clock.advance(by: 0.1)
                run.app.sound.player?.pump()
                live.followPlayAlong()
                live.followMedley()
            }
        }

        @Test
        func `p plays the medley as one timeline and the audio commits each member`()
            async throws
        {
            let (run, setlist) = try await MedleyStage.run()
            let live = try await MedleyStage.start(run, setlist, kind: .rehearsal)
            live.dispatch(.togglePlayAlong)
            #expect(live.isPlayingAlong)
            let playing = try #require(live.playAlong?.timeline)
            // Two passes per member, every member: 16 chords each, one count-in only.
            #expect(playing.passes == 0 ..< 6)
            #expect(playing.chords.count == 48)
            let second = playing.timeline.chords[16]
            #expect(playing.timeline.chords[15].tempo == 92)
            #expect(second.tempo == 120)
            #expect(second.pass == 2)
            // No gap: member 2 starts on member 1's last bar line.
            #expect(second.onset == playing.timeline.chords[15].onset
                + playing.timeline.chords[15].length)
            #expect(playing.timeline.barBeat(at: second.onset).beat == 1)
            // Member 1 (16 bars at 92) plus the count-in bar, and a little into member 2.
            Self.play(run, live, for: 16 * 4 * 60 / 92 + 4 * 60 / 92 + 1.5)
            _ = try await run.env.waitFor { live.medleyChipText == "Medley 2 of 3" ? true : nil }
            #expect(live.isPlayingAlong)
            #expect(live.state.record.items[0].state == .played)
            try await run.end(live)
        }

        @Test
        func `play-along stops at a member with no tempo`() async throws {
            var songs = MedleyStage.songs
            songs[2] = songs[2].replacingOccurrences(of: "{tempo: 120}\n", with: "")
            let (run, setlist) = try await MedleyStage.run(songs: songs)
            let live = try await MedleyStage.start(run, setlist, kind: .rehearsal)
            live.dispatch(.togglePlayAlong)
            #expect(live.playAlong?.timeline.passes == 0 ..< 4)
            Self.play(run, live, for: 16 * 4 * 60 / 92 + 16 * 4 * 60 / 120 + 4 * 60 / 92 + 1)
            #expect(!live.isPlayingAlong)
            #expect(live.indicator == "No tempo for Channa Mereya: play-along stops here")
            try await run.end(live)
        }

        @Test
        func `play-along refuses a member with no tempo (R191)`() async throws {
            var songs = MedleyStage.songs
            songs[0] = songs[0].replacingOccurrences(of: "{tempo: 92}\n", with: "")
            let (run, setlist) = try await MedleyStage.run(songs: songs)
            let live = try await MedleyStage.start(run, setlist, kind: .rehearsal)
            live.dispatch(.togglePlayAlong)
            #expect(!live.isPlayingAlong)
            #expect(live.indicator == "No tempo for Kesariya")
            try await run.end(live)
        }

        @Test
        func `a gig medley stays silent`() async throws {
            let (run, setlist) = try await MedleyStage.run()
            let live = try await MedleyStage.start(run, setlist)
            #expect(live.playAlong == nil)
            live.dispatch(.togglePlayAlong)
            #expect(!live.isPlayingAlong)
            #expect(live.indicator == "Play-along works in rehearsals")
            try await run.end(live)
        }

        /// The stage inside the medley at member 2, 1440 x 900 dark, for the review.
        @Test
        func `renders the medley stage`() async throws {
            let (run, setlist) = try await MedleyStage.run()
            let live = try await MedleyStage.start(run, setlist)
            live.dispatch(.next)
            _ = try await run.env.waitFor { live.medleyChipText == "Medley 2 of 3" ? true : nil }
            let screen = CGSize(width: 1440, height: 900)
            live.setViewport(LiveView.viewport(for: screen, topInset: 0))
            let view = LiveView(session: live)
                .frame(width: screen.width, height: screen.height)
                .environment(\.colorScheme, .dark)
            let renderer = ImageRenderer(content: view)
            renderer.scale = 2
            let image = try #require(renderer.cgImage)
            try DiagramSnapshotTests.writePNG(
                image,
                to: DiagramSnapshotTests.screenshotDirectory.deletingLastPathComponent()
                    .appending(path: "p9-3/stage-dark.png"),
            )
            try await run.end(live)
        }
    }
}
