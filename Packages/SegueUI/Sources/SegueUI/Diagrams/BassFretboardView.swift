// P8-4b (docs/phases/8-workstreams/P8-4-bass.md section 7.2, R166). A bass fretboard cell for
// the editor's diagram strip: every chord tone on frets 0-12 labelled by degree, the note to
// play strongest and its suggested position filled.

import Diagrams
import Editing
import Library
import SwiftUI

/// A horizontal neck (tab orientation: lowest string at the bottom), frets 0 ... 12.
struct BassFretboardView: View {
    let diagram: BassDiagram
    let size: DiagramSize

    private var fretWidth: CGFloat {
        size == .compact ? 15 : 19
    }

    /// Far enough apart that labelled dots on neighbouring strings never touch.
    private var stringGap: CGFloat {
        let five = diagram.tuning.strings.count == 5
        return size == .compact ? (five ? 9 : 10) : (five ? 11 : 12)
    }

    private var dotSize: CGFloat {
        stringGap - 1
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
            .frame(width: neckWidth + 8, height: neckHeight + dotSize + 22)
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
        let inlayY = y(0) + dotSize / 2 + 4
        for fret in [3, 5, 7, 9] {
            dot(&context, at: CGPoint(x: x(fret), y: inlayY), diameter: 3, color: Theme.color.line)
        }
        dot(&context, at: CGPoint(x: x(12) - 2.5, y: inlayY), diameter: 3, color: Theme.color.line)
        dot(&context, at: CGPoint(x: x(12) + 2.5, y: inlayY), diameter: 3, color: Theme.color.line)
        // Every chord tone labelled by degree; the note to play strongest (R166).
        for tone in diagram.tones {
            mark(&context, tone)
        }
        if let suggested = diagram.suggested {
            let label = Text("\(suggested.fret)")
                .font(SchibstedGrotesk.semiBold.font(size: 9))
                .foregroundStyle(Theme.color.muted)
            context.draw(label, at: CGPoint(x: x(suggested.fret), y: inlayY + 8))
        }
    }

    /// One tone: the suggested place filled cue, the note's other places cue rings, a slash
    /// chord's root an ink ring, other tones muted rings; the degree centred in each.
    private func mark(_ context: inout GraphicsContext, _ tone: NeckTone) {
        let center = point(tone.position)
        let rect = CGRect(
            x: center.x - dotSize / 2,
            y: center.y - dotSize / 2,
            width: dotSize,
            height: dotSize,
        )
        let played = tone.position == diagram.suggested
        let (stroke, text): (Color, Color) = switch tone.role {
        case .bass: (Theme.color.cue, played ? Theme.color.ground : Theme.color.cueText)
        case .root: (Theme.color.ink, Theme.color.ink)
        case .tone: (Theme.color.muted, Theme.color.muted)
        }
        if played {
            context.fill(Path(ellipseIn: rect), with: .color(Theme.color.cue))
        } else {
            context.fill(Path(ellipseIn: rect), with: .color(Theme.color.ground))
            context.stroke(
                Path(ellipseIn: rect.insetBy(dx: 0.5, dy: 0.5)),
                with: .color(stroke),
                lineWidth: 1,
            )
        }
        let size = dotSize * 0.68 - (tone.degree.count > 2 ? 1 : 0)
        context.draw(
            Text(tone.degree)
                .font(SchibstedGrotesk.bold.font(size: size))
                .foregroundStyle(text),
            at: CGPoint(x: center.x, y: center.y + 0.3),
            anchor: .center,
        )
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

    /// "B, play on the A string fret 2; also E string fret 7, G string fret 4; chord tones
    /// R, 5".
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
        var degrees: [String] = []
        for tone in diagram.tones where tone.role != .bass && !degrees.contains(tone.degree) {
            degrees.append(tone.degree)
        }
        if !degrees.isEmpty {
            parts.append("chord tones " + degrees.joined(separator: ", "))
        }
        return parts.joined(separator: "; ")
    }
}
