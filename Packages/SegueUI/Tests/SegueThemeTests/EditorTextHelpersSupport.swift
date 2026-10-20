import AppKit
@testable import SegueUI

/// A source editor hosted in a window, as the app does, for the `{` completion and slash
/// menu tests.
@MainActor
struct HostedSourceEditor {
    let model: SongEditorViewModel
    let window: NSWindow

    var source: SourceEditorController {
        model.sourceEditor
    }

    init(_ text: String) {
        model = SongEditorViewModel(mode: .create, source: text) { _ in
            throw CancellationError()
        }
        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 800, height: 600),
            styleMask: [.titled],
            backing: .buffered,
            defer: false,
        )
        window.isReleasedWhenClosed = false
        window.contentView = model.sourceEditor.scrollView
        window.makeFirstResponder(model.sourceEditor.textView)
        model.sourceEditor.undoManager.groupsByEvent = false
    }

    /// Puts the caret (or a selection) at `range` (UTF-16).
    func select(_ location: Int, length: Int = 0) {
        source.textView.setSelectedRange(NSRange(location: location, length: length))
    }

    /// Types `text` at the selection as the keyboard would, one character at a time, and
    /// runs the completion update the text view schedules after each keystroke.
    func type(_ text: String) {
        for character in text {
            let undo = source.undoManager
            undo.beginUndoGrouping()
            source.textView.insertText(
                String(character),
                replacementRange: source.textView.selectedRange(),
            )
            undo.endUndoGrouping()
            source.updateCompletion(typed: String(character))
        }
    }

    /// Accepts the popup's selected item as one user action (one undo group).
    func accept() {
        grouped { source.acceptCompletion() }
    }

    /// Backspace as the keyboard sends it.
    func deleteBackward() {
        grouped { source.textView.deleteBackward(nil) }
    }

    private func grouped(_ action: () -> Void) {
        source.undoManager.beginUndoGrouping()
        action()
        source.undoManager.endUndoGrouping()
    }

    func close() {
        source.completion.hide()
        window.close()
    }
}
