import AppKit
import Editing
@testable import SegueUI
import Testing

/// Text-mode typing and visual tree edits share one undo stack, one step per action.
@MainActor
struct EditorUndoTests {
    @Test
    func `a visual edit after typing is its own undo step`() throws {
        let model = SongEditorViewModel(mode: .create, source: "") { _ in
            throw CancellationError()
        }
        let source = model.sourceEditor
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 800, height: 600),
            styleMask: [.titled],
            backing: .buffered,
            defer: false,
        )
        window.isReleasedWhenClosed = false
        defer { window.close() }
        window.contentView = source.scrollView
        window.makeFirstResponder(source.textView)
        let undo = source.undoManager
        undo.groupsByEvent = false
        let text = "{key: Am}\n{start_of_verse}\n[Am]Dil ki raah pe [F]chalte\n{end_of_verse}\n"
        undo.beginUndoGrouping()
        source.textView.insertText(text, replacementRange: NSRange(location: 0, length: 0))
        undo.endUndoGrouping()
        model.setEditorMode(.visual)
        // As in the app: the canvas replaces the source view in the window.
        window.contentView = model.visualEditor.container
        window.makeFirstResponder(model.visualEditor.textView)
        let ref = try #require(model.snapshot.chords.last?.ref)
        undo.beginUndoGrouping()
        #expect(model.perform(.deleteChord(ref)))
        undo.endUndoGrouping()
        #expect(!model.source.contains("[F]"))
        #expect(undo.undoActionName == "Delete Chord")
        undo.undo()
        #expect(source.textView.string == text)
        // The model (and canvas) follow the undo.
        #expect(model.source == text, "after undo: \(model.source)")
        #expect(model.visualEditor.projection.text.contains("Dil ki raah pe chalte"))
        undo.redo()
        #expect(!model.source.contains("[F]"))
    }
}
