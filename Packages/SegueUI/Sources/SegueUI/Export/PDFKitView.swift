#if os(macOS)
    import AppKit
    import PDFKit
    import SwiftUI

    /// The preview's pages (spec 6.2): a `PDFView`, continuous, scaled to fit, with page
    /// shadows over the `surfaceAlt` ground. Reports the page in view.
    struct PDFKitView: NSViewRepresentable {
        let document: PDFDocument?
        @Binding var currentPage: Int
        var handle: PDFViewHandle?

        func makeCoordinator() -> Coordinator {
            Coordinator(currentPage: $currentPage)
        }

        func makeNSView(context: Context) -> PDFView {
            let view = PreviewPDFView()
            view.displayMode = .singlePageContinuous
            view.displayDirection = .vertical
            view.autoScales = false
            view.displaysPageBreaks = true
            view.pageShadowsEnabled = true
            view.pageBreakMargins = NSEdgeInsets(top: 12, left: 12, bottom: 12, right: 12)
            view.backgroundColor = NSColor(Theme.color.surfaceAlt)
            view.setAccessibilityIdentifier(AccessibilityID.pdfView)
            context.coordinator.observe(view)
            view.document = document
            handle?.view = view
            return view
        }

        func updateNSView(_ view: PDFView, context: Context) {
            context.coordinator.currentPage = $currentPage
            view.backgroundColor = NSColor(Theme.color.surfaceAlt)
            guard view.document !== document else { return }
            // A re-render keeps the reader on the page they were reading.
            let page = currentPage
            view.document = document
            (view as? PreviewPDFView)?.fitPages()
            if let document, let target = document.page(at: min(page, document.pageCount - 1)) {
                view.go(to: target)
            }
        }

        static func dismantleNSView(_: PDFView, coordinator: Coordinator) {
            coordinator.stop()
        }

        /// Pages at actual size (a page as wide as the sheet's mockup), smaller only when the
        /// pane is narrower, until the reader zooms (spec 6.2, R187 direction A).
        final class PreviewPDFView: PDFView {
            var userZoomed = false

            override func layout() {
                super.layout()
                if !userZoomed {
                    fitPages()
                }
            }

            func fitPages() {
                guard let page = document?.page(at: 0) else { return }
                let width = page.bounds(for: .mediaBox).width
                let room = bounds.width - 2 * 24
                guard width > 0, room > 0 else { return }
                let scale = min(1, room / width)
                if abs(scaleFactor - scale) > 0.001 {
                    scaleFactor = scale
                }
            }
        }

        @MainActor
        final class Coordinator {
            var currentPage: Binding<Int>
            private var observer: (any NSObjectProtocol)?

            init(currentPage: Binding<Int>) {
                self.currentPage = currentPage
            }

            func observe(_ view: PDFView) {
                observer = NotificationCenter.default.addObserver(
                    forName: .PDFViewPageChanged,
                    object: view,
                    queue: .main,
                ) { [weak self, weak view] _ in
                    MainActor.assumeIsolated {
                        guard let view, let page = view.currentPage,
                              let index = view.document?.index(for: page)
                        else { return }
                        if self?.currentPage.wrappedValue != index {
                            self?.currentPage.wrappedValue = index
                        }
                    }
                }
            }

            func stop() {
                if let observer {
                    NotificationCenter.default.removeObserver(observer)
                }
                observer = nil
            }
        }
    }
#endif
