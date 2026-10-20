import AppKit
import SegueUI
import Support
import SwiftUI

#if DEBUG
    /// `-SegueWindowFrame` (the capture layer, WS5 8.2 / WS6 5.3): moves the hosting window to
    /// `frame` once, when the view joins it. The frame is in points with a top-left origin at
    /// the main screen's visible area (below the menu bar, beside the Dock), so a Dock on
    /// either side never covers the window.
    struct WindowFrameApplier: NSViewRepresentable {
        let frame: CGRect

        func makeNSView(context _: Context) -> ApplierView {
            ApplierView(windowFrame: frame)
        }

        func updateNSView(_: ApplierView, context _: Context) {}

        final class ApplierView: NSView {
            private let target: CGRect
            private var applied = false

            init(windowFrame target: CGRect) {
                self.target = target
                super.init(frame: .zero)
            }

            @available(*, unavailable)
            required init?(coder _: NSCoder) {
                nil
            }

            override func viewDidMoveToWindow() {
                super.viewDidMoveToWindow()
                guard !applied, let window else { return }
                applied = true
                DispatchQueue.main.async { [target] in
                    window.setFrame(WindowFrameApplier.appKitFrame(target), display: true)
                }
            }
        }

        /// `rect` (top-left origin at the main screen's visible area) in AppKit's
        /// bottom-left screen space.
        static func appKitFrame(_ rect: CGRect) -> CGRect {
            let visible = NSScreen.screens.first?.visibleFrame ?? .zero
            return CGRect(
                x: visible.minX + rect.minX,
                y: visible.maxY - rect.minY - rect.height,
                width: rect.width,
                height: rect.height,
            )
        }
    }

    extension SegueApp {
        /// `-SegueFixedClock`: captures start the app clock at a fixed instant, then it runs.
        static func captureClock(_ options: LaunchOptions) -> any Support.Clock {
            guard let start = options.fixedClock else { return SystemClock() }
            let monotonic = SuspendingClock()
            let launch = monotonic.now
            let rate = options.clockRate ?? 1
            return MonotonicClock(origin: start) { launch.duration(to: monotonic.now) * rate }
        }

        /// `-SegueWindowFrame` (and, with `-SegueStageWindowed`, the stage window's frame).
        @MainActor
        static func captureWindowFrame(_ options: LaunchOptions) -> CGRect? {
            if options.stageWindowed, let frame = options.windowFrame {
                StageWindowController.shared.windowedFrame = frame
            }
            return options.windowFrame
        }
    }
#endif
