import AppKit
import Foundation
import LiveLayout
@testable import SegueUI
import Shows
import SwiftUI
import Testing

/// The stage in the stage theme at 13" and 16" MacBook sizes (and a 27" external display),
/// with short, long and very long songs. Renders the real `LiveView` from a real show and
/// writes PNGs to `.build/screenshots/live/` for review; asserts the min-font rule.
extension StageWindowSuites {
    @MainActor
    @Suite(.serialized)
    struct LiveStageSnapshotTests {
        /// Logical screen sizes in points.
        static let screens: [(name: String, size: CGSize)] = [
            ("13in", CGSize(width: 1470, height: 956)),
            ("16in", CGSize(width: 1728, height: 1117)),
            ("27in", CGSize(width: 2560, height: 1440)),
        ]

        @Test
        func `the stage renders short, long and very long songs at each size`() async throws {
            _ = NSApplication.shared
            let env = try TestEnvironment()
            let app = try await env.openApp()
            let fixture = try await LiveFixture(app: app, titles: ["Short"], lines: 8)
            let session = try #require(app.session)
            for (title, lines) in [("Long", 40), ("Very Long", 96)] {
                let song = try await session.library.createSong(
                    source: LiveFixture.source(title: title, lines: lines),
                )
                await session.setlists.add(song.id, to: fixture.setlist.id)
            }
            let setlist = try #require(session.setlists.selected)
            app.liveSettings.settings.hiddenChecklistItems = Set(ChecklistItem.allCases)
            #expect(await app.startShow(setlist, kind: .gig))
            let live = try #require(app.live)
            defer { StageWindowController.shared.close() }

            for (index, name) in ["short", "long", "verylong"].enumerated() {
                if index > 0 {
                    live.dispatch(.next)
                    _ = try await env.waitFor { live.state.current?.position == index ? true : nil }
                }
                for screen in Self.screens {
                    let plan = try render(
                        live,
                        screen: screen.size,
                        name: "stage-\(screen.name)-\(name)",
                    )
                    // Lyrics never go below the 22pt default minimum.
                    #expect(plan.lyricSize >= LiveSettings.defaultMinLyricSize)
                    if name == "short" {
                        #expect(plan.fit == .fits, "\(name) at \(screen.name)")
                    }
                    if plan.fit == .scrollsAtMinimum {
                        // Never shrunk below the minimum: it scrolls at exactly the minimum.
                        #expect(plan.lyricSize == LiveSettings.defaultMinLyricSize)
                    }
                    if name == "verylong", screen.name == "13in" {
                        #expect(plan.needsScroll)
                    }
                }
            }
            // The overlays, at 13".
            let small = Self.screens[0].size
            live.dispatch(.toggleSidebar)
            _ = try render(live, screen: small, name: "stage-13in-drawer")
            live.dispatch(.toggleSidebar)
            live.dispatch(.toggleRequests)
            _ = try render(live, screen: small, name: "stage-13in-requests")
            live.dispatch(.toggleRequests)
            live.dispatch(.endShow)
            _ = try render(live, screen: small, name: "stage-13in-end-confirm")
            live.overlay = nil
        }

        /// The status line (and a notice in it) has its own band between the song and the
        /// footer: showing it at the start of a show changes no pixel of the song, so the
        /// last lyric line is never covered (WS6 found it over the last line).
        @Test
        func `the status line never covers the song`() async throws {
            _ = NSApplication.shared
            let env = try TestEnvironment()
            let app = try await env.openApp()
            let fixture = try await LiveFixture(app: app, titles: ["Long"], lines: 40)
            app.liveSettings.settings.hiddenChecklistItems = Set(ChecklistItem.allCases)
            #expect(await app.startShow(fixture.setlist, kind: .gig))
            let live = try #require(app.live)
            defer { StageWindowController.shared.close() }

            let screen = Self.screens[0].size
            live.notice = nil
            _ = try render(live, screen: screen, name: "stage-13in-status-hidden")
            let hidden = try Bitmap(stageImage(live, screen: screen))
            live.notice = "Kept for this show only: this song cannot be changed."
            let plan = try render(live, screen: screen, name: "stage-13in-status-shown")
            let shown = try Bitmap(stageImage(live, screen: screen))
            live.notice = nil
            // The song fills the body to its bottom edge, so a covered line would show.
            #expect(plan.needsScroll)

            // Rows in 2x pixels; the header is skipped (its clock ticks between renders), and
            // a pixel counts as changed past 8/255 (two renders differ by 1/255 in text
            // antialiasing).
            let scale = 2.0
            let bandTop = LiveView.headerHeight + LiveView.mapHeight + LiveView.bodyTopPadding
                + LiveView.viewport(for: screen, topInset: 0).height
            let bandBottom = bandTop + LiveView.statusBandHeight
            var changed = (song: 0, band: 0, footer: 0)
            for row in Int(LiveView.headerHeight * scale) ..< Int(screen.height * scale) {
                for column in 0 ..< Int(screen.width * scale)
                    where hidden.rgb(x: column, y: row).differs(from: shown.rgb(x: column, y: row))
                {
                    let y = Double(row) / scale
                    if y < bandTop {
                        changed.song += 1
                    } else if y < bandBottom {
                        changed.band += 1
                    } else {
                        changed.footer += 1
                    }
                }
            }
            #expect(changed.song == 0, "the status line changed \(changed.song) song pixels")
            #expect(changed.footer == 0, "the status line changed \(changed.footer) footer pixels")
            #expect(changed.band > 0, "the notice never showed")
        }

        /// The integration pass's review set: the basic and 40-line fixtures through the real
        /// stage at 13", 16" and 1080p, in `.build/screenshots/integration/`. Asserts the
        /// build rulings on each: no wrapped lyric line when it fits, at most two columns
        /// for the basic song, labels at least 12pt, and the plan sound.
        @Test
        func `fixtures render through the stage at every screen size`() async throws {
            _ = NSApplication.shared
            let env = try TestEnvironment()
            let app = try await env.openApp()
            let session = try #require(app.session)
            var setlist = try #require(await session.setlists.create(name: "Integration"))
            for name in ["basic-verse-chorus.cho", "live-forty-lines.cho"] {
                let source = try String(
                    contentsOf: StageLayoutSupport.fixtures.appending(path: name),
                    encoding: .utf8,
                )
                let song = try await session.library.createSong(source: source)
                await session.setlists.add(song.id, to: setlist.id)
            }
            setlist = try #require(session.setlists.selected)
            app.liveSettings.settings.hiddenChecklistItems = Set(ChecklistItem.allCases)
            #expect(await app.startShow(setlist, kind: .rehearsal))
            let live = try #require(app.live)
            defer { StageWindowController.shared.close() }
            let screens: [(name: String, size: CGSize)] = [
                ("13in", CGSize(width: 1470, height: 956)),
                ("16in", CGSize(width: 1728, height: 1117)),
                ("1080p", CGSize(width: 1920, height: 1080)),
            ]
            for (index, song) in ["basic", "forty-lines"].enumerated() {
                if index > 0 {
                    live.dispatch(.next)
                    _ = try await env.waitFor { live.state.current?.position == index ? true : nil }
                }
                for screen in screens {
                    let plan = try render(
                        live,
                        screen: screen.size,
                        name: "\(song)-\(screen.name)",
                        directory: Self.integrationDirectory,
                    )
                    try checkRulings(
                        plan,
                        live: live,
                        screen: screen.size,
                        label: "\(song) at \(screen.name)",
                    )
                    if song == "basic" {
                        #expect(plan.columns.count <= 2, "\(song) at \(screen.name)")
                    }
                    try renderHardeningSet(live, screen: screen, song: song)
                }
            }
        }

        /// The hardening review set (revised wrap ruling): the 13" stage, in
        /// `.build/screenshots/hardening/`.
        private func renderHardeningSet(
            _ live: LiveSession,
            screen: (name: String, size: CGSize),
            song: String,
        ) throws {
            guard screen.name == "13in" else { return }
            _ = try render(
                live,
                screen: screen.size,
                name: "\(song)-13in",
                directory: LiveHardeningTests.hardeningDirectory,
            )
        }

        /// The build rulings on one rendered plan: it fits at or above the minimum, labels
        /// are at least 12pt, and lyric lines wrap only when no layout without wrapping
        /// reaches the comfortable size, max(28pt, 1.25 x the minimum) (decisions.md,
        /// "Auto-fit wrapping (revised)"); a wrapped line never ends on a single word.
        private func checkRulings(
            _ plan: LayoutPlan,
            live: LiveSession,
            screen: CGSize,
            label: String,
        ) throws {
            // The section map band (R147, 58 pt) costs the 13" stage about a line: forty
            // lines no longer fit there and scroll at the minimum instead.
            let mayScroll = label == "forty-lines at 13in"
            #expect(plan.fit == .fits || (mayScroll && plan.fit == .scrollsAtMinimum), "\(label)")
            #expect(plan.lyricSize >= LiveSettings.defaultMinLyricSize, "\(label)")
            let blocks = plan.columns.flatMap(\.blocks)
            #expect(blocks.flatMap(\.labelLines).allSatisfy { $0.text.size >= 12 })
            let wrapped = Self.wrappedLines(plan)
            let unwrapped = try unwrappedSize(live, screen: screen)
            let comfortable = max(28, 1.25 * LiveSettings.defaultMinLyricSize)
            #expect(
                wrapped == 0 || unwrapped < comfortable,
                "\(label): \(wrapped) wrapped at \(plan.lyricSize)pt, \(unwrapped)pt without",
            )
            #expect(Self.widows(plan) == 0, "\(label): a wrapped line ends on one word")
            print("Integration: \(label) \(plan.lyricSize)pt \(plan.columns.count) col, "
                + "\(wrapped) wrapped (largest without wrapping \(unwrapped)pt)")
        }

        /// Wrapped lyric lines whose last row holds a single word.
        static func widows(_ plan: LayoutPlan) -> Int {
            let rows = plan.columns.flatMap(\.blocks).flatMap(\.allRows)
                .filter { $0.kind == .lyric && $0.source != nil }
            let lines = Dictionary(grouping: rows) { $0.source }.values.filter { $0.count > 1 }
            return lines.count { line in
                let last = line.max { $0.y < $1.y }
                let words = last?.text.map(\.text).joined().split(whereSeparator: \.isWhitespace)
                return words?.count == 1
            }
        }

        /// Lyric lines laid out on more than one row.
        static func wrappedLines(_ plan: LayoutPlan) -> Int {
            let rows = plan.columns.flatMap(\.blocks).flatMap(\.allRows)
            let sources = rows.filter { $0.kind == .lyric }.compactMap(\.source)
            return Dictionary(grouping: sources) { $0 }.values.count { $0.count > 1 }
        }

        /// The largest size any forced column count reaches without a wrapped lyric line
        /// (with no comfortable size, so any layout without wrapping wins).
        private func unwrappedSize(_ live: LiveSession, screen: CGSize) throws -> Double {
            let model = try #require(live.currentModel)
            var style = LayoutStyle.stage
            style.comfortableLyricSize = 0
            style.comfortableMinimumFactor = 0
            return (1 ... 3).map { columns in
                LayoutEngine.plan(
                    LayoutRequest(
                        model: model,
                        viewport: LiveView.viewport(for: screen, topInset: 0),
                        minLyricSize: LiveSettings.defaultMinLyricSize,
                        columns: columns,
                        style: style,
                    ),
                    metrics: StageTextMetrics(),
                )
            }
            .filter { $0.fit == .fits && Self.wrappedLines($0) == 0 }
            .map(\.lyricSize)
            .max() ?? 0
        }

        /// `<repo>/.build/screenshots/integration`.
        static var integrationDirectory: URL {
            screenshotDirectory
                .deletingLastPathComponent()
                .appending(path: "integration", directoryHint: .isDirectory)
        }

        /// Lays out for `screen`, renders the stage and writes the PNG; returns the plan.
        private func render(
            _ live: LiveSession,
            screen: CGSize,
            name: String,
            directory: URL = Self.screenshotDirectory,
        ) throws -> LayoutPlan {
            live.setViewport(LiveView.viewport(for: screen, topInset: 0))
            let plan = try #require(live.plan)
            let image = try stageImage(live, screen: screen)
            #expect(image.width == Int(screen.width * 2))
            try DiagramSnapshotTests.writePNG(image, to: directory.appending(path: "\(name).png"))
            return plan
        }

        /// The stage at `screen`, rendered at 2x in the dark stage theme.
        private func stageImage(_ live: LiveSession, screen: CGSize) throws -> CGImage {
            let view = LiveView(session: live)
                .frame(width: screen.width, height: screen.height)
                .environment(\.colorScheme, .dark)
            let renderer = ImageRenderer(content: view)
            renderer.scale = 2
            return try #require(renderer.cgImage, "no stage image")
        }

        /// `<repo>/.build/screenshots/live`.
        static var screenshotDirectory: URL {
            DiagramSnapshotTests.screenshotDirectory
                .deletingLastPathComponent()
                .appending(path: "live", directoryHint: .isDirectory)
        }
    }
}

private extension RGB {
    /// More than 8/255 apart in any channel.
    func differs(from other: RGB) -> Bool {
        abs(Int(red) - Int(other.red)) > 8 || abs(Int(green) - Int(other.green)) > 8
            || abs(Int(blue) - Int(other.blue)) > 8
    }
}
