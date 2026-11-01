#if os(macOS)
    import AppKit
    import SwiftUI

    /// The keys the set composer handles itself (P8-5 section 4.3).
    enum ComposerCommand: Equatable {
        case accept
        case next
        case previous
        case tab
        case backtab
        case escape
    }

    /// The set composer's text field (P8-5 section 4.5): a borderless `NSTextField` with its
    /// own field editor, so turning off every text substitution and the editor's own undo
    /// never leaks into other fields of the window.
    ///
    /// Romanized Hindi rule: spell-check, grammar, autocorrect, text replacement, smart
    /// quotes and dashes, completion, inline predictions and Writing Tools are all off, so
    /// nothing ever "corrects" what was typed ("---" stays three hyphens). Arrange Sections'
    /// roadmap field (P8-3 section 6.5) uses it for the same reason (romanized part labels).
    struct ComposerTextField: NSViewRepresentable {
        let text: String
        var font: NSFont
        var identifier = AccessibilityID.setlistComposer
        /// Drawn while the field is empty (the composer draws its own instead).
        var placeholder: String?
        var accessibilityHint: String?
        /// Bumped to take keyboard focus (⌘L).
        var focusRequest: Int
        /// Bumped to select the whole text (the duplicate block keeps it, selected).
        var selectAllRequest: Int
        var accessibilityLabel: String
        var accessibilityValue: String
        var onChange: (String) -> Void
        var onFocusChange: (Bool) -> Void
        /// Returns whether the key was handled.
        var onCommand: (ComposerCommand) -> Bool
        /// Backspace, before the field editor deletes (the artist chip field selects and
        /// removes chips with it in an empty input); returns whether it was handled.
        var onDeleteBackward: (() -> Bool)?

        func makeCoordinator() -> Coordinator {
            Coordinator(self)
        }

        func makeNSView(context: Context) -> ComposerNSTextField {
            let field = ComposerNSTextField()
            let cell = ComposerTextFieldCell(textCell: "")
            // The cell's own flag decides the field editor's `allowsUndo` while editing.
            cell.allowsUndo = false
            field.cell = cell
            field.isBordered = false
            field.drawsBackground = false
            field.isEditable = true
            field.isSelectable = true
            field.focusRingType = .none
            field.lineBreakMode = .byClipping
            field.usesSingleLineMode = true
            field.cell?.isScrollable = true
            field.cell?.wraps = false
            field.font = font
            field.textColor = NSColor(Theme.color.ink)
            field.stringValue = text
            field.delegate = context.coordinator
            field.onFocusChange = { focused in context.coordinator.parent.onFocusChange(focused) }
            field.setAccessibilityIdentifier(identifier)
            field.setAccessibilityLabel(accessibilityLabel)
            field.placeholderString = placeholder
            field.setAccessibilityHelp(accessibilityHint)
            field.setContentHuggingPriority(.defaultLow, for: .horizontal)
            field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
            context.coordinator.focusRequest = focusRequest
            context.coordinator.selectAllRequest = selectAllRequest
            return field
        }

        func updateNSView(_ field: ComposerNSTextField, context: Context) {
            let coordinator = context.coordinator
            coordinator.parent = self
            if field.stringValue != text {
                field.stringValue = text
            }
            field.font = font
            field.isEnabled = context.environment.isEnabled
            field.setAccessibilityLabel(accessibilityLabel)
            field.setAccessibilityValueDescription(accessibilityValue)
            if coordinator.focusRequest != focusRequest {
                coordinator.focusRequest = focusRequest
                field.focus()
            }
            if coordinator.selectAllRequest != selectAllRequest {
                coordinator.selectAllRequest = selectAllRequest
                field.currentEditor()?.selectAll(nil)
            }
        }

        @MainActor
        final class Coordinator: NSObject, NSTextFieldDelegate {
            var parent: ComposerTextField
            var focusRequest = 0
            var selectAllRequest = 0

            init(_ parent: ComposerTextField) {
                self.parent = parent
            }

            func controlTextDidChange(_ notification: Notification) {
                guard let field = notification.object as? NSTextField else { return }
                parent.onChange(field.stringValue)
            }

            func controlTextDidBeginEditing(_ notification: Notification) {
                // The cell's own field editor is already configured; this keeps it so even
                // if AppKit handed over another one.
                if let editor = notification.userInfo?["NSFieldEditor"] as? NSTextView {
                    ComposerTextFieldCell.configure(editor)
                }
            }

            func control(
                _: NSControl,
                textView _: NSTextView,
                doCommandBy selector: Selector,
            ) -> Bool {
                if selector == #selector(NSResponder.deleteBackward(_:)) {
                    return parent.onDeleteBackward?() ?? false
                }
                guard let command = Self.command(for: selector) else { return false }
                return parent.onCommand(command)
            }

            /// The field editor's key commands the composer maps (section 8.3).
            static func command(for selector: Selector) -> ComposerCommand? {
                switch selector {
                case #selector(NSResponder.insertNewline(_:)): .accept
                case #selector(NSResponder.moveDown(_:)): .next
                case #selector(NSResponder.moveUp(_:)): .previous
                case #selector(NSResponder.insertTab(_:)): .tab
                case #selector(NSResponder.insertBacktab(_:)): .backtab
                case #selector(NSResponder.cancelOperation(_:)): .escape
                default: nil
                }
            }
        }
    }

    /// Reports focus in and out (the field editor stands in for the field while editing).
    final class ComposerNSTextField: NSTextField {
        var onFocusChange: ((Bool) -> Void)?

        override func becomeFirstResponder() -> Bool {
            let became = super.becomeFirstResponder()
            if became {
                onFocusChange?(true)
            }
            return became
        }

        override func textDidEndEditing(_ notification: Notification) {
            super.textDidEndEditing(notification)
            onFocusChange?(false)
        }

        /// A focus asked for before the field was in a window (a field that appears and is
        /// focused in the same update, as the heading's credit fields do).
        private var pendingFocus = false

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if pendingFocus, window != nil {
                pendingFocus = false
                DispatchQueue.main.async { [weak self] in self?.focus() }
            }
        }

        /// Takes keyboard focus with the caret at the end (the typed text stays).
        func focus() {
            guard let window else {
                pendingFocus = true
                return
            }
            if currentEditor() == nil {
                window.makeFirstResponder(self)
            }
            if let editor = currentEditor() {
                editor.selectedRange = NSRange(
                    location: (stringValue as NSString).length,
                    length: 0,
                )
            }
        }
    }

    /// The composer's field editor. It takes no drops, so a library song dropped on the
    /// row while the field is focused is appended to the set, not typed into the line.
    final class ComposerFieldEditor: NSTextView {
        override var acceptableDragTypes: [NSPasteboard.PasteboardType] {
            []
        }
    }

    /// Hands the composer its own field editor (`NSCell.fieldEditor(for:)`), configured
    /// once, instead of the window's shared one.
    final class ComposerTextFieldCell: NSTextFieldCell {
        private lazy var editor: NSTextView = {
            let editor = ComposerFieldEditor()
            editor.isFieldEditor = true
            Self.configure(editor)
            return editor
        }()

        override func fieldEditor(for _: NSView) -> NSTextView? {
            editor
        }

        /// AppKit resets some of the editor's flags (completion, undo) each time editing
        /// begins; set them again after it has.
        override func setUpFieldEditorAttributes(_ textObj: NSText) -> NSText {
            let text = super.setUpFieldEditorAttributes(textObj)
            if let editor = text as? NSTextView {
                Self.configure(editor)
            }
            return text
        }

        /// Section 4.5: every substitution, check and suggestion off, and no text undo (the
        /// window's undo stack belongs to the builder).
        static func configure(_ editor: NSTextView) {
            editor.isContinuousSpellCheckingEnabled = false
            editor.isGrammarCheckingEnabled = false
            editor.isAutomaticSpellingCorrectionEnabled = false
            editor.isAutomaticTextReplacementEnabled = false
            editor.isAutomaticQuoteSubstitutionEnabled = false
            editor.isAutomaticDashSubstitutionEnabled = false
            editor.isAutomaticTextCompletionEnabled = false
            editor.isAutomaticLinkDetectionEnabled = false
            editor.isAutomaticDataDetectionEnabled = false
            editor.smartInsertDeleteEnabled = false
            editor.enabledTextCheckingTypes = 0
            editor.inlinePredictionType = .no
            editor.writingToolsBehavior = .none
            editor.allowsUndo = false
        }

        /// The section 4.5 flags as one string, every one "off" (tests read it).
        static func report(_ editor: NSTextView) -> String {
            let flags: [(String, Bool)] = [
                ("continuousSpelling", editor.isContinuousSpellCheckingEnabled),
                ("grammar", editor.isGrammarCheckingEnabled),
                ("spelling", editor.isAutomaticSpellingCorrectionEnabled),
                ("replacement", editor.isAutomaticTextReplacementEnabled),
                ("quotes", editor.isAutomaticQuoteSubstitutionEnabled),
                ("dashes", editor.isAutomaticDashSubstitutionEnabled),
                ("completion", editor.isAutomaticTextCompletionEnabled),
                ("undo", editor.allowsUndo),
            ]
            return flags.map { "\($0.0)=\($0.1 ? "on" : "off")" }.joined(separator: " ")
        }
    }
#endif
