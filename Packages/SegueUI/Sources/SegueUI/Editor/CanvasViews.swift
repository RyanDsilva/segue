#if os(macOS)
    import AppKit
    import QuartzCore

    /// Mouse and key handling the canvas controller does before the text view.
    @MainActor
    protocol CanvasGestureHandling: AnyObject {
        /// Returns true when the event was consumed (a chord gesture).
        func canvasMouseDown(_ event: NSEvent) -> Bool
        func canvasMouseDragged(_ event: NSEvent) -> Bool
        func canvasMouseUp(_ event: NSEvent) -> Bool
        func canvasMouseMoved(_ event: NSEvent)
        func canvasMouseExited()
        func canvasKeyDown(_ event: NSEvent) -> Bool
        func canvasDidResize()
        #if DEBUG
            func canvasKeystrokeTimed(_ seconds: TimeInterval, isShortcut: Bool)
        #endif
    }

    /// The visual canvas text (TextKit 2): section labels and lyric lines, with every
    /// automatic text transformation off like the source view. Chords are not text; the
    /// overlay draws them as pills over the chord lane of each lyric row.
    final class CanvasTextView: NSTextView {
        weak var gestures: (any CanvasGestureHandling)?
        private var trackingArea: NSTrackingArea?

        override func mouseDown(with event: NSEvent) {
            if gestures?.canvasMouseDown(event) == true {
                return
            }
            super.mouseDown(with: event)
        }

        override func mouseDragged(with event: NSEvent) {
            if gestures?.canvasMouseDragged(event) == true {
                return
            }
            super.mouseDragged(with: event)
        }

        override func mouseUp(with event: NSEvent) {
            if gestures?.canvasMouseUp(event) == true {
                return
            }
            super.mouseUp(with: event)
        }

        override func mouseMoved(with event: NSEvent) {
            super.mouseMoved(with: event)
            gestures?.canvasMouseMoved(event)
        }

        override func mouseExited(with event: NSEvent) {
            super.mouseExited(with: event)
            gestures?.canvasMouseExited()
        }

        override func keyDown(with event: NSEvent) {
            #if DEBUG
                let start = CACurrentMediaTime()
            #endif
            if gestures?.canvasKeyDown(event) != true {
                super.keyDown(with: event)
            }
            textLayoutManager?.textViewportLayoutController.layoutViewport()
            // Timing is Debug only (the E2E typing-latency instrumentation).
            #if DEBUG
                gestures?.canvasKeystrokeTimed(
                    CACurrentMediaTime() - start,
                    isShortcut: event.modifierFlags.contains(.command),
                )
            #endif
        }

        override func updateTrackingAreas() {
            super.updateTrackingAreas()
            if let trackingArea {
                removeTrackingArea(trackingArea)
            }
            let area = NSTrackingArea(
                rect: bounds,
                options: [.mouseMoved, .mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
                owner: self,
            )
            addTrackingArea(area)
            trackingArea = area
        }

        /// TextKit lays out the viewport here, after an edit: the pills follow the new
        /// glyph positions.
        override func layout() {
            super.layout()
            gestures?.canvasDidResize()
        }

        override func setFrameSize(_ newSize: NSSize) {
            let widthChanged = newSize.width != frame.width
            super.setFrameSize(newSize)
            if widthChanged {
                // Mockup padding is 120 at 1440; narrower windows keep at least 40.
                let inset = min(max((newSize.width - 860) / 2, 40), 120)
                if abs(textContainerInset.width - inset) > 0.5 {
                    textContainerInset = NSSize(width: inset, height: 32)
                }
            }
            gestures?.canvasDidResize()
        }
    }

    /// Draws chord pills, section rules and drag/hover ghosts over the canvas, and exposes
    /// pills and chord slots to accessibility. Sits above the scroll view's clip view and
    /// passes every click through to the text view.
    final class CanvasOverlayView: NSView {
        weak var painter: (any CanvasOverlayPainting)?

        override var isFlipped: Bool {
            true
        }

        override func hitTest(_: NSPoint) -> NSView? {
            nil
        }

        override func draw(_ dirtyRect: NSRect) {
            painter?.drawOverlay(in: dirtyRect, of: self)
        }

        override func isAccessibilityElement() -> Bool {
            true
        }

        override func accessibilityRole() -> NSAccessibility.Role? {
            .group
        }

        /// Retained until the next query: accessibility clients read the elements' attributes
        /// after `accessibilityChildren()` returns.
        private var accessibilityElements: [Any] = []

        override func accessibilityChildren() -> [Any]? {
            accessibilityElements = painter?.overlayAccessibilityElements(for: self) ?? []
            return accessibilityElements
        }

        override func accessibilityChildrenInNavigationOrder()
            -> [any NSAccessibilityElementProtocol]?
        {
            accessibilityChildren()?.compactMap { $0 as? any NSAccessibilityElementProtocol }
        }
    }

    @MainActor
    protocol CanvasOverlayPainting: AnyObject {
        func drawOverlay(in dirtyRect: NSRect, of overlay: CanvasOverlayView)
        func overlayAccessibilityElements(for overlay: CanvasOverlayView) -> [Any]
    }

    /// The canvas container: scroll view with the text view, and the overlay on top.
    final class CanvasContainerView: NSView {
        let scrollView = NSScrollView()
        let overlay = CanvasOverlayView()

        override init(frame frameRect: NSRect) {
            super.init(frame: frameRect)
            scrollView.autoresizingMask = [.width, .height]
            scrollView.frame = bounds
            addSubview(scrollView)
            overlay.autoresizingMask = [.width, .height]
            overlay.frame = bounds
            addSubview(overlay)
        }

        @available(*, unavailable)
        required init?(coder _: NSCoder) {
            nil
        }
    }
#endif
