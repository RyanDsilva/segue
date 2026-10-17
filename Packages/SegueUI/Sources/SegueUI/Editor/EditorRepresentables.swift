#if os(macOS)
    import AppKit
    import SwiftUI

    /// Hosts the source text view. The controller owns the view (it is the undoable store
    /// of the song), so switching modes detaches and re-attaches it rather than rebuilding.
    struct SourceEditorRepresentable: NSViewRepresentable {
        let controller: SourceEditorController

        func makeNSView(context _: Context) -> NSScrollView {
            controller.scrollView.removeFromSuperview()
            return controller.scrollView
        }

        func updateNSView(_: NSScrollView, context _: Context) {
            guard controller.pendingFocus else { return }
            Task { @MainActor in
                controller.pendingFocus = false
                controller.focus()
                controller.textView.scrollRangeToVisible(controller.selectedRange)
            }
        }
    }

    /// Hosts the visual canvas (text view + chord overlay).
    struct VisualEditorRepresentable: NSViewRepresentable {
        let controller: VisualEditorController

        func makeNSView(context _: Context) -> CanvasContainerView {
            controller.container.removeFromSuperview()
            return controller.container
        }

        func updateNSView(_: CanvasContainerView, context _: Context) {
            Task { @MainActor in
                controller.didAttach()
            }
        }
    }
#endif
