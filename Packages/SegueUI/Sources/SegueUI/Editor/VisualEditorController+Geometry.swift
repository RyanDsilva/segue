#if os(macOS)
    import AppKit
    import CoreText
    import Editing

    /// One laid-out row of a canvas paragraph (a lyric line wraps into several rows).
    @MainActor
    struct CanvasRow {
        var paragraph: Int
        /// The row's typographic rect in text view coordinates.
        var rect: CGRect
        /// The x of the paragraph's layout fragment, in text view coordinates.
        var fragmentX: CGFloat
        var line: NSTextLineFragment
        var baseline: CGFloat
        var isLastRow: Bool

        /// Top of the lyric glyphs; the chord lane is everything above it.
        var lyricTop: CGFloat {
            baseline - EditorStyle.canvasLyricFont.ascender
        }

        var pillTop: CGFloat {
            lyricTop - CanvasTypesetting.pillGap - CanvasTypesetting.pillHeight
        }

        /// Whether the row shows the UTF-16 offset `offset` of its paragraph.
        func holds(_ offset: Int) -> Bool {
            let range = line.characterRange
            return NSLocationInRange(offset, range) || (isLastRow && offset >= NSMaxRange(range))
                || (offset == NSMaxRange(range) && range.length == 0)
        }

        /// x (text view coordinates) of the caret position before UTF-16 `offset`.
        func x(at offset: Int) -> CGFloat {
            let clamped = min(
                max(offset, line.characterRange.location),
                NSMaxRange(line.characterRange),
            )
            return fragmentX + line.typographicBounds.minX + line.locationForCharacter(at: clamped)
                .x
        }
    }

    /// A pill as laid out on the canvas.
    struct PillLayout {
        var paragraph: Int
        var line: RenderLine
        var chord: RenderChord
        /// Text view coordinates.
        var rect: CGRect
    }

    /// A chord slot: above the character at `offset` of a lyric line.
    struct LaneTarget: Equatable {
        var paragraph: Int
        var path: BlockPath
        /// `Character` offset into the lyric text.
        var offset: Int
        /// Top-left of a pill placed there (text view coordinates).
        var anchor: CGPoint
    }

    /// The selected pill, by content (refs go stale after every edit).
    struct ChordSelection: Equatable {
        var path: BlockPath
        var offset: Int
        var original: String
    }

    /// A pill being pressed or dragged.
    struct ChordDrag {
        var pill: PillLayout
        var start: CGPoint
        var current: CGPoint
        var isDragging = false
        var duplicate = false
        var target: LaneTarget?
    }

    extension VisualEditorController {
        /// Calls `body` for each laid-out row intersecting `rect` (text view coordinates),
        /// top to bottom, until it returns false.
        func forEachRow(in rect: CGRect, _ body: (CanvasRow) -> Bool) {
            guard let layoutManager = textView.textLayoutManager,
                  let contentManager = layoutManager.textContentManager,
                  !projection.paragraphs.isEmpty
            else { return }
            let origin = textView.textContainerOrigin
            let documentStart = layoutManager.documentRange.location
            let startPoint = CGPoint(x: 0, y: max(rect.minY - origin.y, 0))
            let start = layoutManager.textLayoutFragment(for: startPoint)?.rangeInElement.location
                ?? documentStart
            layoutManager
                .enumerateTextLayoutFragments(from: start, options: [.ensuresLayout]) { fragment in
                    let frame = fragment.layoutFragmentFrame.offsetBy(dx: origin.x, dy: origin.y)
                    guard frame.minY <= rect.maxY else { return false }
                    let location = contentManager.offset(
                        from: documentStart,
                        to: fragment.rangeInElement.location,
                    )
                    let index = projection.paragraphIndex(at: location)
                    let lines = fragment.textLineFragments.filter {
                        $0.characterRange.length > 0 || fragment.textLineFragments.count == 1
                    }
                    for (rowIndex, line) in lines.enumerated() {
                        let bounds = line.typographicBounds.offsetBy(dx: frame.minX, dy: frame.minY)
                        let row = CanvasRow(
                            paragraph: index,
                            rect: bounds,
                            fragmentX: frame.minX,
                            line: line,
                            baseline: bounds.minY + line.glyphOrigin.y,
                            isLastRow: rowIndex == lines.count - 1,
                        )
                        if bounds.maxY >= rect.minY, !body(row) {
                            return false
                        }
                    }
                    return true
                }
        }

        /// Where the character at a paragraph UTF-16 offset starts, as drawn: the row's
        /// start plus the typeset width of the row's text before it. (TextKit's caret
        /// geometry ignores the kerning that makes room for pills; the drawn glyphs do not.)
        func anchorX(in row: CanvasRow, at offset: Int) -> CGFloat {
            let rowStart = row.line.characterRange.location
            let start = row.x(at: rowStart)
            guard offset > rowStart, let storage = textView.textStorage else { return start }
            let paragraphStart = projection.starts[row.paragraph]
            let range = NSRange(location: paragraphStart + rowStart, length: offset - rowStart)
            guard NSMaxRange(range) <= storage.length else { return row.x(at: offset) }
            let prefix = storage.attributedSubstring(from: range)
            let line = CTLineCreateWithAttributedString(prefix)
            return start + CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil))
        }

        /// The pills of one row.
        func pills(in row: CanvasRow) -> [PillLayout] {
            guard let line = projection.paragraphs[row.paragraph].lyricLine else { return [] }
            var result: [PillLayout] = []
            for group in CanvasTypesetting.groups(of: line.chords) {
                let offset = line.utf16Offset(ofLyricOffset: group.offset)
                guard row.holds(offset) else { continue }
                var x = anchorX(in: row, at: offset)
                for chord in group.chords {
                    let width = CanvasTypesetting.pillWidth(chord.text)
                    let rect = CGRect(
                        x: x,
                        y: row.pillTop,
                        width: width,
                        height: CanvasTypesetting.pillHeight,
                    )
                    result.append(PillLayout(
                        paragraph: row.paragraph,
                        line: line,
                        chord: chord,
                        rect: rect,
                    ))
                    x += width + CanvasTypesetting.stackSpacing
                }
            }
            return result
        }

        /// The pill under `point` (text view coordinates).
        func pill(at point: CGPoint) -> PillLayout? {
            var found: PillLayout?
            let probe = CGRect(x: point.x, y: point.y - 80, width: 1, height: 160)
            forEachRow(in: probe) { row in
                if let hit = pills(in: row)
                    .last(where: { $0.rect.insetBy(dx: -2, dy: -2).contains(point) })
                {
                    found = hit
                    return false
                }
                return row.rect.minY <= point.y + 80
            }
            return found
        }

        /// The chord slot under `point`. In the lane only (`laneOnly`, for clicks: the
        /// character under the pointer), or anywhere on the row (drags: the nearest
        /// character boundary).
        func laneTarget(at point: CGPoint, laneOnly: Bool) -> LaneTarget? {
            var found: LaneTarget?
            let probe = CGRect(x: point.x, y: point.y - 1, width: 1, height: 2)
            forEachRow(in: probe) { row in
                guard row.rect.minY <= point.y,
                      point.y < row.rect.maxY + CanvasTypesetting.lineSpacing
                else { return true }
                guard let line = projection.paragraphs[row.paragraph].lyricLine
                else { return false }
                if laneOnly, point.y >= row.lyricTop {
                    return false
                }
                found = target(in: row, line: line, x: point.x, nearest: !laneOnly)
                return false
            }
            return found
        }

        private func target(
            in row: CanvasRow,
            line: RenderLine,
            x: CGFloat,
            nearest: Bool,
        ) -> LaneTarget {
            let range = row.line.characterRange
            let first = line.lyricOffset(atUTF16: range.location)
            let last = row.isLastRow
                ? line.lyricCount
                : line.lyricOffset(atUTF16: NSMaxRange(range))
            var best = first
            var bestDistance = CGFloat.greatestFiniteMagnitude
            for offset in first ... max(first, last) {
                let position = anchorX(in: row, at: line.utf16Offset(ofLyricOffset: offset))
                if nearest {
                    let distance = abs(position - x)
                    if distance < bestDistance {
                        bestDistance = distance
                        best = offset
                    }
                } else if position <= x + 0.5 {
                    best = offset
                } else {
                    break
                }
            }
            let anchorX = anchorX(in: row, at: line.utf16Offset(ofLyricOffset: best))
            return LaneTarget(
                paragraph: row.paragraph,
                path: line.path,
                offset: best,
                anchor: CGPoint(x: anchorX, y: row.pillTop),
            )
        }

        /// Finds the pill for a selection in the current projection.
        func layout(of selection: ChordSelection) -> PillLayout? {
            guard let index = projection.lyricParagraphs[selection.path] else { return nil }
            let paragraphRange = projection.range(of: index)
            var found: PillLayout?
            let top = textView.textLayoutManager.flatMap { manager -> CGFloat? in
                guard let contentManager = manager.textContentManager,
                      let location = contentManager.location(
                          manager.documentRange.location,
                          offsetBy: paragraphRange.location,
                      ),
                      let fragment = manager.textLayoutFragment(for: location)
                else { return nil }
                return fragment.layoutFragmentFrame.minY + textView.textContainerOrigin.y
            } ?? 0
            forEachRow(in: CGRect(x: 0, y: top, width: 1, height: 1)) { row in
                guard row.paragraph == index else { return row.paragraph < index }
                if let pill = pills(in: row).last(where: {
                    $0.chord.offset == selection.offset && $0.chord.original == selection.original
                }) {
                    found = pill
                    return false
                }
                return true
            }
            return found
        }

        /// The chord a selection names, from the projection (no layout needed).
        func chord(for selection: ChordSelection) -> (line: RenderLine, chord: RenderChord)? {
            guard let index = projection.lyricParagraphs[selection.path],
                  let line = projection.paragraphs[index].lyricLine,
                  let chord = line.chords.last(where: {
                      $0.offset == selection.offset && $0.original == selection.original
                  })
            else { return nil }
            return (line, chord)
        }

        /// Drops a selection whose chord no longer exists.
        func resolveSelection() {
            if let selection = selectedChord, chord(for: selection) == nil {
                selectedChord = nil
            }
        }
    }

    // MARK: - Accessibility

    extension VisualEditorController {
        func overlayAccessibilityElements(for overlay: CanvasOverlayView) -> [Any] {
            guard let window = textView.window else { return [] }
            var elements: [Any] = []
            func screenFrame(_ rect: CGRect) -> CGRect {
                window.convertToScreen(textView.convert(rect, to: nil))
            }
            forEachRow(in: textView.visibleRect) { row in
                guard let line = projection.paragraphs[row.paragraph].lyricLine else { return true }
                for word in LyricOffsets.words(in: line) {
                    let start = line.utf16Offset(ofLyricOffset: word.offsets.lowerBound)
                    guard row.holds(start) else { continue }
                    let end = line.utf16Offset(ofLyricOffset: word.offsets.upperBound)
                    let minX = anchorX(in: row, at: start)
                    let rect = CGRect(
                        x: minX,
                        y: row.pillTop,
                        width: max(row.x(at: end) - minX, 8),
                        height: CanvasTypesetting.pillHeight,
                    )
                    elements.append(accessibilityElement(
                        label: word.word,
                        identifier: AccessibilityID.editorLane,
                        frame: screenFrame(rect),
                        parent: overlay,
                    ))
                }
                for pill in pills(in: row) {
                    let element = accessibilityElement(
                        label: pill.chord.text,
                        identifier: AccessibilityID.editorPill,
                        frame: screenFrame(pill.rect),
                        parent: overlay,
                    )
                    let selection = ChordSelection(
                        path: pill.line.path,
                        offset: pill.chord.offset,
                        original: pill.chord.original,
                    )
                    element.setAccessibilitySelected(selection == selectedChord)
                    elements.append(element)
                }
                return true
            }
            return elements
        }

        private func accessibilityElement(
            label: String,
            identifier: String,
            frame: CGRect,
            parent: Any,
        ) -> NSAccessibilityElement {
            let element = NSAccessibilityElement()
            element.setAccessibilityRole(.button)
            element.setAccessibilityLabel(label)
            element.setAccessibilityIdentifier(identifier)
            element.setAccessibilityFrame(frame)
            element.setAccessibilityParent(parent)
            return element
        }
    }
#endif
