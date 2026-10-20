#if os(macOS)
    import AppKit
    import Editing

    /// What the source editor needs from the editor model.
    @MainActor
    protocol SourceEditorHost: AnyObject {
        /// The snapshot of the text as it is now (rebuilt in `sourceTextDidChange`).
        var snapshot: SourceSnapshot { get }
        /// Every text change, typed or applied: rebuild the snapshot from `text`.
        func sourceTextDidChange(_ text: String)
        func sourceSelectionDidChange(_ range: NSRange)
        /// `[` completions for `prefix` (what follows the `[`), most relevant first.
        func chordCompletions(prefix: String) -> [ChordCompletion]
        #if DEBUG
            func keystrokeTimed(_ seconds: TimeInterval, isShortcut: Bool)
        #endif
    }

    /// Owns the ChordPro source text view: the single undoable store of the song (phase 1
    /// interfaces, "Source of truth"). Applies tree edits from visual mode as one undo group,
    /// colours the syntax incrementally, underlines diagnostics, and runs `[` / `{`
    /// completion.
    @MainActor
    final class SourceEditorController: NSObject {
        let scrollView: NSScrollView
        let textView: SourceTextView
        /// The editor's one undo stack, shared with visual mode.
        let undoManager = UndoManager()
        weak var host: (any SourceEditorHost)?
        /// Focus the text view once it is back in a window (after a mode switch).
        var pendingFocus = false

        let completion = CompletionPopup()
        /// The chord completions the popup shows (titles), with what each one inserts.
        var chordCompletions: [ChordCompletion] = []
        /// The range touched since the last restyle (UTF-16, post-edit coordinates).
        var pendingEditedRange: NSRange?
        /// Set while a `SourceChange` is applied, so completion ignores it.
        var isApplyingChange = false
        /// The replacement text of the last user edit, to spot `[` / `{` being typed.
        var lastTypedText: String?
        /// Diagnostics shown inline, and the text they were computed for.
        var diagnostics: [EditorDiagnostic] = []
        var diagnosticsText = ""

        init(text: String) {
            let textView = SourceTextView(usingTextLayoutManager: true)
            self.textView = textView
            scrollView = NSScrollView()
            super.init()
            configure(text: text)
        }

        var text: String {
            textView.string
        }

        var selectedRange: NSRange {
            textView.selectedRange()
        }

        // MARK: Setup

        func configure(text: String) {
            EditorScrollView.configure(scrollView)
            textView.minSize = NSSize(width: 0, height: 0)
            textView.maxSize = NSSize(
                width: CGFloat.greatestFiniteMagnitude,
                height: CGFloat.greatestFiniteMagnitude,
            )
            textView.isVerticallyResizable = true
            textView.isHorizontallyResizable = false
            textView.autoresizingMask = [.width]
            textView.textContainer?.widthTracksTextView = true
            EditorTextInput.configure(textView)
            textView.drawsBackground = false
            textView.textContainerInset = NSSize(width: SourceTextView.gutterWidth / 2, height: 20)
            textView.insertionPointColor = EditorStyle.ink
            textView.selectedTextAttributes = [
                .backgroundColor: NSColor.selectedTextBackgroundColor,
            ]
            textView.font = EditorStyle.sourceFont
            textView.typingAttributes = Self.baseAttributes
            configureAccessibility()
            textView.delegate = self
            textView.textStorage?.delegate = self
            textView.keyHandler = self
            #if DEBUG
                textView.onKeystrokeTimed = { [weak self] seconds, isShortcut in
                    self?.host?.keystrokeTimed(seconds, isShortcut: isShortcut)
                }
            #endif
            scrollView.documentView = textView

            textView.string = text
            textView.updateLineStarts()
            pendingEditedRange = nil
            // Undo / redo change the text without a `textDidChange` when the source view is
            // not the one being edited (visual mode), so resync on the undo manager's signal.
            for name: NSNotification.Name in [
                .NSUndoManagerDidUndoChange,
                .NSUndoManagerDidRedoChange,
            ] {
                NotificationCenter.default.addObserver(
                    self,
                    selector: #selector(undoManagerDidChange),
                    name: name,
                    object: undoManager,
                )
            }
            completion.onPick = { [weak self] index in
                self?.acceptCompletion(at: index)
            }
            Task { @MainActor [completion] in
                completion.prepare()
            }
        }

        private func configureAccessibility() {
            textView.setAccessibilityIdentifier(AccessibilityID.editorText)
            textView.setAccessibilityLabel("ChordPro source")
            // Exposed explicitly: without any accessibility help set, AppKit no longer
            // surfaces the text view as its own element to XCUITest.
            textView.setAccessibilityElement(true)
        }

        /// Colours the whole text (on load and when the snapshot was replaced wholesale).
        func restyleAll() {
            restyle(NSRange(location: 0, length: (textView.string as NSString).length))
        }

        // MARK: Applying tree edits

        /// Applies a planned change as one undo step named `change.actionName`, through the
        /// text view (so it is undoable exactly like typing), then selects `selectionAfter`.
        func apply(_ change: SourceChange) {
            guard !change.isEmpty, let storage = textView.textStorage else { return }
            let edits = change.edits.sorted { $0.range.lowerBound < $1.range.lowerBound }
            let ranges = edits.map { NSValue(range: $0.nsRange) }
            let strings = edits.map(\.replacement)
            completion.hide()
            isApplyingChange = true
            defer { isApplyingChange = false }
            textView.breakUndoCoalescing()
            undoManager.beginUndoGrouping()
            if textView.shouldChangeText(inRanges: ranges, replacementStrings: strings) {
                storage.beginEditing()
                for edit in edits.reversed() {
                    storage.replaceCharacters(in: edit.nsRange, with: edit.replacement)
                }
                storage.endEditing()
                if let selection = change.selectionAfter {
                    textView.setSelectedRange(NSRange(
                        location: selection.lowerBound,
                        length: selection.count,
                    ))
                }
                textView.didChangeText()
            }
            undoManager.setActionName(change.actionName)
            undoManager.endUndoGrouping()
            textView.breakUndoCoalescing()
        }

        /// Set while an undo or redo is being synced to the editor (the canvas then maps
        /// the caret from the source selection the undo restored).
        private(set) var isSyncingUndo = false

        @objc private func undoManagerDidChange(_: Notification) {
            guard host?.snapshot.text != textView.string else { return }
            isSyncingUndo = true
            defer { isSyncingUndo = false }
            textView.updateLineStarts()
            textView.gutter.needsDisplay = true
            host?.sourceTextDidChange(textView.string)
            if let range = pendingEditedRange {
                pendingEditedRange = nil
                restyle(range)
            }
        }

        /// Replaces the whole text (one undo step).
        func replaceAll(with text: String, actionName: String = "Replace Text") {
            let length = (textView.string as NSString).length
            apply(SourceChange(
                edits: [TextEdit(range: 0 ..< length, replacement: text)],
                actionName: actionName,
            ))
            restyleAll()
        }

        /// Selects a UTF-16 range and scrolls it into view.
        func select(_ range: NSRange) {
            let length = (textView.string as NSString).length
            let location = min(max(range.location, 0), length)
            let clamped = NSRange(location: location, length: min(range.length, length - location))
            textView.setSelectedRange(clamped)
            textView.scrollRangeToVisible(clamped)
        }

        func focus() {
            textView.window?.makeFirstResponder(textView)
            completion.prepare()
        }

        // MARK: Diagnostics

        /// Shows `diagnostics` (computed for `text`) as underlines with tooltips. Ignored when
        /// the text has moved on since; the next debounce brings fresh ones.
        func showDiagnostics(_ newDiagnostics: [EditorDiagnostic], for text: String) {
            guard text == textView.string else { return }
            // Underlines already shown move with the text, so find them where they are now.
            var touched = newDiagnostics.map { lineRange(for: $0.range) }
            if let storage = textView.textStorage {
                storage.enumerateAttribute(
                    .underlineStyle,
                    in: NSRange(location: 0, length: storage.length),
                ) { value, range, _ in
                    if value != nil {
                        touched.append(range)
                    }
                }
            }
            diagnostics = newDiagnostics
            diagnosticsText = text
            guard !touched.isEmpty else { return }
            for range in touched {
                restyle(range)
            }
        }

        // MARK: Styling

        static var paragraphStyle: NSParagraphStyle {
            let style = NSMutableParagraphStyle()
            style.minimumLineHeight = EditorStyle.sourceLineHeight
            style.maximumLineHeight = EditorStyle.sourceLineHeight
            return style
        }

        static var baseAttributes: [NSAttributedString.Key: Any] {
            [
                .font: EditorStyle.sourceFont,
                .foregroundColor: EditorStyle.ink,
                .paragraphStyle: paragraphStyle,
                .baselineOffset: EditorStyle.sourceBaselineOffset,
            ]
        }

        static func attributes(
            for kind: SyntaxHighlight.Kind,
        ) -> [NSAttributedString.Key: Any] {
            switch kind {
            case .chord, .unknownChord:
                [.foregroundColor: EditorStyle.cueText, .font: EditorStyle.sourceChordFont]
            case .noChord:
                [.foregroundColor: EditorStyle.muted, .font: EditorStyle.sourceChordFont]
            case .commentDirective, .directive:
                [.foregroundColor: EditorStyle.muted]
            case .sectionMarker:
                [
                    .foregroundColor: EditorStyle.muted,
                    .font: NSFont.monospacedSystemFont(ofSize: 14, weight: .semibold),
                ]
            case .fileComment:
                [.foregroundColor: EditorStyle.lineNumber]
            }
        }

        /// Re-colours the paragraphs touching `range` from the current snapshot.
        func restyle(_ range: NSRange) {
            guard let storage = textView.textStorage, let host else { return }
            let text = textView.string as NSString
            guard range.location <= text.length else { return }
            let clamped = NSRange(
                location: range.location,
                length: min(range.length, text.length - range.location),
            )
            let paragraphs = text.paragraphRange(for: clamped)
            let snapshot = host.snapshot
            guard snapshot.text.utf16.count == text.length else { return }
            storage.beginEditing()
            storage.setAttributes(Self.baseAttributes, range: paragraphs)
            let span = paragraphs.location ..< NSMaxRange(paragraphs)
            for highlight in snapshot.highlights(in: span) {
                let run = NSIntersectionRange(
                    NSRange(location: highlight.range.lowerBound, length: highlight.range.count),
                    paragraphs,
                )
                if run.length > 0 {
                    storage.addAttributes(Self.attributes(for: highlight.kind), range: run)
                }
            }
            if diagnosticsText == textView.string {
                for diagnostic in diagnostics {
                    let marked = NSIntersectionRange(diagnosticRange(diagnostic), paragraphs)
                    guard marked.length > 0 else { continue }
                    let color = diagnostic.severity == .error
                        ? EditorStyle.errorUnderline
                        : EditorStyle.warningUnderline
                    storage.addAttributes([
                        .underlineStyle: NSUnderlineStyle.thick.union(.patternDot).rawValue,
                        .underlineColor: color,
                        .toolTip: diagnostic.message,
                    ], range: marked)
                }
            }
            storage.endEditing()
            textView.typingAttributes = Self.baseAttributes
        }

        /// A diagnostic's range; an empty one (a caret position) marks its whole line.
        func diagnosticRange(_ diagnostic: EditorDiagnostic) -> NSRange {
            let range = NSRange(
                location: diagnostic.range.lowerBound,
                length: diagnostic.range.count,
            )
            return range.length > 0 ? range : lineRange(for: diagnostic.range)
        }

        /// The line holding `range` without its line ending.
        func lineRange(for range: Range<Int>) -> NSRange {
            let text = textView.string as NSString
            let location = min(range.lowerBound, text.length)
            var line = text.lineRange(for: NSRange(location: location, length: 0))
            while line.length > 0,
                  let scalar = UnicodeScalar(text.character(at: NSMaxRange(line) - 1)),
                  CharacterSet.newlines.contains(scalar)
            {
                line.length -= 1
            }
            return line
        }
    }

    // MARK: - NSTextViewDelegate

    extension SourceEditorController: NSTextViewDelegate {
        func undoManager(for _: NSTextView) -> UndoManager? {
            undoManager
        }

        func textView(
            _: NSTextView,
            shouldChangeTextIn range: NSRange,
            replacementString: String?,
        ) -> Bool {
            if !isApplyingChange, interceptSlashTyping(in: range, replacement: replacementString) {
                return false
            }
            if !isApplyingChange {
                lastTypedText = replacementString
            }
            return true
        }

        func textDidChange(_: Notification) {
            let typed = isApplyingChange || undoManager.isUndoing || undoManager.isRedoing
                ? nil
                : lastTypedText
            lastTypedText = nil
            textView.updateLineStarts()
            textView.gutter.needsDisplay = true
            host?.sourceTextDidChange(textView.string)
            if let range = pendingEditedRange {
                pendingEditedRange = nil
                restyle(range)
            }
            if typed != nil || completion.isVisible {
                // After the keystroke: moving a window costs window-server round trips that
                // must not hold up the typed character.
                Task { @MainActor [weak self] in
                    self?.updateCompletion(typed: typed)
                }
            }
        }

        func textViewDidChangeSelection(_: Notification) {
            host?.sourceSelectionDidChange(textView.selectedRange())
            if completion.isVisible, completionContext() == nil {
                completion.hide()
            }
        }

        func textView(_: NSTextView, doCommandBy _: Selector) -> Bool {
            false
        }
    }

    // MARK: - Completion keys

    extension SourceEditorController: SourceKeyHandling {
        func handleCommand(_ selector: Selector) -> Bool {
            guard completion.isVisible else { return false }
            if completion.items.isEmpty {
                // A header-only hint: Esc closes it, every other key behaves as usual.
                guard selector == #selector(NSResponder.cancelOperation(_:)) else { return false }
                completion.hide()
                return true
            }
            switch selector {
            case #selector(NSResponder.moveDown(_:)):
                completion.moveSelection(by: 1)
            case #selector(NSResponder.moveUp(_:)):
                completion.moveSelection(by: -1)
            case #selector(NSResponder.moveRight(_:)) where completion.kind?.isList == false:
                completion.moveSelection(by: 1)
            case #selector(NSResponder.moveLeft(_:)) where completion.kind?.isList == false:
                completion.moveSelection(by: -1)
            case #selector(NSResponder.insertNewline(_:)), #selector(NSResponder.insertTab(_:)):
                acceptCompletion()
            case #selector(NSResponder.cancelOperation(_:)):
                completion.hide()
            default:
                return false
            }
            return true
        }
    }

    // MARK: - NSTextStorageDelegate

    extension SourceEditorController: NSTextStorageDelegate {
        nonisolated func textStorage(
            _: NSTextStorage,
            didProcessEditing editedMask: NSTextStorageEditActions,
            range editedRange: NSRange,
            changeInLength _: Int,
        ) {
            guard editedMask.contains(.editedCharacters) else { return }
            MainActor.assumeIsolated {
                if let pending = pendingEditedRange {
                    // Earlier pending ranges shift with later edits; a union over-covers,
                    // which only restyles a few more lines.
                    pendingEditedRange = NSUnionRange(pending, editedRange)
                } else {
                    pendingEditedRange = editedRange
                }
            }
        }
    }
#endif
