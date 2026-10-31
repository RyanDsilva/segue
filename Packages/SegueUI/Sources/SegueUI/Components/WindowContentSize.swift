#if os(macOS)
    import AppKit
    import SwiftUI

    extension View {
        /// Keeps `size` at the content layout size of the window showing this view (below
        /// its toolbar), updated as the window resizes; nil until the view is in a window. A
        /// sheet sizes itself to fit the window it opens over from this.
        func windowContentSize(_ size: Binding<CGSize?>) -> some View {
            background(WindowContentSizeReader(size: size))
        }
    }

    private struct WindowContentSizeReader: NSViewRepresentable {
        @Binding var size: CGSize?

        func makeNSView(context _: Context) -> ReaderView {
            let view = ReaderView()
            view.onChange = { size = $0 }
            return view
        }

        func updateNSView(_ view: ReaderView, context _: Context) {
            view.onChange = { size = $0 }
        }

        final class ReaderView: NSView {
            var onChange: ((CGSize) -> Void)?
            private var observer: (any NSObjectProtocol)?

            override func viewDidMoveToWindow() {
                super.viewDidMoveToWindow()
                if let observer {
                    NotificationCenter.default.removeObserver(observer)
                    self.observer = nil
                }
                guard let window else { return }
                report(window)
                observer = NotificationCenter.default.addObserver(
                    forName: NSWindow.didResizeNotification,
                    object: window,
                    queue: .main,
                ) { [weak self] notification in
                    guard let window = notification.object as? NSWindow else { return }
                    MainActor.assumeIsolated { self?.report(window) }
                }
            }

            /// After the current view update: a size set while SwiftUI updates is dropped.
            private func report(_ window: NSWindow) {
                let size = window.contentLayoutRect.size
                Task { @MainActor [weak self] in self?.onChange?(size) }
            }
        }
    }
#endif
