import AppKit
@testable import SegueUI
import SwiftUI
import Testing

/// Every Settings pane is exactly as tall as its form (`SettingsPaneHeight`), so the window
/// shows all of it at its default size and grows when content arrives late. Each pane is
/// rendered at that size into `.build/screenshots/settings-panes/` for the visual review.
@MainActor
struct SettingsPanesTests {
    @Test
    func `every pane is as tall as its content and renders unclipped`() async throws {
        let env = try TestEnvironment()
        let dependencies = env.dependencies(
            location: env.location(),
            override: env.libraryURL,
            remember: false,
        )
        let app = AppModel(dependencies: dependencies)
        await app.start()
        let panes: [(String, AnyView)] = [
            ("general", AnyView(GeneralSettingsView(app: app))),
            ("appearance", AnyView(AppearanceSettingsView(store: app.polish.appearance))),
            ("instrument", AnyView(InstrumentSettingsView(store: app.instrumentProfile))),
            (
                "audio",
                AnyView(AudioSettingsView(sound: app.sound, instrument: app.instrumentProfile)),
            ),
            ("live", AnyView(LiveSettingsView(
                store: app.liveSettings,
                shortcuts: app.dependencies.live.shortcuts,
                workspace: app.dependencies.workspace,
            ))),
            ("privacy", AnyView(PrivacySettingsView(
                store: app.dependencies.consent,
                workspace: app.dependencies.workspace,
            ))),
            ("data", AnyView(DataSettingsView(app: app))),
        ]
        for (name, pane) in panes {
            let controller = NSHostingController(
                rootView: pane.frame(width: 560).guideLinks(NSWorkspaceActions()),
            )
            // The least height the pane accepts equals the height it asks for: the window
            // cannot be shorter than its content (up to the 640 pt cap).
            let least = controller.sizeThatFits(in: CGSize(width: 560, height: 0)).height
            let ideal = controller.sizeThatFits(in: CGSize(width: 560, height: 10000)).height
            #expect(least == ideal, "\(name): \(least) vs \(ideal)")
            #expect(least <= SettingsPaneHeight.maximumHeight, "\(name) is taller than the cap")
            // With the guide action set, as in the app, so the Help buttons show.
            let host = NSHostingView(
                rootView: pane.frame(width: 560).guideLinks(NSWorkspaceActions()),
            )
            host.appearance = NSAppearance(named: .darkAqua)
            host.frame = NSRect(origin: .zero, size: host.fittingSize)
            host.layoutSubtreeIfNeeded()
            let rep = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
            host.cacheDisplay(in: host.bounds, to: rep)
            try DiagramSnapshotTests.writePNG(
                #require(rep.cgImage),
                to: Self.directory
                    .appending(path: "\(name)-dark.png"),
            )
        }
    }

    /// `<repo>/.build/screenshots/settings-panes`.
    static var directory: URL {
        DiagramSnapshotTests.screenshotDirectory
            .deletingLastPathComponent()
            .appending(path: "settings-panes", directoryHint: .isDirectory)
    }
}
