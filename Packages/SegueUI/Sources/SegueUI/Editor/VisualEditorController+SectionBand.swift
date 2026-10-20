#if os(macOS)
    import AppKit
    import ChordPro
    import Editing

    /// Which edge of a section band.
    struct BandEdgeHit: Equatable {
        var band: Int
        var edge: SectionEdge
    }

    /// A gesture in the band lane.
    enum BandGesture {
        /// Picking lines: from the paragraph pressed to the one under the pointer.
        case selecting(anchor: Int)
        /// Dragging a section edge; `target` is the paragraph the edge snaps to.
        case resizing(BandEdgeHit, target: Int?)
    }

    /// Where a band is drawn (text view coordinates). `top` / `bottom` are nil when that
    /// end is scrolled out of view.
    struct BandFrame {
        var band: Int
        var rect: CGRect
        var topVisible: Bool
        var bottomVisible: Bool
    }

    /// Colours of the section band: one hue per kind (verse steel blue, chorus amber,
    /// bridge violet, intro/outro green, the rest grey); never red, which chords use.
    @MainActor
    enum SectionBandStyle {
        static let capHeight: CGFloat = 22
        static let cornerRadius: CGFloat = 7
        static let edgeTolerance: CGFloat = 5

        /// Whether the canvas being drawn is dark; set at the start of every band pass
        /// (colours are resolved concretely, so alpha survives every drawing context).
        static var drawsDark = true

        /// The kind's colour for the current pass.
        static func color(for kind: SectionKind) -> NSColor {
            let (light, dark) = hex(for: kind)
            return rgb(drawsDark ? dark : light)
        }

        /// The kind's colour following the appearance (the SwiftUI chip bar).
        static func dynamicColor(for kind: SectionKind) -> NSColor {
            let (light, dark) = hex(for: kind)
            return NSColor(name: nil) { appearance in
                rgb(isDark(appearance) ? dark : light)
            }
        }

        private static func hex(for kind: SectionKind) -> (light: Int, dark: Int) {
            switch kind {
            case .verse: (0x3A6EA8, 0x6C9BD2)
            case .chorus: (0xA87412, 0xE0A84A)
            case .bridge: (0x7350C2, 0xA487E0)
            case let .custom(name) where ["intro", "outro"].contains(name.lowercased()):
                (0x2E8551, 0x5DB37E)
            case .custom, .tab: (0x55555C, 0x8E8E96)
            }
        }

        /// Cap text: paper on the light caps, stage on the dark ones.
        static var capText: NSColor {
            rgb(drawsDark ? 0x101113 : 0xFFFFFF)
        }

        /// The body tint over the ground.
        static func tint(_ color: NSColor) -> NSColor {
            color.withAlphaComponent(drawsDark ? 0.16 : 0.10)
        }

        static var selectionFill: NSColor {
            drawsDark ? NSColor(white: 0.93, alpha: 0.07) : NSColor(white: 0.07, alpha: 0.05)
        }

        /// The dashed outline of an empty slot.
        static var slotStroke: NSColor {
            rgb(drawsDark ? 0x8E8E96 : 0x8A8A92).withAlphaComponent(drawsDark ? 0.45 : 0.6)
        }

        static var capFont: NSFont {
            EditorStyle.grotesk(.bold, size: 12)
        }

        private static func rgb(_ value: Int) -> NSColor {
            NSColor(
                srgbRed: CGFloat((value >> 16) & 0xFF) / 255,
                green: CGFloat((value >> 8) & 0xFF) / 255,
                blue: CGFloat(value & 0xFF) / 255,
                alpha: 1,
            )
        }

        static func isDark(_ appearance: NSAppearance) -> Bool {
            appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        }
    }

    // MARK: - Geometry

    extension VisualEditorController {
        /// The band lane's x range in text view coordinates.
        var laneX: ClosedRange<CGFloat> {
            let minX = textView.textContainerOrigin.x
                + (textView.textContainer?.lineFragmentPadding ?? 0)
            return minX ... minX + CanvasTypesetting.bandLaneWidth
        }

        func isInLane(_ point: CGPoint) -> Bool {
            point.x >= laneX.lowerBound - 6 && point.x <= laneX.upperBound + 6
        }

        /// The drawn frame of every band intersecting `rect`, from the laid-out rows.
        func bandFrames(in rect: CGRect) -> [BandFrame] {
            guard !bands.bands.isEmpty else { return [] }
            var owner = [Int?](repeating: nil, count: projection.paragraphs.count)
            for (index, band) in bands.bands.enumerated() {
                for paragraph in band.paragraphs where paragraph < owner.count {
                    owner[paragraph] = index
                }
            }
            var tops: [Int: CGFloat] = [:]
            var bottoms: [Int: CGFloat] = [:]
            var firstSeen: Set<Int> = []
            var lastSeen: Set<Int> = []
            forEachRow(in: rect.insetBy(dx: 0, dy: -80)) { row in
                guard let index = owner[row.paragraph] else { return true }
                let band = bands.bands[index]
                tops[index] = min(tops[index] ?? .greatestFiniteMagnitude, row.rect.minY)
                bottoms[index] = max(bottoms[index] ?? -.greatestFiniteMagnitude, row.rect.maxY)
                if row.paragraph == band.paragraphs.lowerBound {
                    firstSeen.insert(index)
                }
                if row.paragraph == band.paragraphs.upperBound, row.isLastRow {
                    lastSeen.insert(index)
                }
                return true
            }
            let x = laneX
            return tops.keys.sorted().compactMap { index in
                guard var top = tops[index], var bottom = bottoms[index] else { return nil }
                if !firstSeen.contains(index) {
                    top = rect.minY - 120
                }
                if !lastSeen.contains(index) {
                    bottom = rect.maxY + 120
                }
                let frame = CGRect(
                    x: x.lowerBound,
                    y: top,
                    width: x.upperBound - x.lowerBound,
                    height: max(bottom - top, SectionBandStyle.capHeight),
                )
                guard frame.intersects(rect) else { return nil }
                return BandFrame(
                    band: index,
                    rect: frame,
                    topVisible: firstSeen.contains(index),
                    bottomVisible: lastSeen.contains(index),
                )
            }
        }

        /// The frame of one band, if it is laid out near the visible area.
        func bandFrame(_ index: Int) -> BandFrame? {
            bandFrames(in: textView.visibleRect).first { $0.band == index }
        }

        /// The paragraph whose row is nearest to `y` (text view coordinates), and that
        /// row's frame.
        func paragraph(atY y: CGFloat) -> (index: Int, rect: CGRect)? {
            var best: (index: Int, rect: CGRect)?
            var bestDistance = CGFloat.greatestFiniteMagnitude
            forEachRow(in: CGRect(x: 0, y: y - 120, width: 1, height: 240)) { row in
                let distance = row.rect.minY > y ? row.rect.minY - y
                    : row.rect.maxY < y ? y - row.rect.maxY : 0
                if distance < bestDistance {
                    best = (row.paragraph, row.rect)
                    bestDistance = distance
                }
                return row.rect.minY <= y + 120
            }
            return best
        }

        /// The top and bottom of a run of paragraphs that is on screen.
        func rowsFrame(_ paragraphs: ClosedRange<Int>) -> CGRect? {
            var frame: CGRect?
            forEachRow(in: textView.visibleRect.insetBy(dx: 0, dy: -80)) { row in
                if paragraphs.contains(row.paragraph) {
                    frame = frame.map { $0.union(row.rect) } ?? row.rect
                }
                return row.paragraph <= paragraphs.upperBound
            }
            return frame
        }

        /// The band edge (editable sections only) or band under a lane point.
        func edgeHit(at point: CGPoint) -> BandEdgeHit? {
            guard isInLane(point) else { return nil }
            for frame in bandFrames(in: textView.visibleRect) {
                guard case let .section(_, _, _, editable) = bands.bands[frame.band].kind,
                      editable
                else { continue }
                let tolerance = SectionBandStyle.edgeTolerance
                if frame.topVisible, abs(point.y - frame.rect.minY) <= tolerance {
                    return BandEdgeHit(band: frame.band, edge: .top)
                }
                if frame.bottomVisible, abs(point.y - frame.rect.maxY) <= tolerance {
                    return BandEdgeHit(band: frame.band, edge: .bottom)
                }
            }
            return nil
        }

        func bandIndex(at point: CGPoint) -> Int? {
            guard isInLane(point) else { return nil }
            return bandFrames(in: textView.visibleRect)
                .first { $0.rect.insetBy(dx: -6, dy: -2).contains(point) }?.band
        }

        /// Lines picked by a text selection that spans more than one canvas line.
        var textLineSelection: ClosedRange<Int>? {
            let range = textView.selectedRange()
            guard range.length > 0, !projection.paragraphs.isEmpty else { return nil }
            let first = projection.paragraphIndex(at: range.location)
            let last = projection.paragraphIndex(at: max(NSMaxRange(range) - 1, range.location))
            return last > first ? first ... last : nil
        }

        /// The line selection the band keys and chips act on.
        var activeLineSelection: ClosedRange<Int>? {
            lineSelection ?? textLineSelection
        }
    }

    // MARK: - Painting

    extension VisualEditorController {
        func drawBands(in dirtyRect: NSRect, overlay: CanvasOverlayView) {
            SectionBandStyle.drawsDark = SectionBandStyle.isDark(textView.effectiveAppearance)
            let visible = textView.visibleRect
            if let selection = activeLineSelection, let rows = rowsFrame(selection) {
                drawSelection(rows, overlay: overlay)
            }
            for frame in bandFrames(in: visible) {
                var rect = frame.rect
                if case let .resizing(hit, target?) = bandGesture, hit.band == frame.band,
                   let snapped = paragraphFrame(target)
                {
                    switch hit.edge {
                    case .top: rect = CGRect(
                            x: rect.minX,
                            y: snapped.minY,
                            width: rect.width,
                            height: max(rect.maxY - snapped.minY, SectionBandStyle.capHeight),
                        )
                    case .bottom: rect.size.height = max(
                            snapped.maxY - rect.minY,
                            SectionBandStyle.capHeight,
                        )
                    }
                }
                let drawn = textView.convert(rect, to: overlay)
                guard drawn.intersects(dirtyRect) else { continue }
                drawBand(bands.bands[frame.band], frame: frame, in: drawn)
            }
        }

        private func paragraphFrame(_ index: Int) -> CGRect? {
            rowsFrame(index ... index)
        }

        private func drawSelection(_ rows: CGRect, overlay: CanvasOverlayView) {
            let containerWidth = textView.textContainer?.size.width ?? textView.bounds.width
            let right = textView.textContainerOrigin.x + containerWidth
            let area = CGRect(
                x: laneX.lowerBound - 10,
                y: rows.minY - 4,
                width: right - laneX.lowerBound + 10,
                height: rows.height + 8,
            )
            SectionBandStyle.selectionFill.setFill()
            NSBezierPath(
                roundedRect: textView.convert(area, to: overlay),
                xRadius: 8,
                yRadius: 8,
            ).fill()
        }

        private func drawBand(_ band: SectionBand, frame: BandFrame, in rect: CGRect) {
            let isSelected = activeLineSelection == band.paragraphs
            let shape = NSBezierPath(
                roundedRect: rect.insetBy(dx: 0.5, dy: 1.5),
                xRadius: SectionBandStyle.cornerRadius,
                yRadius: SectionBandStyle.cornerRadius,
            )
            shape.lineWidth = 1
            switch band.kind {
            case let .section(path, kind, _, _):
                drawSection(
                    band,
                    kind: kind,
                    notes: sectionNoteCount(path),
                    frame: frame,
                    rect: rect,
                )
                SectionBandStyle.color(for: kind).withAlphaComponent(0.55).setStroke()
                if isSelected {
                    EditorStyle.ink.setStroke()
                    shape.lineWidth = 1.5
                    shape.setLineDash([4, 3], count: 2, phase: 0)
                }
                shape.stroke()
                drawEdgeGrip(frame: frame, rect: rect)
            case .slot:
                if isSelected {
                    SectionBandStyle.selectionFill.setFill()
                    shape.fill()
                    EditorStyle.ink.setStroke()
                    shape.lineWidth = 1.5
                } else {
                    SectionBandStyle.slotStroke.setStroke()
                }
                shape.setLineDash([4, 3], count: 2, phase: 0)
                shape.stroke()
            case .repeatRef:
                let color = SectionBandStyle.color(for: .chorus)
                color.withAlphaComponent(0.7).setStroke()
                shape.setLineDash([4, 3], count: 2, phase: 0)
                shape.stroke()
                drawRepeatText(band.title, color: color, in: rect)
            }
        }

        /// The tinted body and, when the top is on screen, the solid cap with the label
        /// and the note badge slot.
        private func drawSection(
            _ band: SectionBand,
            kind: SectionKind,
            notes: Int,
            frame: BandFrame,
            rect: CGRect,
        ) {
            let color = SectionBandStyle.color(for: kind)
            let body = NSBezierPath(
                roundedRect: rect.insetBy(dx: 0.5, dy: 1.5),
                xRadius: SectionBandStyle.cornerRadius,
                yRadius: SectionBandStyle.cornerRadius,
            )
            SectionBandStyle.tint(color).setFill()
            body.fill()
            guard frame.topVisible else { return }
            NSGraphicsContext.saveGraphicsState()
            body.addClip()
            color.setFill()
            CGRect(
                x: rect.minX,
                y: rect.minY,
                width: rect.width,
                height: 1.5 + SectionBandStyle.capHeight,
            ).fill()
            drawCapText(band.title, notes: notes, in: rect)
            NSGraphicsContext.restoreGraphicsState()
        }

        /// The label, truncated to the cap, and the note badge slot at its right (a speech
        /// bubble and the count; P3-13 supplies the count, nothing shows at zero).
        private func drawCapText(_ title: String, notes: Int, in rect: CGRect) {
            let attributes: [NSAttributedString.Key: Any] = [
                .font: SectionBandStyle.capFont,
                .foregroundColor: SectionBandStyle.capText,
            ]
            let count = notes > 0 ? "\(notes)" as NSString : nil
            let countWidth = count.map { $0.size(withAttributes: attributes).width } ?? 0
            let badgeWidth = count == nil ? 0 : countWidth + 18
            let text = NSAttributedString(string: title, attributes: attributes)
            let size = text.size()
            let origin = CGPoint(
                x: rect.minX + 8,
                y: rect.minY + 1.5 + (SectionBandStyle.capHeight - size.height) / 2,
            )
            text.draw(
                with: CGRect(
                    origin: origin,
                    size: CGSize(width: rect.width - 16 - badgeWidth, height: size.height),
                ),
                options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine],
            )
            guard let count else { return }
            let x = rect.maxX - 8 - badgeWidth
            let configuration = NSImage.SymbolConfiguration(pointSize: 10, weight: .bold)
                .applying(.init(paletteColors: [SectionBandStyle.capText]))
            if let bubble = NSImage(systemSymbolName: "text.bubble", accessibilityDescription: nil)?
                .withSymbolConfiguration(configuration)
            {
                bubble.draw(
                    in: CGRect(x: x, y: origin.y + 2, width: 13, height: 12),
                    from: .zero,
                    operation: .sourceOver,
                    fraction: 1,
                    respectFlipped: true,
                    hints: nil,
                )
            }
            count.draw(at: CGPoint(x: x + 16, y: origin.y), withAttributes: attributes)
        }

        private func drawRepeatText(_ title: String, color: NSColor, in rect: CGRect) {
            let attributes: [NSAttributedString.Key: Any] = [
                .font: SectionBandStyle.capFont,
                .foregroundColor: color,
            ]
            let text = "\u{21BB} \(title)" as NSString
            let size = text.size(withAttributes: attributes)
            text.draw(
                at: CGPoint(x: rect.minX + 8, y: rect.midY - size.height / 2),
                withAttributes: attributes,
            )
        }

        /// The hovered or dragged edge: an ink line with a grip in the middle.
        private func drawEdgeGrip(frame: BandFrame, rect: CGRect) {
            let edge: SectionEdge? = switch bandGesture {
            case let .resizing(hit, _) where hit.band == frame.band: hit.edge
            default: hoveredEdge?.band == frame.band ? hoveredEdge?.edge : nil
            }
            guard let edge else { return }
            let y = edge == .top ? rect.minY + 1 : rect.maxY - 1
            EditorStyle.ink.setFill()
            CGRect(x: rect.minX, y: y - 1, width: rect.width, height: 2).fill()
            let grip = NSBezierPath(
                roundedRect: CGRect(x: rect.midX - 14, y: y - 4, width: 28, height: 8),
                xRadius: 4,
                yRadius: 4,
            )
            EditorStyle.ground.setFill()
            grip.fill()
            EditorStyle.ink.setStroke()
            grip.lineWidth = 1.5
            grip.stroke()
        }
    }
#endif
