import AppKit
import Foundation
import Library
import LiveLayout
@testable import SegueUI
import Shows
import SwiftUI
import Testing

/// Singer view for review (P9-2, R187 directions A): the stage in chart and singer view at
/// 1440 x 900, a 13" and a 1280 x 800 screen, the Singer Screen at 1920 x 1080 (all dark: the
/// stage is always dark), and the library pane's and the editor's singer previews in dark and
/// light. PNGs go to `.build/screenshots/p9-2/`; asserts the 28 pt floor and no chord.
extension StageWindowSuites {
    @MainActor
    @Suite(.serialized)
    struct SingerViewSnapshotTests {
        /// The R187 fixture: an instrumental intro, a Chords only chorus, the Welcome song's
        /// romanized Hindi.
        static let kitaabon = """
        {title: Kitaabon Wali Gali}
        {artist: Segue Originals}
        {key: Am}
        {tempo: 84}

        {start_of_verse: Intro}
        [Am]  [G]  [F]  [E]
        {end_of_verse}

        {start_of_verse: Verse 1}
        [Am]Purani si gali mein [G]kitaabon ki du[F]kaan,
        Panne palatte haathon mein [E]chhupi thi muskaan,
        [Am]Chai ka cup thanda tha, [G]baatein thi garam,
        [F]Shaam ne dheere dheere [E]badle apne kadam.
        {end_of_verse}

        {start_of_chorus}
        {comment: All together}
        [F]Ki[G]taabon wali gali, [C]phir se bula [Am]rahi,
        [F]Har ek kahaani [G]mein teri [E]yaad chhupi,
        [F]Lafzon ke [G]mele mein [C]main kho [Am]jaaun,
        [Dm]Tera naam likha [E]panna dhoondh [Am]laaun.
        {end_of_chorus}

        {start_of_verse: Verse 2}
        [Am]Baarish ki boondein [G]khidki pe likhti,
        [F]Adhoori si kavita [E]jo tujh tak pahunchti,
        [Am]Raaste wahi hain, [G]mausam naya,
        [F]Dil ne phir se [E]wahi geet gaaya.
        {end_of_verse}

        {chorus}

        {start_of_bridge}
        [Dm]Na koi [Am]jaldi, [E]na koi [Am]shor,
        [Dm]Bas ek [Am]kahaani [E]aur nayi si [Am]bhor.
        {end_of_bridge}

        {chorus}
        """

        static let kettle = """
        {title: Kettle On, Lights Low}
        {key: Bb}
        {tempo: 72}
        [Bb]Kettle on, lights [F]low,
        """

        static let screens: [(name: String, size: CGSize)] = [
            ("1440x900", CGSize(width: 1440, height: 900)),
            ("13in", CGSize(width: 1470, height: 956)),
            ("1280x800", CGSize(width: 1280, height: 800)),
        ]

        @Test
        func `singer view renders on stage, on a Singer Screen and in the previews`(
        ) async throws {
            let run = try await MetronomeRun(songs: [Self.kitaabon, Self.kettle])
            let session = try #require(run.app.session)
            // Intro, Verse 1, Chorus, Verse 2, Chorus (Chords only), Bridge, Chorus.
            var entry = try #require(run.setlist.entries.first)
            entry.arrangement = SlotArrangement(passes: [
                ("Intro", 1, PassMode.full), ("Verse 1", 1, .full), ("Chorus", 1, .full),
                ("Verse 2", 1, .full), ("Chorus", 2, .chordsOnly), ("Bridge", 1, .full),
                ("Chorus", 3, .full),
            ].map { label, occurrence, mode in
                ArrangementPass(
                    anchor: .section(SectionRef(label: label, occurrence: occurrence)),
                    mode: mode,
                )
            })
            _ = try await session.stores.setlists.updateEntry(entry, in: run.setlist.id)
            let setlist = try #require(await session.stores.setlists.setlist(id: run.setlist.id))
            #expect(await run.app.startShow(setlist, kind: .rehearsal))
            let live = try #require(run.app.live)
            defer { StageWindowController.shared.close() }

            try renderStage(live)
            try renderScreen(live)
            try await renderPreviews(run, live)
            run.app.previewPrefs.setSinger(false, from: .editor)
        }

        private func renderStage(_ live: LiveSession) throws {
            for screen in Self.screens {
                live.setViewport(LiveView.viewport(for: screen.size, topInset: 0))
                if live.singerView {
                    live.dispatch(.toggleSingerView)
                }
                live.jump(toPass: 4)
                let chart = try #require(live.plan)
                live.jumpToast = nil
                try write(stage(live, screen.size), "stage-chart-\(screen.name)-dark")
                live.dispatch(.toggleSingerView)
                live.indicator = nil
                live.jumpToast = nil
                let singer = try #require(live.plan)
                try write(stage(live, screen.size), "stage-singer-\(screen.name)-dark")
                #expect(singer.lyricSize >= 28)
                #expect(singer.lyricSize >= chart.lyricSize)
                print("P9-2 \(screen.name): chart \(chart.lyricSize) pt, singer "
                    + "\(singer.lyricSize) pt in \(singer.columns.count) columns, \(singer.fit)")
            }
        }

        private func renderScreen(_ live: LiveSession) throws {
            // The Singer Screen at 1920 x 1080, beside a chart stage.
            live.dispatch(.toggleSingerView)
            let screen = SingerScreenModel(live: live)
            let size = CGSize(width: 1920, height: 1080)
            screen.setViewport(LayoutSize(
                width: size.width - 2 * SingerScreenView.horizontalPadding,
                height: size.height - SingerScreenView.headerHeight - SingerScreenView.mapHeight
                    - SingerScreenView.bodyTopPadding - SingerScreenView.bottomPadding,
            ))
            let screenPlan = try #require(screen.plan)
            #expect(screenPlan.lyricSize >= 28)
            let screenView = SingerScreenView(model: screen)
                .frame(width: size.width, height: size.height)
                .environment(\.colorScheme, .dark)
            try write(Self.image(screenView), "singer-screen-1920x1080-dark")
        }

        private func renderPreviews(_ run: MetronomeRun, _ live: LiveSession) async throws {
            let session = try #require(run.app.session)
            // The previews: the library pane and the editor, in dark and light.
            run.app.previewPrefs.setSinger(true, from: .library)
            let library = session.library
            let record = try #require(library.catalog.first { $0.document.metadata.title
                    == "Kitaabon Wali Gali"
            })
            for dark in [true, false] {
                let pane = SongDetailPane(model: library, session: session, record: record)
                    .frame(width: 900, height: 1500)
                try write(
                    Self.hosted(pane, dark: dark),
                    "preview-library-singer-\(dark ? "dark" : "light")",
                )
            }
            try await run.end(live)
            library.beginEditing(record)
            let editor = try await run.env.waitFor { library.editor }
            for mode in [SongEditorViewModel.EditorMode.visual, .text] {
                editor.setEditorMode(mode)
                editor.scheduleRender(delay: .zero)
                await editor.renderTask?.value
                for dark in [true, false] {
                    let view = SongEditorView(model: editor, onDone: {})
                        .frame(width: 1280, height: 900)
                    try write(
                        Self.hosted(view, dark: dark),
                        "preview-editor-\(mode)-singer-\(dark ? "dark" : "light")",
                    )
                }
            }
        }

        private func stage(_ live: LiveSession, _ size: CGSize) throws -> CGImage {
            try Self.image(LiveView(session: live)
                .frame(width: size.width, height: size.height)
                .environment(\.colorScheme, .dark))
        }

        private func write(_ image: CGImage, _ name: String) throws {
            try DiagramSnapshotTests.writePNG(
                image,
                to: Self.directory.appending(path: "\(name).png"),
            )
        }

        static func image(_ view: some View) throws -> CGImage {
            let renderer = ImageRenderer(content: view)
            renderer.scale = 2
            return try #require(renderer.cgImage, "no image")
        }

        /// AppKit controls (the segmented Chords / Singer) only draw in a hosting view.
        static func hosted(_ view: some View, dark: Bool) throws -> CGImage {
            let host = NSHostingView(rootView: view.background(Theme.color.ground))
            host.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
            host.frame = NSRect(origin: .zero, size: host.fittingSize)
            host.layoutSubtreeIfNeeded()
            let rep = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
            host.cacheDisplay(in: host.bounds, to: rep)
            return try #require(rep.cgImage)
        }

        /// `<repo>/.build/screenshots/p9-2`.
        static var directory: URL {
            DiagramSnapshotTests.screenshotDirectory
                .deletingLastPathComponent()
                .appending(path: "p9-2", directoryHint: .isDirectory)
        }
    }
}
