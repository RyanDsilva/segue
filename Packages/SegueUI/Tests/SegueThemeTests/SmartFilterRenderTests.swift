import AppKit
import Library
@testable import SegueUI
import SwiftUI
import Testing

/// Renders the smart filter editor sheet (direction A) in light and dark into
/// `.build/screenshots/smart-filters/` for the visual review, through a real
/// `NSHostingView` so the AppKit popups and fields draw as they do in the app.
@MainActor
struct SmartFilterRenderTests {
    @Test
    func `the editor sheet renders in light and dark`() throws {
        let conditions = SmartFilterConditions(
            anyTags: ["upbeat", "crowd pleaser"],
            proficiencies: [.ready, .pro],
            keys: ["G", "Em"],
            tempo: SmartFilterRange(min: 80, max: 120),
            neverPlayed: true,
        )
        for dark in [false, true] {
            let sheet = SmartFilterEditorSheet(
                title: "Edit Smart Filter",
                saveTitle: "Save",
                draft: SmartFilterDraft(name: "Openers", conditions: conditions),
                libraryTags: ["upbeat", "ballad", "crowd pleaser"],
                songs: [],
                playStats: [:],
            ) { _, _ in }
                .background(Theme.color.ground)
            let host = NSHostingView(rootView: sheet)
            host.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
            host.frame = NSRect(origin: .zero, size: host.fittingSize)
            host.layoutSubtreeIfNeeded()
            let rep = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
            host.cacheDisplay(in: host.bounds, to: rep)
            let image = try #require(rep.cgImage)
            #expect(image.width > 600)
            try DiagramSnapshotTests.writePNG(image, to: Self.directory.appending(
                path: "editor-\(dark ? "dark" : "light").png",
            ))
        }
    }

    /// `<repo>/.build/screenshots/smart-filters`.
    static var directory: URL {
        DiagramSnapshotTests.screenshotDirectory
            .deletingLastPathComponent()
            .appending(path: "smart-filters", directoryHint: .isDirectory)
    }
}
