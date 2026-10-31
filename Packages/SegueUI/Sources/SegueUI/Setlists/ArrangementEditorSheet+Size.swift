#if os(macOS)
    import CoreGraphics

    extension ArrangementEditorSheet {
        /// The design's 1200 x 760 (B1) where the window has room; in a smaller window, the
        /// window less a margin on each side, down to 760 x 480 (the window's minimum is 820 x
        /// 520).
        static func size(in window: CGSize?) -> CGSize {
            guard let window else { return CGSize(width: 1200, height: 760) }
            return CGSize(
                width: min(1200, max(760, window.width - 48)),
                height: min(760, max(480, window.height - 40)),
            )
        }

        /// The palette, lane and inspector pane: 640 of the full 1200, never under 400 so a
        /// chip row and the inspector's controls keep their room; the preview takes the rest.
        static func paneWidth(sheetWidth: CGFloat) -> CGFloat {
            min(640, max(400, (sheetWidth * 0.53).rounded()))
        }
    }
#endif
