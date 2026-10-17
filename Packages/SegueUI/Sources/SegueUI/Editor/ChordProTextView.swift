#if os(macOS)
    import AppKit
    import SwiftUI

    /// A plain monospaced text editor for raw ChordPro.
    ///
    /// Wraps `NSTextView` because SwiftUI's `TextEditor` cannot turn off spell-checking and
    /// smart quote/dash substitution, and lyrics (often romanized Hindi) must be kept exactly
    /// as typed (decisions.md, Language: "Editor input").
    struct ChordProTextView: NSViewRepresentable {
        @Binding var text: String
        var accessibilityIdentifier: String
        var accessibilityLabel: String

        func makeCoordinator() -> Coordinator {
            Coordinator(text: $text)
        }

        func makeNSView(context: Context) -> NSScrollView {
            let scrollView = NSTextView.scrollableTextView()
            scrollView.hasVerticalScroller = true
            scrollView.autohidesScrollers = true
            scrollView.drawsBackground = false
            scrollView.borderType = .noBorder

            guard let textView = scrollView.documentView as? NSTextView else { return scrollView }
            Self.configure(textView)
            textView.delegate = context.coordinator
            textView.string = text
            textView.setAccessibilityIdentifier(accessibilityIdentifier)
            textView.setAccessibilityLabel(accessibilityLabel)
            return scrollView
        }

        func updateNSView(_ scrollView: NSScrollView, context: Context) {
            context.coordinator.text = $text
            guard let textView = scrollView.documentView as? NSTextView else { return }
            if textView.string != text {
                textView.string = text
            }
        }

        /// Every automatic text transformation off: what is typed is what is saved.
        private static func configure(_ textView: NSTextView) {
            textView.isRichText = false
            textView.importsGraphics = false
            textView.allowsUndo = true
            textView.usesFindBar = true
            textView.isIncrementalSearchingEnabled = true
            textView.isAutomaticQuoteSubstitutionEnabled = false
            textView.isAutomaticDashSubstitutionEnabled = false
            textView.isAutomaticTextReplacementEnabled = false
            textView.isAutomaticSpellingCorrectionEnabled = false
            textView.isContinuousSpellCheckingEnabled = false
            textView.isGrammarCheckingEnabled = false
            textView.isAutomaticTextCompletionEnabled = false
            textView.isAutomaticLinkDetectionEnabled = false
            textView.isAutomaticDataDetectionEnabled = false
            textView.smartInsertDeleteEnabled = false
            textView.font = .monospacedSystemFont(ofSize: 13, weight: .regular)
            textView.textColor = .textColor
            textView.drawsBackground = false
            textView.textContainerInset = NSSize(width: 12, height: 12)
        }

        @MainActor
        final class Coordinator: NSObject, NSTextViewDelegate {
            var text: Binding<String>

            init(text: Binding<String>) {
                self.text = text
            }

            func textDidChange(_ notification: Notification) {
                guard let textView = notification.object as? NSTextView else { return }
                text.wrappedValue = textView.string
            }
        }
    }
#endif
