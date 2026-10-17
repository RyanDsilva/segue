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
                    source: LiveFixture.source(title: title, lines: lines, duration: "3:00"),
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

        /// Lays out for `screen`, renders the stage and writes the PNG; returns the plan.
        private func render(
            _ live: LiveSession,
            screen: CGSize,
            name: String,
        ) throws -> LayoutPlan {
            live.setViewport(LiveView.viewport(for: screen, topInset: 0))
            let plan = try #require(live.plan)
            let view = LiveView(session: live)
                .frame(width: screen.width, height: screen.height)
                .environment(\.colorScheme, .dark)
            let renderer = ImageRenderer(content: view)
            renderer.scale = 2
            let image = try #require(renderer.cgImage, "no image for \(name)")
            #expect(image.width == Int(screen.width * 2))
            try DiagramSnapshotTests.writePNG(
                image,
                to: Self.screenshotDirectory.appending(path: "\(name).png"),
            )
            return plan
        }

        /// `<repo>/.build/screenshots/live`.
        static var screenshotDirectory: URL {
            DiagramSnapshotTests.screenshotDirectory
                .deletingLastPathComponent()
                .appending(path: "live", directoryHint: .isDirectory)
        }
    }
}
