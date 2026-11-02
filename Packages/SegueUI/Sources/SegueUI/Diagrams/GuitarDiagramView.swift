// Owner: unit B (diagram views). Frozen interface: docs/phases/1-interfaces.md.

import Diagrams
import SwiftUI

/// A guitar chord box: n strings from the tuning, base-fret label, barres, muted/open
/// markers, capo bar when `capoFret` is set (Shapes mode).
struct GuitarDiagramView: View {
    let name: String
    let shape: GuitarShape
    let tuning: Tuning
    var capoFret: Int?
    var size: DiagramSize = .regular
    /// Fret rows drawn at least (the shape editor shows one more for room).
    var minimumFrets = 4
    /// Overrides the size's default for finger numbers (the shape editor always shows them).
    var showsFingers: Bool?
    /// When set, the grid is editable: called with the string and the relative fret
    /// tapped (`0` for the marker row above the nut).
    var onTapCell: ((_ string: Int, _ fret: Int) -> Void)?

    var body: some View {
        let geometry = geometry
        VStack(spacing: geometry.metrics.nameSpacing) {
            DiagramNameLabel(name: name, metrics: geometry.metrics)
                .frame(maxWidth: geometry.size.width)
            GuitarDiagramCanvas(geometry: geometry, shape: shape)
                .modifier(TapLocationModifier(isEnabled: onTapCell != nil) { location in
                    if let cell = geometry.cell(at: location) {
                        onTapCell?(cell.string, cell.fret)
                    }
                })
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(uiString("\(name), guitar"))
        .accessibilityValue(accessibilityValue)
        .accessibilityIdentifier(AccessibilityID.guitarDiagram)
    }

    private var geometry: GuitarDiagramGeometry {
        var metrics = DiagramMetrics.forSize(size)
        if let showsFingers {
            metrics.showsFingers = showsFingers
        }
        return GuitarDiagramGeometry(
            metrics: metrics,
            shape: shape,
            stringCount: tuning.strings.count,
            minimumFrets: minimumFrets,
            capoFret: capoFret,
        )
    }

    /// Strings low to high (`x` muted), then base fret and capo: "x 3 2 0 1 0".
    private var accessibilityValue: String {
        var parts = [shape.frets.map { $0.map(String.init) ?? "x" }.joined(separator: " ")]
        if shape.baseFret > 1 {
            parts.append("base fret \(shape.baseFret)")
        }
        if let capoFret, capoFret > 0 {
            parts.append("capo \(capoFret)")
        }
        return parts.joined(separator: ", ")
    }
}

/// The drawn diagram without its name, sized to its geometry.
struct GuitarDiagramCanvas: View {
    let geometry: GuitarDiagramGeometry
    let shape: GuitarShape

    var body: some View {
        Canvas { context, _ in
            GuitarDiagramRenderer(geometry: geometry, shape: shape).draw(in: &context)
        }
        .frame(width: geometry.size.width, height: geometry.size.height)
        .contentShape(Rectangle())
    }
}

/// Tap handling with the location, only when editing (so read-only diagrams stay inert).
private struct TapLocationModifier: ViewModifier {
    let isEnabled: Bool
    let action: (CGPoint) -> Void

    func body(content: Content) -> some View {
        if isEnabled {
            content.onTapGesture(coordinateSpace: .local, perform: action)
        } else {
            content
        }
    }
}

/// Where everything in a guitar diagram sits, in points. Positions are whole points so
/// hairlines land on device pixels at 2x.
struct GuitarDiagramGeometry {
    let metrics: DiagramMetrics
    let stringCount: Int
    let fretCount: Int
    let baseFret: Int
    let capoFret: Int?

    init(
        metrics: DiagramMetrics,
        shape: GuitarShape,
        stringCount: Int,
        minimumFrets: Int,
        capoFret: Int?,
    ) {
        self.metrics = metrics
        self.stringCount = max(stringCount, 1)
        let highest = shape.frets.compactMap(\.self).max() ?? 0
        let barreHighest = shape.barres.map(\.fret).max() ?? 0
        fretCount = max(minimumFrets, highest, barreHighest)
        baseFret = max(shape.baseFret, 1)
        self.capoFret = capoFret.flatMap { $0 > 0 ? $0 : nil }
    }

    /// Room either side of the grid for the base-fret label (kept symmetric so the grid
    /// centres under the name).
    var sideMargin: CGFloat {
        max(metrics.stringGap, metrics.labelSize * 2.3).rounded(.up)
    }

    /// Height of the open/muted marker row above the nut.
    var markerRowHeight: CGFloat {
        (metrics.markerSize * 2).rounded(.up)
    }

    /// Top of the first fret space (bottom edge of the nut or capo bar).
    var gridTop: CGFloat {
        markerRowHeight + metrics.nutWidth
    }

    var gridBottom: CGFloat {
        gridTop + CGFloat(fretCount) * metrics.fretGap
    }

    /// Caption row under the grid ("Capo 2").
    var captionHeight: CGFloat {
        capoFret == nil ? 0 : (metrics.labelSize * 1.9).rounded(.up)
    }

    var size: CGSize {
        CGSize(
            width: 2 * sideMargin + CGFloat(stringCount - 1) * metrics.stringGap,
            height: gridBottom + metrics.lineWidth + (metrics.dotSize / 4).rounded(.up)
                + captionHeight,
        )
    }

    func stringX(_ string: Int) -> CGFloat {
        sideMargin + CGFloat(string) * metrics.stringGap
    }

    func fretLineY(_ line: Int) -> CGFloat {
        gridTop + CGFloat(line) * metrics.fretGap
    }

    /// Centre of a note on `string` at relative fret `fret` (1 = first space).
    func noteCentre(string: Int, fret: Int) -> CGPoint {
        CGPoint(x: stringX(string), y: gridTop + (CGFloat(fret) - 0.5) * metrics.fretGap)
    }

    func markerCentre(string: Int) -> CGPoint {
        CGPoint(x: stringX(string), y: (markerRowHeight / 2).rounded())
    }

    /// The string and relative fret under `point` (`fret` 0 = the marker row).
    func cell(at point: CGPoint) -> (string: Int, fret: Int)? {
        let string = Int(((point.x - sideMargin) / metrics.stringGap).rounded())
        guard (0 ..< stringCount).contains(string), point.y <= gridBottom else { return nil }
        if point.y < gridTop {
            return (string, 0)
        }
        let fret = Int(((point.y - gridTop) / metrics.fretGap).rounded(.down)) + 1
        return (string, min(max(fret, 1), fretCount))
    }
}

/// Draws a guitar diagram into a `Canvas`.
private struct GuitarDiagramRenderer {
    let geometry: GuitarDiagramGeometry
    let shape: GuitarShape

    private var metrics: DiagramMetrics {
        geometry.metrics
    }

    func draw(in context: inout GraphicsContext) {
        drawGrid(in: &context)
        drawNutOrCapo(in: &context)
        drawBarres(in: &context)
        drawNotes(in: &context)
        drawMarkers(in: &context)
        drawLabels(in: &context)
    }

    private func drawGrid(in context: inout GraphicsContext) {
        var grid = Path()
        let left = geometry.stringX(0)
        let right = geometry.stringX(geometry.stringCount - 1)
        for line in 0 ... geometry.fretCount {
            let y = geometry.fretLineY(line)
            grid.move(to: CGPoint(x: left, y: y))
            grid.addLine(to: CGPoint(x: right, y: y))
        }
        for string in 0 ..< geometry.stringCount {
            let x = geometry.stringX(string)
            grid.move(to: CGPoint(x: x, y: geometry.gridTop))
            grid.addLine(to: CGPoint(x: x, y: geometry.gridBottom))
        }
        context.stroke(
            grid,
            with: .color(Theme.color.muted),
            style: StrokeStyle(lineWidth: metrics.lineWidth, lineCap: .square),
        )
    }

    /// The nut (open position), replaced by a capo bar that overhangs the outer strings
    /// when a capo is set. Up the neck there is no nut: the base-fret label says where.
    private func drawNutOrCapo(in context: inout GraphicsContext) {
        guard geometry.baseFret == 1 else { return }
        let left = geometry.stringX(0)
        let right = geometry.stringX(geometry.stringCount - 1)
        let bottom = geometry.gridTop
        if geometry.capoFret != nil {
            let overhang = (metrics.stringGap * 0.45).rounded()
            let height = (metrics.nutWidth * 1.5).rounded()
            let bar = CGRect(
                x: left - overhang,
                y: bottom - height + metrics.lineWidth / 2,
                width: right - left + 2 * overhang,
                height: height,
            )
            context.fill(
                Path(roundedRect: bar, cornerRadius: height / 2),
                with: .color(Theme.color.ink),
            )
        } else {
            let half = metrics.lineWidth / 2
            let nut = CGRect(
                x: left - half,
                y: bottom - metrics.nutWidth + half,
                width: right - left + metrics.lineWidth,
                height: metrics.nutWidth,
            )
            context.fill(Path(nut), with: .color(Theme.color.ink))
        }
    }

    private func drawBarres(in context: inout GraphicsContext) {
        for barre in shape.barres where barre.fret >= 1 {
            let first = max(barre.strings.lowerBound, 0)
            let last = min(barre.strings.upperBound, geometry.stringCount - 1)
            guard first <= last else { continue }
            let centre = geometry.noteCentre(string: first, fret: barre.fret)
            let radius = metrics.dotSize / 2
            let rect = CGRect(
                x: geometry.stringX(first) - radius,
                y: centre.y - radius,
                width: geometry.stringX(last) - geometry.stringX(first) + metrics.dotSize,
                height: metrics.dotSize,
            )
            context.fill(
                Path(roundedRect: rect, cornerRadius: radius),
                with: .color(Theme.color.ink),
            )
            if metrics.showsFingers, let finger = barre.finger {
                drawFinger(finger, at: centre, in: &context)
            }
        }
    }

    private func drawNotes(in context: inout GraphicsContext) {
        for (string, fret) in shape.frets.enumerated() where string < geometry.stringCount {
            guard let fret, fret >= 1 else { continue }
            let underBarre = shape.barres
                .contains { $0.fret == fret && $0.strings.contains(string) }
            guard !underBarre else { continue }
            let centre = geometry.noteCentre(string: string, fret: fret)
            let radius = metrics.dotSize / 2
            context.fill(
                Path(ellipseIn: CGRect(
                    x: centre.x - radius,
                    y: centre.y - radius,
                    width: metrics.dotSize,
                    height: metrics.dotSize,
                )),
                with: .color(Theme.color.ink),
            )
            if metrics.showsFingers, string < shape.fingers.count,
               let finger = shape.fingers[string]
            {
                drawFinger(finger, at: centre, in: &context)
            }
        }
    }

    private func drawFinger(_ finger: Int, at centre: CGPoint, in context: inout GraphicsContext) {
        let text = Text(String(finger))
            .font(SchibstedGrotesk.bold.font(size: (metrics.dotSize * 0.68).rounded()))
            .foregroundStyle(Theme.color.ground)
        context.draw(text, at: centre, anchor: .center)
    }

    /// Open strings get a ring, muted strings a cross, above the nut.
    private func drawMarkers(in context: inout GraphicsContext) {
        let half = metrics.markerSize / 2
        let stroke = max(metrics.lineWidth, metrics.markerSize / 6)
        for string in 0 ..< geometry.stringCount {
            let centre = geometry.markerCentre(string: string)
            let fret = string < shape.frets.count ? shape.frets[string] : nil
            switch fret {
            case .none:
                var cross = Path()
                cross.move(to: CGPoint(x: centre.x - half, y: centre.y - half))
                cross.addLine(to: CGPoint(x: centre.x + half, y: centre.y + half))
                cross.move(to: CGPoint(x: centre.x + half, y: centre.y - half))
                cross.addLine(to: CGPoint(x: centre.x - half, y: centre.y + half))
                context.stroke(
                    cross,
                    with: .color(Theme.color.muted),
                    style: StrokeStyle(lineWidth: stroke, lineCap: .round),
                )
            case 0:
                let inset = stroke / 2
                let ring = CGRect(
                    x: centre.x - half + inset,
                    y: centre.y - half + inset,
                    width: metrics.markerSize - stroke,
                    height: metrics.markerSize - stroke,
                )
                context.stroke(
                    Path(ellipseIn: ring),
                    with: .color(Theme.color.ink),
                    lineWidth: stroke,
                )
            default:
                continue
            }
        }
    }

    /// "5fr" beside the first fret space up the neck; "Capo 2" under the grid.
    private func drawLabels(in context: inout GraphicsContext) {
        let font = SchibstedGrotesk.semiBold.font(size: metrics.labelSize)
        if geometry.baseFret > 1 {
            let centre = geometry.noteCentre(string: 0, fret: 1)
            let label = Text("\(geometry.baseFret)fr", bundle: #bundle).font(font)
                .foregroundStyle(Theme.color.muted)
            context.draw(
                label,
                at: CGPoint(x: centre.x - metrics.dotSize / 2 - 3, y: centre.y),
                anchor: .trailing,
            )
        }
        if let capo = geometry.capoFret {
            let label = Text("Capo \(capo)", bundle: #bundle).font(font)
                .foregroundStyle(Theme.color.muted)
            let x = (geometry.stringX(0) + geometry.stringX(geometry.stringCount - 1)) / 2
            context.draw(
                label,
                at: CGPoint(x: x, y: geometry.size.height),
                anchor: .bottom,
            )
        }
    }
}
