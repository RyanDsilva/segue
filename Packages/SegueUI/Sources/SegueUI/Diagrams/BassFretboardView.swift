// P8-4b (docs/phases/8-workstreams/P8-4-bass.md section 7.2). A bass fretboard cell for the
// editor's diagram strip: the bass note's positions on frets 0-12, the suggested one filled,
// root-fifth-octave around it.

import Diagrams
import Editing
import Library
import SwiftUI

/// A horizontal neck (tab orientation: lowest string at the bottom), frets 0 ... 12.
struct BassFretboardView: View {
    let diagram: BassDiagram
    let size: DiagramSize

    private var fretWidth: CGFloat {
        size == .compact ? 9 : 12
    }

    private var stringGap: CGFloat {
        let strings = diagram.tuning.strings.count
        return (size == .compact ? 22 : 30) / CGFloat(max(strings - 1, 1))
    }

    private var neckWidth: CGFloat {
        fretWidth * CGFloat(BassFretboard.maxFret) + fretWidth
    }

    private var neckHeight: CGFloat {
        stringGap * CGFloat(diagram.tuning.strings.count - 1)
    }

    var body: some View {
        VStack(spacing: 2) {
            Text(diagram.note)
                .font(SchibstedGrotesk.bold.font(size: size == .compact ? 15 : 18))
                .foregroundStyle(Theme.color.ink)
            Text(diagram.chordName)
                .font(SchibstedGrotesk.medium.font(size: size == .compact ? 10 : 12))
                .foregroundStyle(Theme.color.muted)
            Canvas { context, _ in
                draw(in: &context)
            }
            .frame(width: neckWidth + 8, height: neckHeight + 22)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Self.spoken(diagram))
    }

    /// The x of a fret's dot (the open string sits left of the nut).
    private func x(_ fret: Int) -> CGFloat {
        4 + (CGFloat(fret) + 0.5) * fretWidth
    }

    /// The y of a string, lowest at the bottom.
    private func y(_ string: Int) -> CGFloat {
        5 + neckHeight - CGFloat(string) * stringGap
    }

    private func draw(in context: inout GraphicsContext) {
        let strings = diagram.tuning.strings.count
        // Strings.
        for string in 0 ..< strings {
            var line = Path()
            line.move(to: CGPoint(x: 4 + fretWidth, y: y(string)))
            line.addLine(to: CGPoint(x: 4 + neckWidth, y: y(string)))
            context.stroke(line, with: .color(Theme.color.indicatorOff), lineWidth: 1)
        }
        // Frets, the nut thicker.
        for fret in 1 ... BassFretboard.maxFret + 1 {
            var wire = Path()
            let wireX = 4 + CGFloat(fret) * fretWidth
            wire.move(to: CGPoint(x: wireX, y: y(strings - 1)))
            wire.addLine(to: CGPoint(x: wireX, y: y(0)))
            context.stroke(wire, with: .color(Theme.color.line), lineWidth: fret == 1 ? 2 : 1)
        }
        // Inlay dots under the neck: 3, 5, 7, 9 and a double at 12.
        let inlayY = y(0) + 7
        for fret in [3, 5, 7, 9] {
            dot(&context, at: CGPoint(x: x(fret), y: inlayY), diameter: 3, color: Theme.color.line)
        }
        dot(&context, at: CGPoint(x: x(12) - 2.5, y: inlayY), diameter: 3, color: Theme.color.line)
        dot(&context, at: CGPoint(x: x(12) + 2.5, y: inlayY), diameter: 3, color: Theme.color.line)
        // Fifth and octave: small filled dots.
        // (An octave on one of the note's own positions is already its ring.)
        for position in diagram.shape where !diagram.positions.contains(position) {
            dot(&context, at: point(position), diameter: 4, color: Theme.color.muted)
        }
        // Every position of the note: hollow rings; the suggested one filled.
        let ring = size == .compact ? 6.0 : 8.0
        for position in diagram.positions where position != diagram.suggested {
            let rect = CGRect(
                x: point(position).x - ring / 2,
                y: point(position).y - ring / 2,
                width: ring,
                height: ring,
            )
            context.stroke(Path(ellipseIn: rect), with: .color(Theme.color.muted), lineWidth: 1)
        }
        if let suggested = diagram.suggested {
            dot(&context, at: point(suggested), diameter: ring + 1, color: Theme.color.cue)
            let label = Text("\(suggested.fret)")
                .font(SchibstedGrotesk.semiBold.font(size: 9))
                .foregroundStyle(Theme.color.muted)
            context.draw(label, at: CGPoint(x: x(suggested.fret), y: inlayY + 8))
        }
    }

    private func point(_ position: FretPosition) -> CGPoint {
        CGPoint(x: x(position.fret), y: y(position.string))
    }

    private func dot(
        _ context: inout GraphicsContext,
        at center: CGPoint,
        diameter: CGFloat,
        color: Color,
    ) {
        let rect = CGRect(
            x: center.x - diameter / 2,
            y: center.y - diameter / 2,
            width: diameter,
            height: diameter,
        )
        context.fill(Path(ellipseIn: rect), with: .color(color))
    }

    /// "B, play on the A string, fret 2; also E string fret 7, G string fret 4; fifth F
    /// sharp on the D string fret 4".
    static func spoken(_ diagram: BassDiagram) -> String {
        func string(_ position: FretPosition) -> String {
            let open = diagram.tuning.openStringName(position.string)
            return "\(BassLine.spokenNote(open)) string fret \(position.fret)"
        }
        var parts = [BassLine.spokenNote(diagram.note)]
        if let suggested = diagram.suggested {
            parts[0] += ", play on the \(string(suggested))"
        }
        let others = diagram.positions.filter { $0 != diagram.suggested }.map(string)
        if !others.isEmpty {
            parts.append("also " + others.joined(separator: ", "))
        }
        return parts.joined(separator: "; ")
    }
}
