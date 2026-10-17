#if os(macOS)
    import AppKit
    import QuartzCore

    /// The ChordPro source view (text mode): a TextKit 2 `NSTextView` that draws line numbers
    /// in its left inset and highlights the caret's line (mockup E2 a), and times each
    /// keystroke (acceptance criterion 9: < 16 ms on a 200-line song).
    final class SourceTextView: NSTextView {
        /// Width of the line-number column inside the left inset.
        static let gutterWidth: CGFloat = 48
        /// Space between the line numbers and the text.
        static let gutterGap: CGFloat = 16

        /// UTF-16 offsets where each source line starts (line 1 at index 0).
        var lineStarts = [0]
        /// Called after every key event with its processing time in seconds.
        var onKeystrokeTimed: ((TimeInterval, Bool) -> Void)?
        /// Lets the controller see Esc / arrows / Return before the text view does.
        weak var keyHandler: (any SourceKeyHandling)?

        /// The text starts after the line-number column. The inset's width is half the
        /// column, so the container (view width minus twice the inset) ends at the view's
        /// right edge.
        override var textContainerOrigin: NSPoint {
            NSPoint(x: Self.gutterWidth, y: textContainerInset.height)
        }

        override func keyDown(with event: NSEvent) {
            let start = CACurrentMediaTime()
            super.keyDown(with: event)
            // Lay out the viewport now (it would happen before the next frame anyway), so
            // the measurement covers parse + highlight + layout of the edit.
            textLayoutManager?.textViewportLayoutController.layoutViewport()
            let elapsed = CACurrentMediaTime() - start
            if elapsed > 0.008 {
                EditorPerformance.log.notice(
                    "slow key \(event.charactersIgnoringModifiers ?? "?", privacy: .public)",
                )
            }
            onKeystrokeTimed?(elapsed, event.modifierFlags.contains(.command))
        }

        override func doCommand(by selector: Selector) {
            if keyHandler?.handleCommand(selector) == true {
                return
            }
            super.doCommand(by: selector)
        }

        // MARK: Line numbers and current line

        /// Line numbers and the caret-line band, drawn behind the text. A subview because
        /// a TextKit 2 text view does not redraw its own background on `setNeedsDisplay`.
        private(set) lazy var gutter: SourceGutterView = {
            let gutter = SourceGutterView()
            gutter.textView = self
            gutter.autoresizingMask = [.width, .height]
            gutter.frame = bounds
            addSubview(gutter, positioned: .below, relativeTo: nil)
            return gutter
        }()

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            gutter.needsDisplay = true
        }

        override func setFrameSize(_ newSize: NSSize) {
            super.setFrameSize(newSize)
            gutter.frame = bounds
            gutter.needsDisplay = true
        }

        /// Draws the gutter and band for `rect` (gutter view coordinates = text view's).
        func drawGutter(in rect: NSRect) {
            guard let layoutManager = textLayoutManager,
                  let contentManager = layoutManager.textContentManager
            else { return }
            let origin = textContainerOrigin
            let length = (string as NSString).length
            let caretLine = lineIndex(forOffset: selectedRange().location)
            let endsWithNewline = lineStarts.last == length && length > 0
            let documentStart = layoutManager.documentRange.location
            let startPoint = CGPoint(x: 0, y: max(rect.minY - origin.y, 0))
            let startLocation = layoutManager.textLayoutFragment(for: startPoint)?
                .rangeInElement.location ?? documentStart
            layoutManager.enumerateTextLayoutFragments(
                from: startLocation,
                options: [.ensuresLayout, .ensuresExtraLineFragment],
            ) { fragment in
                let frame = fragment.layoutFragmentFrame.offsetBy(dx: origin.x, dy: origin.y)
                let offset = contentManager.offset(
                    from: documentStart,
                    to: fragment.rangeInElement.location,
                )
                let line = lineIndex(forOffset: offset)
                let lines = fragment.textLineFragments
                let endOffset = contentManager.offset(
                    from: documentStart,
                    to: fragment.rangeInElement.endLocation,
                )
                // The empty line after a final newline is an extra line fragment of the last
                // paragraph, not a paragraph of its own.
                let extra = endsWithNewline && endOffset >= length && lines.count > 1
                    && lines.last?.characterRange.length == 0
                    ? lines.last : nil
                let paragraphHeight = frame.height - (extra?.typographicBounds.height ?? 0)
                if line == caretLine {
                    fillLineBand(y: frame.minY, height: paragraphHeight)
                }
                drawNumber(
                    line + 1,
                    lineTop: frame.minY + (lines.first?.typographicBounds.minY ?? 0),
                )
                if let extra {
                    let extraY = frame.minY + extra.typographicBounds.minY
                    if caretLine == lineStarts.count - 1 {
                        fillLineBand(y: extraY, height: extra.typographicBounds.height)
                    }
                    drawNumber(lineStarts.count, lineTop: extraY)
                }
                return frame.minY < rect.maxY
            }
        }

        private func fillLineBand(y: CGFloat, height: CGFloat) {
            EditorStyle.surfaceAlt.setFill()
            NSRect(x: 0, y: y, width: bounds.width, height: height).fill()
        }

        /// A line number on the text's baseline (the source text is raised by its baseline
        /// offset to sit centred in the 24pt line).
        private func drawNumber(_ number: Int, lineTop: CGFloat) {
            let font = EditorStyle.lineNumberFont
            let attributes: [NSAttributedString.Key: Any] = [
                .font: font,
                .foregroundColor: EditorStyle.lineNumber,
            ]
            let label = "\(number)" as NSString
            let size = label.size(withAttributes: attributes)
            let textFont = EditorStyle.sourceFont
            let baseline = lineTop + EditorStyle.sourceLineHeight + textFont.descender
                - EditorStyle.sourceBaselineOffset
            label.draw(
                at: NSPoint(
                    x: Self.gutterWidth - Self.gutterGap - size.width,
                    y: baseline - font.ascender,
                ),
                withAttributes: attributes,
            )
        }

        /// The 0-based line holding a UTF-16 offset.
        func lineIndex(forOffset offset: Int) -> Int {
            var low = 0
            var high = lineStarts.count - 1
            while low < high {
                let mid = (low + high + 1) / 2
                if lineStarts[mid] <= offset {
                    low = mid
                } else {
                    high = mid - 1
                }
            }
            return low
        }

        /// Recomputes `lineStarts` from the text.
        func updateLineStarts() {
            let text = string as NSString
            var starts = [0]
            starts.reserveCapacity(lineStarts.count + 4)
            let length = text.length
            var index = 0
            while index < length {
                let character = text.character(at: index)
                if character == 0x0A {
                    starts.append(index + 1)
                } else if character == 0x0D {
                    if index + 1 < length, text.character(at: index + 1) == 0x0A {
                        index += 1
                    }
                    starts.append(index + 1)
                }
                index += 1
            }
            lineStarts = starts
        }

        /// Redraws the line band when the caret moves to another line.
        func caretLineDidChange() {
            gutter.needsDisplay = true
        }

        override func setSelectedRanges(
            _ ranges: [NSValue],
            affinity: NSSelectionAffinity,
            stillSelecting: Bool,
        ) {
            let before = lineIndex(forOffset: selectedRange().location)
            super.setSelectedRanges(ranges, affinity: affinity, stillSelecting: stillSelecting)
            if lineIndex(forOffset: selectedRange().location) != before {
                caretLineDidChange()
            }
        }
    }

    /// Key commands the source controller wants first (completion navigation).
    @MainActor
    protocol SourceKeyHandling: AnyObject {
        /// Returns true when the command was handled.
        func handleCommand(_ selector: Selector) -> Bool
    }

    /// Draws the source view's line numbers and caret-line band behind its text.
    final class SourceGutterView: NSView {
        weak var textView: SourceTextView?

        override var isFlipped: Bool {
            true
        }

        override func hitTest(_: NSPoint) -> NSView? {
            nil
        }

        override func draw(_ dirtyRect: NSRect) {
            textView?.drawGutter(in: dirtyRect)
        }
    }
#endif
