#if os(macOS)
    import AppKit
    import SwiftUI

    /// A multi-line text field with spell checking, grammar checking, autocorrect and smart
    /// substitutions all off: descriptions are often romanized Hindi, which must never be
    /// "corrected" (docs/decisions.md, Language). SwiftUI's `TextEditor` cannot turn
    /// spelling off on macOS.
    struct PlainTextEditor: NSViewRepresentable {
        @Binding var text: String
        var accessibilityIdentifier: String
        var accessibilityLabel: String

        func makeNSView(context: Context) -> NSScrollView {
            let scroll = NSTextView.scrollableTextView()
            scroll.drawsBackground = false
            scroll.borderType = .noBorder
            scroll.hasVerticalScroller = true
            scroll.autohidesScrollers = true
            guard let view = scroll.documentView as? NSTextView else { return scroll }
            view.delegate = context.coordinator
            view.isRichText = false
            view.importsGraphics = false
            view.allowsUndo = true
            view.isContinuousSpellCheckingEnabled = false
            view.isGrammarCheckingEnabled = false
            view.isAutomaticSpellingCorrectionEnabled = false
            view.isAutomaticTextReplacementEnabled = false
            view.isAutomaticQuoteSubstitutionEnabled = false
            view.isAutomaticDashSubstitutionEnabled = false
            view.isAutomaticTextCompletionEnabled = false
            view.isAutomaticLinkDetectionEnabled = false
            view.isAutomaticDataDetectionEnabled = false
            view.smartInsertDeleteEnabled = false
            view.font = .systemFont(ofSize: NSFont.systemFontSize)
            view.textColor = .labelColor
            view.drawsBackground = false
            view.textContainerInset = NSSize(width: 4, height: 6)
            view.string = text
            view.setAccessibilityIdentifier(accessibilityIdentifier)
            view.setAccessibilityLabel(accessibilityLabel)
            return scroll
        }

        func updateNSView(_ scroll: NSScrollView, context: Context) {
            context.coordinator.text = $text
            guard let view = scroll.documentView as? NSTextView, view.string != text else {
                return
            }
            view.string = text
        }

        func makeCoordinator() -> Coordinator {
            Coordinator(text: $text)
        }

        @MainActor
        final class Coordinator: NSObject, NSTextViewDelegate {
            var text: Binding<String>

            init(text: Binding<String>) {
                self.text = text
            }

            func textDidChange(_ notification: Notification) {
                guard let view = notification.object as? NSTextView else { return }
                text.wrappedValue = view.string
            }
        }
    }
#endif
