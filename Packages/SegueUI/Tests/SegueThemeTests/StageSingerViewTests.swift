import AppKit
import Editing
import Foundation
import LiveLayout
@testable import SegueUI
import Shows
import Testing

/// Singer view on a real stage (P9-2 section 6, 16.3): `V` flips the remembered setting and
/// re-lays out on the same pass, the Singer chip and the sounding key line show, `B` and `T`
/// explain themselves and change nothing, the singer zoom is its own, the checklist warns,
/// and nothing ever sounds.
extension StageWindowSuites {
    @MainActor
    @Suite(.serialized, .timeLimit(.minutes(1)))
    struct StageSingerViewTests {
        /// G with a capo on 2 sounds in A; an instrumental intro; chords inside romanized
        /// Hindi words; long enough to have many passes.
        static let song: String = {
            var text = """
            {title: Kitaabon}
            {key: G}
            {capo: 2}
            {tempo: 96}
            {start_of_verse: Intro}
            [G]  [D]  [Em]
            {end_of_verse}

            """
            for verse in 1 ... 6 {
                text += "{start_of_verse: Verse \(verse)}\n"
                text += "Tu[G]jh mein [D]rab dikh[Em]ta hai \(verse)\n"
                text += "[C]Ke[G]sari[D]ya te[Em]ra, line two\n"
                text += "{end_of_verse}\n\n"
            }
            return text
        }()

        /// The next song opens with a chord grid typed as text: never its up-next line in
        /// singer view.
        static let next = "{title: Next}\n{key: D}\n{tempo: 72}\n| [D] . . | [A] . . |\n"
            + "[D]First words [A]here\n"

        static func run() async throws -> MetronomeRun {
            try await MetronomeRun(songs: [song, next], recordsAnalytics: true)
        }

        static func texts(_ plan: LayoutPlan?) -> [PlacedText] {
            let blocks: [LayoutBlock] = (plan?.columns ?? []).flatMap(\.blocks)
            return blocks.flatMap(\.allRows).flatMap { $0.chords + $0.text }
        }

        static func hasChords(_ plan: LayoutPlan?) -> Bool {
            texts(plan).contains { [.chord, .chordSeparator, .approach].contains($0.role) }
        }

        @Test
        func `v hides the chords on the same pass, remembered, silent in a gig`() async throws {
            let run = try await Self.run()
            let live = try await run.start(.gig)
            #expect(Self.hasChords(live.plan))
            #expect(live.planView == .chart)
            let passes = try #require(live.plan?.passes.map(\.name))
            live.jump(toPass: 4)
            let pinned = live.currentPass(at: run.env.clock.now())
            #expect(pinned == 4)

            let settingsUses = run.analytics?.features.count { $0 == "liveSettings" }
            live.dispatch(.toggleSingerView)
            #expect(run.app.liveSettings.settings.singerView)
            #expect(live.indicator == "Singer view")
            #expect(live.planView == .singer)
            #expect(!Self.hasChords(live.plan))
            // The same passes, and the performer stays on the same one.
            #expect(live.plan?.passes.map(\.name) == passes)
            #expect(live.currentPass(at: run.env.clock.now()) == pinned)
            #expect(Self.texts(live.plan).contains { $0.text.contains("Tujh") })
            #expect(Self.texts(live.plan).contains { $0.text == SingerView.instrumentalText })
            #expect((live.plan?.lyricSize ?? 0) >= 28)
            // The header: the sounding key, never the capo shape key.
            #expect(live.singerKeyLine == "Key A, 96")
            // The up-next skips a chord grid typed as text.
            #expect(live.upNextModel.flatMap(StageFooter.firstLine) == "First words here")
            #expect(live.upNextSingerKeyLine == "Key D, 72")
            // Remembered for the next show, and counted once as a stage feature.
            #expect(LiveSettingsStore.load(from: run.env.defaults).singerView)
            #expect(run.analytics?.features.contains("singerView") == true)
            // A stage key, not a use of Settings > Live.
            #expect(run.analytics?.features.count { $0 == "liveSettings" } == settingsUses)

            live.dispatch(.toggleSingerView)
            #expect(live.indicator == "Chords")
            #expect(Self.hasChords(live.plan))
            #expect(live.currentPass(at: run.env.clock.now()) == pinned)
            // Display only: a gig never makes a sound.
            #expect(run.sounds.made == 0)
            #expect(run.outputs.made == 0)
            #expect(run.app.dependencies.audio.isBlocked)
            try await run.end(live)
        }

        @Test
        func `b and t explain themselves in singer view and the bass view comes back`(
        ) async throws {
            let run = try await Self.run()
            run.app.instrumentProfile.update { $0.bassNotes = true }
            run.app.instrumentProfile.update { $0.stageNeck = true }
            let live = try await run.start(.rehearsal)
            #expect(live.showsBassNeck)
            live.dispatch(.toggleSingerView)
            #expect(!live.showsBassNeck)
            #expect(live.currentScale == nil)
            live.dispatch(.toggleBassNotes)
            #expect(live.indicator == "Singer view hides chords (V shows them)")
            #expect(run.app.instrumentProfile.profile.bassNotes)
            live.dispatch(.toggleFillTab)
            #expect(live.indicator == "Singer view hides chords (V shows them)")
            #expect(!run.app.instrumentProfile.profile.fillsAsTab)
            live.dispatch(.toggleSingerView)
            #expect(live.showsBassNeck)
            #expect(live.currentModel?.transform.options.bass?.notes == true)
            try await run.end(live)
        }

        @Test
        func `the singer zoom is its own and the floor holds`() async throws {
            let run = try await Self.run()
            run.app.liveSettings.settings.minLyricSize = 16
            let live = try await run.start(.gig)
            live.dispatch(.toggleSingerView)
            let fitted = try #require(live.plan?.lyricSize)
            #expect(fitted >= 28)
            live.dispatch(.zoomOut)
            #expect(run.app.liveSettings.settings.singerZoom < 1)
            #expect(live.currentPrefs?.zoom == 1)
            #expect((live.plan?.lyricSize ?? 0) >= 28)
            live.dispatch(.zoomIn)
            live.dispatch(.zoomIn)
            #expect(run.app.liveSettings.settings.singerZoom > 1)
            #expect(live.indicator?.hasPrefix("Zoom ") == true)
            #expect((live.plan?.lyricSize ?? 0) > fitted)
            // Back in chart view, the song's own zoom is untouched.
            live.dispatch(.toggleSingerView)
            #expect(live.currentPrefs?.zoom == 1)
            live.dispatch(.resetZoom)
            try await run.end(live)
        }

        @Test
        func `the checklist warns while singer view is on and Show Chords turns it off`(
        ) async throws {
            let run = try await Self.run()
            run.app.liveSettings.settings.singerView = true
            run.app.liveSettings.settings.hiddenChecklistItems = []
            let started = Task { await run.app.startShow(run.setlist, kind: .rehearsal) }
            let checklist = try await run.env.waitFor { run.app.preShow }
            #expect(checklist.visibleRows.contains(.singerView))
            #expect(!checklist.isDone(.singerView))
            checklist.showChords()
            #expect(!run.app.liveSettings.settings.singerView)
            #expect(!checklist.visibleRows.contains(.singerView))
            checklist.answer(true)
            #expect(await started.value)
            let live = try #require(run.app.live)
            live.setViewport(LayoutSize(width: 1390, height: 700))
            #expect(live.planView == .chart)
            try await run.end(live)
        }

        @Test
        func `a show with singer view on says so when it ends`() async throws {
            let run = try await Self.run()
            let live = try await run.start(.rehearsal)
            live.dispatch(.toggleSingerView)
            live.dispatch(.toggleSingerView)
            try await run.end(live)
            let ended = try #require(run.analytics?.log.entries().last { entry in
                (entry["name"] as? String) == "Segue.Show.ended"
            })
            #expect((ended["params"] as? [String: String])?["segue.singer"] == "true")
        }

        @Test
        func `the checklist warns when the Singer Screen's display is not connected`(
        ) async throws {
            let run = try await Self.run()
            run.app.liveSettings.settings.hiddenChecklistItems = []
            let started = Task { await run.app.startShow(run.setlist, kind: .gig) }
            let checklist = try await run.env.waitFor { run.app.preShow }
            checklist.displayCount = { 1 }
            // Never used on this Mac: no line.
            #expect(checklist.singerScreenDisplay == nil)
            run.app.liveSettings.settings.singerScreenDisplay = "LG UltraFine"
            #expect(checklist.singerScreenDisplay == "LG UltraFine")
            checklist.displayCount = { 2 }
            #expect(checklist.singerScreenDisplay == nil)
            checklist.answer(false)
            #expect(await !started.value)
        }

        @Test
        func `live singer view is option-command-v, shared with paste only off stage`() {
            #expect(MenuShortcuts.singerView.displayText == "⌥⌘V")
            #expect(MenuShortcuts.sharedChords.contains { pair in
                pair.0 == MenuShortcuts.newSongFromClipboard && pair.1 == MenuShortcuts.singerView
            })
        }
    }
}
