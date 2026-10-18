#if os(macOS)
    import AppKit
    import Editing

    /// The visual canvas (layout b): lyrics with chord pills over syllables, editable
    /// section labels and lyrics, read-only tab/grid.
    ///
    /// The canvas text is a projection of the `RenderModel`, never the source of truth: every
    /// edit is turned into an `EditOperation`, applied to the ChordPro source through the
    /// source text view (one undo group on the shared stack), and the canvas re-projects the
    /// changed paragraphs.
    @MainActor
    final class VisualEditorController: NSObject {
        let container = CanvasContainerView()
        let textView: CanvasTextView
        unowned let model: SongEditorViewModel

        /// The projection on screen.
        private(set) var projection = CanvasProjection(paragraphs: [])
        /// Where to put the caret after the next attach or reload (from a mode switch).
        var pendingCaret: LyricPosition?
        /// Caret to restore after the next reload: paragraph index and UTF-16 offset in it.
        var pendingParagraphCaret: (paragraph: Int, offset: Int)?
        var pendingFocus = false

        /// The selected pill: its line, lyric offset and source text.
        var selectedChord: ChordSelection?
        var drag: ChordDrag?
        var hover: LaneTarget?
        var popover: NSPopover?
        /// The slot the open popover adds a chord to (drawn as a ghost).
        var popoverTarget: LaneTarget?

        init(model: SongEditorViewModel) {
            self.model = model
            textView = CanvasTextView(usingTextLayoutManager: true)
            super.init()
            configure()
        }

        private func configure() {
            let scrollView = container.scrollView
            EditorScrollView.configure(scrollView)
            scrollView.contentView.postsBoundsChangedNotifications = true

            textView.minSize = .zero
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
            textView.textContainerInset = NSSize(width: 40, height: 32)
            textView.insertionPointColor = EditorStyle.ink
            textView.linkTextAttributes = [
                .foregroundColor: EditorStyle.cueText,
                .cursor: NSCursor.pointingHand,
            ]
            textView.setAccessibilityIdentifier(AccessibilityID.editorVisual)
            textView.setAccessibilityLabel("Lyrics")
            // Exposed explicitly: without any accessibility help set, AppKit no longer
            // surfaces the text view as its own element to XCUITest.
            textView.setAccessibilityElement(true)
            textView.delegate = self
            textView.gestures = self
            scrollView.documentView = textView

            container.overlay.painter = self
            container.overlay.setAccessibilityIdentifier(AccessibilityID.editorVisualChords)
            container.overlay.setAccessibilityLabel("Chords")
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(clipViewDidScroll),
                name: NSView.boundsDidChangeNotification,
                object: scrollView.contentView,
            )
        }

        @objc private func clipViewDidScroll(_: Notification) {
            container.overlay.needsDisplay = true
        }

        func redrawOverlay() {
            container.overlay.needsDisplay = true
        }

        func focus() {
            textView.window?.makeFirstResponder(textView)
        }

        // MARK: Reload

        /// Re-projects the canvas model, replacing only the paragraphs that changed.
        func reload() {
            guard let renderModel = model.canvasModel else { return }
            let caretBefore = currentParagraphCaret()
            let next = CanvasProjection(model: renderModel)
            applyDiff(from: projection, to: next)
            projection = next
            restoreCaret(fallback: caretBefore)
            resolveSelection()
            redrawOverlay()
        }

        private func applyDiff(from old: CanvasProjection, to new: CanvasProjection) {
            guard let storage = textView.textStorage else { return }
            let oldParagraphs = old.paragraphs
            let newParagraphs = new.paragraphs
            if oldParagraphs.isEmpty || storage.length != old.length {
                storage.setAttributedString(Self.attributedText(newParagraphs))
                return
            }
            let (prefix, suffix) = Self.commonEnds(oldParagraphs, newParagraphs)
            if prefix == oldParagraphs.count, prefix == newParagraphs.count {
                return
            }
            let middle = Array(newParagraphs[prefix ..< newParagraphs.count - suffix])
            let replaced: NSRange
            let replacement = NSMutableAttributedString()
            if suffix > 0 {
                // Each middle paragraph keeps its own separator.
                let end = old.starts[oldParagraphs.count - suffix]
                replaced = NSRange(location: old.starts[prefix], length: end - old.starts[prefix])
                for paragraph in middle {
                    replacement.append(CanvasTypesetting.attributed(paragraph, separator: "\n"))
                }
            } else if prefix > 0 {
                // The tail changed: take over the separator after the last kept paragraph.
                let start = old.starts[prefix] - 1
                replaced = NSRange(location: start, length: old.length - start)
                for paragraph in middle {
                    replacement.append(NSAttributedString(string: "\n"))
                    replacement.append(CanvasTypesetting.attributed(paragraph, separator: ""))
                }
                if !middle.isEmpty {
                    // The separator takes the paragraph style of the paragraph it ends.
                    restyleSeparator(
                        before: prefix,
                        in: replacement,
                        kept: newParagraphs[prefix - 1],
                    )
                }
            } else {
                storage.setAttributedString(Self.attributedText(newParagraphs))
                return
            }
            storage.beginEditing()
            storage.replaceCharacters(in: replaced, with: replacement)
            storage.endEditing()
        }

        /// How many paragraphs the two lists share at the start, and then at the end.
        static func commonEnds(
            _ old: [CanvasParagraph],
            _ new: [CanvasParagraph],
        ) -> (prefix: Int, suffix: Int) {
            var prefix = 0
            while prefix < old.count, prefix < new.count, old[prefix] == new[prefix] {
                prefix += 1
            }
            var suffix = 0
            while suffix < old.count - prefix, suffix < new.count - prefix,
                  old[old.count - 1 - suffix] == new[new.count - 1 - suffix]
            {
                suffix += 1
            }
            return (prefix, suffix)
        }

        private func restyleSeparator(
            before _: Int,
            in replacement: NSMutableAttributedString,
            kept: CanvasParagraph,
        ) {
            let styled = CanvasTypesetting.attributed(kept, separator: "\n")
            let attributes = styled.attributes(at: styled.length - 1, effectiveRange: nil)
            replacement.setAttributes(attributes, range: NSRange(location: 0, length: 1))
        }

        static func attributedText(_ paragraphs: [CanvasParagraph]) -> NSAttributedString {
            let text = NSMutableAttributedString()
            for (index, paragraph) in paragraphs.enumerated() {
                let separator = index == paragraphs.count - 1 ? "" : "\n"
                text.append(CanvasTypesetting.attributed(paragraph, separator: separator))
            }
            return text
        }

        // MARK: Caret

        private func currentParagraphCaret() -> (paragraph: Int, offset: Int)? {
            guard !projection.paragraphs.isEmpty else { return nil }
            let location = textView.selectedRange().location
            let index = projection.paragraphIndex(at: location)
            return (index, location - projection.starts[index])
        }

        /// Puts the caret where the last action asked, else where it was.
        private func restoreCaret(fallback: (paragraph: Int, offset: Int)?) {
            if let position = pendingCaret {
                pendingCaret = nil
                placeCaret(at: position)
                return
            }
            let undoing = model.isUndoingOrRedoing
            if undoing, let offset = model.sourceSelection?.location,
               let position = model.snapshot.lyricPosition(atSourceOffset: offset)
            {
                placeCaret(at: position)
                return
            }
            guard let target = pendingParagraphCaret ?? fallback,
                  !projection.paragraphs.isEmpty
            else { return }
            pendingParagraphCaret = nil
            let index = min(target.paragraph, projection.paragraphs.count - 1)
            let range = projection.range(of: index)
            let offset = min(max(target.offset, 0), range.length)
            textView.setSelectedRange(NSRange(location: range.location + offset, length: 0))
        }

        /// Places the caret at a lyric position (cursor mapping from text mode).
        func placeCaret(at position: LyricPosition) {
            guard let index = projection.lyricParagraphs[position.line],
                  let line = projection.paragraphs[index].lyricLine
            else { return }
            let offset = line.utf16Offset(ofLyricOffset: position.offset)
            let range = NSRange(location: projection.starts[index] + offset, length: 0)
            textView.setSelectedRange(range)
            textView.scrollRangeToVisible(range)
        }

        /// Visual -> text cursor mapping: the source offset of the canvas caret.
        func caretSourceOffset() -> Int? {
            guard !projection.paragraphs.isEmpty else { return nil }
            let location = textView.selectedRange().location
            let index = projection.paragraphIndex(at: location)
            let paragraph = projection.paragraphs[index]
            let offset = location - projection.starts[index]
            let snapshot = model.snapshot
            switch paragraph.role {
            case let .lyrics(line):
                let character = line.lyricOffset(atUTF16: offset)
                return snapshot.sourceOffset(of: LyricPosition(line: line.path, offset: character))
            case let .label(path?, _, _), let .textModeLink(path?):
                return snapshot.sourceRange(of: path)?.lowerBound
            case let .comment(path), let .stanzaBreak(path), let .verbatim(path):
                return snapshot.sourceRange(of: path)?.lowerBound
            case .emptyNote, .label, .repeatNote, .textModeLink:
                return nil
            }
        }

        /// Called once the canvas is in a window: applies a pending mode-switch caret.
        func didAttach() {
            if let position = pendingCaret {
                pendingCaret = nil
                placeCaret(at: position)
            }
            if pendingFocus {
                pendingFocus = false
                focus()
            }
            redrawOverlay()
        }
    }

    // MARK: - Text edits -> tree operations

    extension VisualEditorController: NSTextViewDelegate {
        func undoManager(for _: NSTextView) -> UndoManager? {
            model.sourceEditor.undoManager
        }

        func textView(
            _: NSTextView,
            shouldChangeTextIn range: NSRange,
            replacementString: String?,
        ) -> Bool {
            if let replacementString {
                handleEdit(range, replacement: replacementString)
            }
            // The canvas never edits itself: the source changes and the canvas re-projects.
            return false
        }

        func textViewDidChangeSelection(_: Notification) {
            if let offset = caretSourceOffset() {
                model.sourceCaretDidMove(to: offset)
            }
        }

        func textView(_: NSTextView, clickedOnLink link: Any, at index: Int) -> Bool {
            guard (link as? URL) == CanvasLink.textMode else { return false }
            textView.setSelectedRange(NSRange(location: index, length: 0))
            model.setEditorMode(.text)
            return true
        }

        /// Turns a typed change into a tree operation (or rejects it).
        private func handleEdit(_ range: NSRange, replacement: String) {
            guard !projection.paragraphs.isEmpty else { return }
            let index = projection.paragraphIndex(at: range.location)
            let paragraphRange = projection.range(of: index)
            let paragraph = projection.paragraphs[index]
            let local = range.location - paragraphRange.location
            if NSMaxRange(range) <= NSMaxRange(paragraphRange) {
                editInside(
                    paragraph,
                    at: index,
                    local: NSRange(location: local, length: range.length),
                    replacement: replacement,
                )
            } else if replacement.isEmpty, range.length == 1, local == paragraphRange.length {
                // Forward delete at the end of a line: join the next line onto this one.
                joinParagraph(index + 1)
            } else {
                NSSound.beep()
            }
        }

        private func editInside(
            _ paragraph: CanvasParagraph,
            at index: Int,
            local: NSRange,
            replacement: String,
        ) {
            let isNewline = replacement == "\n" || replacement == "\r"
            switch paragraph.role {
            case let .lyrics(line):
                let from = line.lyricOffset(atUTF16: local.location)
                let to = line.lyricOffset(atUTF16: NSMaxRange(local))
                if isNewline, local.length == 0 {
                    pendingParagraphCaret = (index + 1, 0)
                    model.perform(.splitLine(at: LyricPosition(line: line.path, offset: from)))
                    return
                }
                guard !replacement.contains(where: \.isNewline) else {
                    NSSound.beep()
                    return
                }
                pendingParagraphCaret = (index, local.location + replacement.utf16.count)
                model.perform(.editLyrics(line.path, range: from ..< to, replacement: replacement))
            case let .label(path?, _, true):
                guard !replacement.contains(where: \.isNewline) else {
                    NSSound.beep()
                    return
                }
                let label = (paragraph.text as NSString)
                    .replacingCharacters(in: local, with: replacement)
                let isBlank = label.trimmingCharacters(in: .whitespaces).isEmpty
                pendingParagraphCaret = (index, local.location + replacement.utf16.count)
                model.perform(.setSectionLabel(path, label: isBlank ? nil : label))
            default:
                if local.location == 0, local.length == 0, replacement.isEmpty {
                    return
                }
                NSSound.beep()
            }
        }

        /// Backspace at the start of a lyric line joins it onto the previous lyric line.
        func joinParagraph(_ index: Int) {
            guard projection.paragraphs.indices.contains(index), index > 0,
                  let line = projection.paragraphs[index].lyricLine,
                  let previous = projection.paragraphs[index - 1].lyricLine
            else {
                NSSound.beep()
                return
            }
            pendingParagraphCaret = (index - 1, previous.lyrics.utf16.count)
            model.perform(.joinWithPrevious(line.path))
        }
    }
#endif
