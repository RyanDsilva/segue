import ChordPro
import Diagrams
import Editing
import Foundation
import Library
import MusicTheory
#if os(macOS)
    import AppKit
#endif

extension SongEditorViewModel {
    // MARK: Mode switching

    #if os(macOS)
        /// The text mode controller (created on first use).
        var sourceEditor: SourceEditorController {
            if let sourceController {
                return sourceController
            }
            let controller = SourceEditorController(text: source)
            controller.host = self
            controller.pendingFocus = editorMode == .text
            sourceController = controller
            controller.restyleAll()
            controller.showDiagnostics(diagnostics, for: source)
            return controller
        }

        /// The visual canvas controller (created on first use).
        var visualEditor: VisualEditorController {
            if let visualController {
                return visualController
            }
            let controller = VisualEditorController(model: self)
            controller.pendingFocus = true
            visualController = controller
            if editorMode == .visual {
                refreshCanvas()
            }
            return controller
        }

        /// Shows a diagnostic in the source (switching to text mode).
        func reveal(_ diagnostic: EditorDiagnostic) {
            setEditorMode(.text)
            let range = diagnostic.range
            sourceEditor.select(NSRange(location: range.lowerBound, length: range.count))
            sourceEditor.pendingFocus = true
        }

        /// Both editor views' automatic text settings, for UI tests (all must be "off").
        var inputSettingsReport: String {
            "source: \(EditorTextInput.report(sourceEditor.textView)) "
                + "visual: \(EditorTextInput.report(visualEditor.textView))"
        }

        var isUndoingOrRedoing: Bool {
            guard let sourceController else { return false }
            let undoManager = sourceController.undoManager
            return undoManager.isUndoing || undoManager.isRedoing
                || sourceController.isSyncingUndo
        }

        var sourceSelection: NSRange? {
            sourceController?.selectedRange
        }

        /// Switches modes, carrying the caret across (same lyric line and character).
        public func setEditorMode(_ newMode: EditorMode) {
            guard newMode != editorMode else { return }
            // Each mode's typing is measured on its own.
            resetKeystrokeStats()
            let source = sourceEditor
            // Close the open "Typing" undo group while the source view is still attached, so
            // the next visual edit is its own undo step.
            source.textView.breakUndoCoalescing()
            switch newMode {
            case .visual:
                let offset = source.selectedRange.location
                editorMode = .visual
                refreshCanvas()
                let position = snapshot.lyricPosition(atSourceOffset: offset)
                visualEditor.pendingCaret = position
                visualEditor.pendingFocus = true
            case .text:
                let offset = visualEditor.caretSourceOffset()
                editorMode = .text
                canvasModel = nil
                if let offset {
                    source.select(NSRange(location: offset, length: 0))
                }
                source.pendingFocus = true
            }
        }
    #else
        public func setEditorMode(_ newMode: EditorMode) {
            editorMode = newMode
        }
    #endif
}

#if os(macOS)
    extension SongEditorViewModel: SourceEditorHost {
        func sourceSelectionDidChange(_ range: NSRange) {
            guard editorMode == .text else { return }
            sourceCaretDidMove(to: range.location)
        }

        func chordCompletionSources() -> (song: [String], diatonic: [String]) {
            var seen = Set<String>()
            let song = snapshot.chords.compactMap { occurrence -> String? in
                guard occurrence.token.chord != nil else { return nil }
                let text = occurrence.token.original
                return seen.insert(text).inserted ? text : nil
            }
            let key = KeyContext(document: snapshot.document).writtenKey
            return (song, key?.diatonicChordSymbols ?? [])
        }

        func keystrokeTimed(_ seconds: TimeInterval, isShortcut: Bool) {
            recordKeystroke(seconds, isShortcut: isShortcut)
        }
    }
#endif
