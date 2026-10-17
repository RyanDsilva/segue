#if os(macOS)
    import AppKit
    import Editing

    /// How a pill is drawn.
    enum PillStyle {
        case normal
        case selected
        /// Unparseable chord: dashed red outline (an inline diagnostic).
        case unknown
        case noChord
        /// A slot you can drop a chord into (hover, open popover, drag target).
        case ghost
        /// The original of a pill being dragged.
        case lifted
    }

    extension VisualEditorController: CanvasOverlayPainting {
        func drawOverlay(in dirtyRect: NSRect, of overlay: CanvasOverlayView) {
            let clip = overlay.convert(container.scrollView.contentView.frame, from: container)
            NSBezierPath(rect: clip).setClip()
            let visible = textView.visibleRect
            let dragged = drag?.isDragging == true ? drag?.pill : nil
            forEachRow(in: visible) { row in
                switch projection.paragraphs[row.paragraph].role {
                case .label:
                    drawRule(
                        after: projection.paragraphs[row.paragraph].text,
                        in: row,
                        overlay: overlay,
                    )
                case .lyrics:
                    for pill in pills(in: row) {
                        let rect = textView.convert(pill.rect, to: overlay)
                        guard rect.intersects(dirtyRect) else { continue }
                        let isDragged = dragged.map {
                            $0.line.path == pill.line.path && $0.chord.ref == pill.chord.ref
                        } ?? false
                        drawPill(
                            pill.chord.text,
                            in: rect,
                            style: isDragged ? .lifted : style(of: pill),
                        )
                    }
                default:
                    break
                }
                return true
            }
            drawGhosts(overlay: overlay)
        }

        private func style(of pill: PillLayout) -> PillStyle {
            let selection = ChordSelection(
                path: pill.line.path,
                offset: pill.chord.offset,
                original: pill.chord.original,
            )
            if selection == selectedChord {
                return .selected
            }
            return switch pill.chord.kind {
            case .chord: .normal
            case .noChord: .noChord
            case .unknown: .unknown
            }
        }

        private func drawGhosts(overlay: CanvasOverlayView) {
            if let drag, drag.isDragging {
                if let target = drag.target {
                    let width = CanvasTypesetting.pillWidth(drag.pill.chord.text)
                    let slot = CGRect(
                        origin: target.anchor,
                        size: CGSize(width: width, height: CanvasTypesetting.pillHeight),
                    )
                    drawPill(
                        drag.pill.chord.text,
                        in: textView.convert(slot, to: overlay),
                        style: .ghost,
                    )
                }
                var floating = drag.pill.rect
                floating.origin.x += drag.current.x - drag.start.x
                floating.origin.y += drag.current.y - drag.start.y
                drawPill(
                    drag.pill.chord.text,
                    in: textView.convert(floating, to: overlay),
                    style: .selected,
                )
                return
            }
            if let target = popoverTarget ?? hover {
                let title = popoverTarget == nil ? (model.armedChord ?? "+") : "+"
                let width = max(CanvasTypesetting.pillWidth(title), 30)
                let slot = CGRect(
                    origin: target.anchor,
                    size: CGSize(width: width, height: CanvasTypesetting.pillHeight),
                )
                drawPill(title, in: textView.convert(slot, to: overlay), style: .ghost)
            }
        }

        /// The hairline after a section label (mockup: label, then a 1pt `line` rule).
        private func drawRule(after label: String, in row: CanvasRow, overlay: CanvasOverlayView) {
            let font = EditorStyle.labelFont
            let width = (label as NSString).size(withAttributes: [.font: font]).width
            let start = row.fragmentX + row.line.typographicBounds.minX + width + 10
            let containerWidth = textView.textContainer?.size.width ?? textView.bounds.width
            let end = textView.textContainerOrigin.x + containerWidth
                - (textView.textContainer?.lineFragmentPadding ?? 0)
            guard end > start else { return }
            let y = (row.baseline - font.xHeight / 2).rounded() + 0.5
            let rule = textView.convert(
                CGRect(x: start, y: y - 0.5, width: end - start, height: 1),
                to: overlay,
            )
            EditorStyle.line.setFill()
            rule.fill()
        }

        func drawPill(_ text: String, in rect: CGRect, style: PillStyle) {
            let shape = NSBezierPath(
                roundedRect: rect.insetBy(dx: 0.5, dy: 0.5),
                xRadius: CanvasTypesetting.pillCornerRadius,
                yRadius: CanvasTypesetting.pillCornerRadius,
            )
            shape.lineWidth = 1
            let textColor = drawPillShape(shape, style: style)
            let font = EditorStyle.pillFont
            let attributes: [NSAttributedString.Key: Any] = [
                .font: font,
                .foregroundColor: textColor,
            ]
            let size = (text as NSString).size(withAttributes: attributes)
            let point = CGPoint(
                x: rect.minX + (rect.width - size.width) / 2,
                y: rect.minY + (rect.height - size.height) / 2,
            )
            (text as NSString).draw(at: point, withAttributes: attributes)
        }

        /// Fills and strokes a pill for `style`; returns its text colour.
        private func drawPillShape(_ shape: NSBezierPath, style: PillStyle) -> NSColor {
            let dashed = style == .unknown || style == .ghost || style == .lifted
            if dashed {
                shape.setLineDash([3, 2], count: 2, phase: 0)
            }
            switch style {
            case .noChord, .normal, .unknown:
                EditorStyle.ground.setFill()
                shape.fill()
                (style == .unknown ? EditorStyle.errorUnderline : NSColor.segueControlBorder)
                    .setStroke()
                shape.stroke()
                return style == .noChord ? EditorStyle.muted : EditorStyle.cueText
            case .selected:
                EditorStyle.ink.setFill()
                shape.fill()
                return EditorStyle.ground
            case .ghost:
                EditorStyle.ground.withAlphaComponent(0.85).setFill()
                shape.fill()
                EditorStyle.lineStrong.setStroke()
                shape.stroke()
                return EditorStyle.muted
            case .lifted:
                EditorStyle.ground.setFill()
                shape.fill()
                EditorStyle.lineStrong.setStroke()
                shape.stroke()
                return EditorStyle.cueText.withAlphaComponent(0.35)
            }
        }
    }
#endif
