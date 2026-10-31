import AppKit
@testable import SegueUI
import SwiftUI
import Testing

/// The fill sheet at its default size (P8-7 16.3), light and dark, on Fretboard and Piano
/// Roll, written to `.build/screenshots/fill-editor` for review.
@MainActor
@Suite(.serialized)
struct FillEditorSnapshotTests {
    @Test(arguments: FillEditorView.allCases)
    func `the sheet renders at its default size in light and dark`(view: FillEditorView)
        async throws
    {
        #expect(Theme.registerFonts())
        let base = try await ChordSpanSelectionTests.open()
        base.editor.refreshSpanSelection()
        base.editor.openFillEditor(span: 1 ... 2)
        let sheet = try #require(base.editor.fillEditor)
        sheet.view = view
        let first = try #require(sheet.draft.ordered(on: sheet.grid).first)
        sheet.draft.selection = [first.id]
        for dark in [false, true] {
            let host = NSHostingView(rootView: FillEditorSheet(model: sheet) { _ in }
                .frame(width: 1040, height: 700))
            host.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
            host.frame = NSRect(x: 0, y: 0, width: 1040, height: 700)
            host.layoutSubtreeIfNeeded()
            let rep = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
            host.cacheDisplay(in: host.bounds, to: rep)
            let image = try #require(rep.cgImage)
            #expect(image.width >= 1040)
            try DiagramSnapshotTests.writePNG(
                image,
                to: DiagramSnapshotTests.screenshotDirectory.deletingLastPathComponent()
                    .appending(path: "fill-editor/\(view.rawValue)-\(dark ? "dark" : "light").png"),
            )
        }
    }
}
