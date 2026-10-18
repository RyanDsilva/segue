import AppKit
import Editing
import Library
@testable import SegueUI
import Testing

/// Phase 1 review fixes (docs/reviews/phase1-review.md) through the real editor: canvas
/// edits around chords inside grapheme clusters (#1), unchanged popover commits (#3), lyric
/// edits that would change the line's kind (#4), and the unsaved baseline after a save that
/// keeps the editor open (#5).
@MainActor
@Suite(.serialized)
struct EditorReviewFixesTests {
    private struct Hosted {
        let model: SongEditorViewModel
        let canvas: VisualEditorController
        let window: NSWindow
    }

    private func canvas(_ source: String) -> Hosted {
        let model = SongEditorViewModel(mode: .create, source: source) { _ in
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

    private func lyricLine(_ canvas: VisualEditorController) throws -> (Int, RenderLine) {
        let index = try #require(canvas.projection.paragraphs.firstIndex { $0.isLyrics })
        let line = try #require(canvas.projection.paragraphs[index].lyricLine)
        return (index, line)
    }

    @Test(arguments: [
        "[C]\u{092A}[G]\u{094D}\u{092F}\u{093E}\u{0930} x\n",
        "[C]e[G]\u{0301}tude x\n",
        "[C]\u{1F468}[G]\u{200D}\u{1F469} dil x\n",
    ])
    func `backspace at the end of a line with a chord inside a cluster deletes the last character`(
        source: String,
    ) throws {
        let hosted = canvas(source)
        defer { hosted.window.close() }
        let (index, line) = try lyricLine(hosted.canvas)
        let end = hosted.canvas.projection.starts[index] + line.lyrics.utf16.count
        hosted.canvas.textView.setSelectedRange(NSRange(location: end, length: 0))
        hosted.canvas.textView.deleteBackward(nil)
        #expect(hosted.model.source == String(source.dropLast(2)) + "\n")
        // Typing it back lands at the end again.
        hosted.canvas.textView.insertText(
            "y",
            replacementRange: hosted.canvas.textView.selectedRange(),
        )
        #expect(hosted.model.source == String(source.dropLast(2)) + "y\n")
    }

    @Test
    func `committing the chord unchanged leaves the source alone`() throws {
        // G# is out of key in C and would come back as Ab if re-mapped (transposed view).
        let hosted = canvas("{key: C}\n[G#]Dil ki [C]baat\n")
        defer { hosted.window.close() }
        hosted.model.stepTranspose(by: 2)
        let (_, line) = try lyricLine(hosted.canvas)
        let chord = try #require(line.chords.first)
        let shown = hosted.canvas.shownText(of: chord)
        #expect(shown == "A#")
        hosted.canvas.commitEdit(of: chord, on: line, typed: shown)
        #expect(hosted.model.source == "{key: C}\n[G#]Dil ki [C]baat\n")
        hosted.canvas.commitEdit(of: chord, on: line, typed: "B")
        #expect(hosted.model.source == "{key: C}\n[A]Dil ki [C]baat\n")
    }

    @Test
    func `typing that would make a comment, directive or chord is refused`() throws {
        let source = "{start_of_verse}\nDil ki baat\n{end_of_verse}\n"
        let hosted = canvas(source)
        defer { hosted.window.close() }
        let (index, _) = try lyricLine(hosted.canvas)
        let start = hosted.canvas.projection.starts[index]
        let textView = hosted.canvas.textView
        textView.insertText("#", replacementRange: NSRange(location: start, length: 0))
        #expect(hosted.model.source == source)
        textView.insertText("[Am]", replacementRange: NSRange(location: start + 4, length: 0))
        #expect(hosted.model.source == source)
        textView.insertText("{x}", replacementRange: NSRange(location: start, length: 11))
        #expect(hosted.model.source == source)
        textView.insertText("ab", replacementRange: NSRange(location: start, length: 0))
        #expect(hosted.model.source.contains("abDil ki baat"))
    }

    @Test
    func `after a save that keeps the editor open, unsaved compares with what was saved`()
        async throws
    {
        let env = try TestEnvironment()
        let library = try await env.openLibrary()
        let created = try await library.createSong(source: "{title: Baseline}\nOne\n")
        library.beginEditing(created)
        let editor = try #require(library.editor)
        editor.sourceTextDidChange("{title: Baseline}\nTwo\n")

        let save = Task { await editor.commit() }
        let deadline = ContinuousClock.now + .seconds(10)
        while !editor.isSaving, ContinuousClock.now < deadline {
            await Task.yield()
        }
        editor.sourceTextDidChange("{title: Baseline}\nTwo, typed during the save\n")
        _ = await save.value
        #expect(library.editor === editor)
        #expect(editor.hasUnsavedChanges)
        // Typing back exactly what was saved leaves nothing unsaved (not the old original).
        editor.sourceTextDidChange("{title: Baseline}\nTwo\n")
        #expect(!editor.hasUnsavedChanges)
        editor.sourceTextDidChange("{title: Baseline}\nOne\n")
        #expect(editor.hasUnsavedChanges)
    }
}
