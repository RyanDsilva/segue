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

        func makeCoordinator() -> Coordinator {
            Coordinator(text: $text)
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
            if field.stringValue != text {
                field.stringValue = text
            }
        }

        @MainActor
        final class Coordinator: NSObject, NSSearchFieldDelegate {
            var text: Binding<String>

            init(text: Binding<String>) {
                self.text = text
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
