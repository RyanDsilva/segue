#if os(macOS)
    import AppKit
    import SwiftUI

    /// A native `NSSearchField` bound to `text`, for placing search inside a specific column
    /// or sheet. (`.searchable` on macOS always lands at the trailing end of the window
    /// toolbar, which in a split view is the detail column, not the list it filters.)
    struct SearchField: NSViewRepresentable {
        @Binding var text: String
        var prompt: String
        var accessibilityIdentifier: String
        /// Return or ↓ in the field (the builder's Pick moves focus to the first result);
        /// nil leaves both keys to the field.
        var onSubmit: (() -> Void)?

        func makeCoordinator() -> Coordinator {
            Coordinator(text: $text, onSubmit: onSubmit)
        }

        func makeNSView(context: Context) -> NSSearchField {
            let field = NSSearchField()
            field.placeholderString = prompt
            field.stringValue = text
            field.delegate = context.coordinator
            field.sendsSearchStringImmediately = true
            field.sendsWholeSearchString = false
            field.focusRingType = .default
            field.controlSize = .regular
            field.isAutomaticTextCompletionEnabled = false
            field.setAccessibilityIdentifier(accessibilityIdentifier)
            field.setContentHuggingPriority(.defaultLow, for: .horizontal)
            return field
        }

        func updateNSView(_ field: NSSearchField, context: Context) {
            context.coordinator.text = $text
            context.coordinator.onSubmit = onSubmit
            if field.stringValue != text {
                field.stringValue = text
            }
        }

        @MainActor
        final class Coordinator: NSObject, NSSearchFieldDelegate {
            var text: Binding<String>
            var onSubmit: (() -> Void)?

            init(text: Binding<String>, onSubmit: (() -> Void)?) {
                self.text = text
                self.onSubmit = onSubmit
            }

            func control(
                _: NSControl,
                textView _: NSTextView,
                doCommandBy selector: Selector,
            ) -> Bool {
                guard let onSubmit,
                      selector == #selector(NSResponder.insertNewline(_:))
                      || selector == #selector(NSResponder.moveDown(_:))
                else { return false }
                onSubmit()
                return true
            }

            func controlTextDidChange(_ notification: Notification) {
                guard let field = notification.object as? NSSearchField else { return }
                text.wrappedValue = field.stringValue
            }

            func searchFieldDidEndSearching(_ sender: NSSearchField) {
                text.wrappedValue = sender.stringValue
            }
        }
    }
#endif
