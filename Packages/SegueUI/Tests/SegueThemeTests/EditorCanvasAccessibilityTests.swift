import AppKit
@testable import SegueUI
import Testing

/// The canvas exposes each chord pill and each word's chord slot to accessibility (UI tests
/// and VoiceOver find pills by label).
@MainActor
struct EditorCanvasAccessibilityTests {
    @Test
    func `pills and chord slots are accessibility elements`() throws {
        #expect(Theme.registerFonts())
        let model = SongEditorViewModel(
            mode: .create,
            source: "{key: G}\n{start_of_verse}\n[C]Dil ki [G]baat\n{end_of_verse}\n",
        ) { _ in throw CancellationError() }
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 900, height: 600),
            styleMask: [.titled],
            backing: .buffered,
            defer: false,
        )
        window.isReleasedWhenClosed = false
        defer { window.close() }
        model.setEditorMode(.visual)
        let canvas = model.visualEditor
        canvas.container.frame = NSRect(x: 0, y: 0, width: 900, height: 600)
        window.contentView = canvas.container
        window.layoutIfNeeded()
        canvas.didAttach()
        let elements = canvas.overlayAccessibilityElements(for: canvas.container.overlay)
            .compactMap { $0 as? NSAccessibilityElement }
        let pills = elements.filter { $0.accessibilityIdentifier() == AccessibilityID.editorPill }
        let lanes = elements.filter { $0.accessibilityIdentifier() == AccessibilityID.editorLane }
        #expect(pills.compactMap { $0.accessibilityLabel() } == ["C", "G"])
        #expect(lanes.compactMap { $0.accessibilityLabel() } == ["Dil", "ki", "baat"])
        #expect(pills.allSatisfy { $0.accessibilityFrame().width > 20 })
        // Everything a drag does, without one (WS2b 4.9.2).
        for pill in pills {
            #expect(pill.accessibilityCustomActions()?.map(\.name) == [
                "Move left one syllable", "Move right one syllable", "Edit chord", "Delete chord",
            ])
        }

        // Move right one syllable: C goes from "Dil" to "ki".
        let moveRight = try #require(pills.first?.accessibilityCustomActions()?[1])
        #expect(moveRight.handler?() == true)
        #expect(model.source.contains("Dil [C]ki [G]baat"), "\(model.source)")
    }

    @Test
    func `a sheet line reads its chords then its lyric`() {
        let tokens = [
            LyricToken(id: 0, chord: "G", text: "Van door slides and the "),
            LyricToken(id: 1, chord: "D", text: "street lamps hum,"),
        ]
        #expect(LyricLineView.spokenText(tokens)
            == "G, D: Van door slides and the street lamps hum,")
        #expect(LyricLineView.spokenText([LyricToken(id: 0, chord: nil, text: "No chords ")])
            == "No chords")
        #expect(LyricLineView.spokenText([LyricToken(id: 0, chord: "Am", text: "")]) == "Am")
    }
}

/// Canvas text edits become tree operations; tab/grid stays read-only.
@MainActor
struct EditorCanvasEditingTests {
    static let song = """
    {key: G}
    {start_of_verse}
    [G]Tum hi [C]ho
    {end_of_verse}
    {start_of_tab}
    e|---0---|
    {end_of_tab}

    """

    private struct Hosted {
        let model: SongEditorViewModel
        let canvas: VisualEditorController
        let window: NSWindow
    }

    private func canvas() -> Hosted {
        let model = SongEditorViewModel(mode: .create, source: Self.song) { _ in
            throw CancellationError()
        }
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 900, height: 600),
            styleMask: [.titled],
            backing: .buffered,
            defer: false,
        )
        window.isReleasedWhenClosed = false
        _ = model.sourceEditor
        model.setEditorMode(.visual)
        let canvas = model.visualEditor
        canvas.container.frame = window.contentLayoutRect
        window.contentView = canvas.container
        canvas.didAttach()
        return Hosted(model: model, canvas: canvas, window: window)
    }

    private func paragraph(
        _ canvas: VisualEditorController,
        _ match: (CanvasParagraph) -> Bool,
    ) throws -> Int {
        let index = canvas.projection.paragraphs.firstIndex(where: match)
        return try #require(index)
    }

    @Test
    func `tab blocks are read-only with a link to text mode`() throws {
        let hosted = canvas()
        let (model, canvas) = (hosted.model, hosted.canvas)
        defer { hosted.window.close() }
        let roles = canvas.projection.paragraphs.map(\.role)
        #expect(roles.contains {
            if case .textModeLink = $0 {
                true
            } else {
                false
            }
        })
        let tab = try paragraph(canvas) {
            if case .verbatim = $0.role {
                true
            } else {
                false
            }
        }
        let start = canvas.projection.starts[tab]
        canvas.textView.insertText("x", replacementRange: NSRange(location: start + 2, length: 0))
        #expect(model.source == Self.song)
    }

    @Test
    func `typing in a lyric line edits the lyric and keeps chords on their syllables`() throws {
        let hosted = canvas()
        let (model, canvas) = (hosted.model, hosted.canvas)
        defer { hosted.window.close() }
        let line = try paragraph(canvas) { $0.isLyrics }
        let start = canvas.projection.starts[line]
        // "Tum hi ho": insert "sach " before "ho" (offset 7).
        canvas.textView.setSelectedRange(NSRange(location: start + 7, length: 0))
        canvas.textView.insertText(
            "sach ",
            replacementRange: NSRange(location: start + 7, length: 0),
        )
        #expect(model.source.contains("[G]Tum hi [C]sach ho") || model.source
            .contains("[G]Tum hi sach [C]ho"))
        #expect(canvas.textView.selectedRange().location == start + 12)
        // Return splits the line; Backspace at the start joins it back.
        canvas.textView.insertText("\n", replacementRange: canvas.textView.selectedRange())
        #expect(model.snapshot.document.metadata.key == "G")
        let lines = model.source.split(separator: "\n")
            .filter { $0.contains("Tum") || $0.contains("ho") }
        #expect(lines.count == 2, "\(model.source)")
        canvas.textView.deleteBackward(nil)
        #expect(model.source.split(separator: "\n")
            .contains { $0.contains("Tum") && $0.contains("ho") })
    }

    @Test
    func `renaming a section from its band sets the label`() throws {
        let hosted = canvas()
        let (model, canvas) = (hosted.model, hosted.canvas)
        defer { hosted.window.close() }
        // The label lives in the band's cap now (P3-11), not in a text row.
        #expect(!canvas.projection.paragraphs.contains {
            if case .label = $0.role {
                true
            } else {
                false
            }
        })
        let band = try #require(canvas.bands.bands.first { $0.title == "Verse" })
        #expect(try canvas.rename(#require(band.sectionPath), to: "Verse 1"))
        #expect(model.source.contains("{start_of_verse: Verse 1}"), "\(model.source)")
    }
}
