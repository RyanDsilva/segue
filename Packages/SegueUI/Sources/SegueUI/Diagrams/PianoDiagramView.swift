// Owner: unit B (diagram views). Frozen interface: docs/phases/1-interfaces.md.

import Diagrams
import MusicTheory
import SwiftUI

/// Compact one-octave keyboard with chord tones highlighted, the root marked distinctly
/// and the bass note as a separate marker/label under the keyboard.
struct PianoDiagramView: View {
    let name: String
    let voicing: PianoVoicing
    var size: DiagramSize = .regular
    /// When set, keys are tappable (custom voicing editing); called with the tapped pitch
    /// class.
    var onToggleKey: ((PitchClass) -> Void)?

    var body: some View {
        let geometry = PianoDiagramGeometry(metrics: .forSize(size))
        VStack(spacing: geometry.metrics.nameSpacing) {
            DiagramNameLabel(name: name, metrics: geometry.metrics)
                .frame(maxWidth: geometry.size.width)
            PianoDiagramCanvas(geometry: geometry, voicing: voicing)
                .modifier(KeyTapModifier(isEnabled: onToggleKey != nil) { location in
                    if let key = geometry.pitchClass(at: location) {
                        onToggleKey?(key)
                    }
                })
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(uiString("\(name), piano"))
        .accessibilityValue(accessibilityValue)
        .accessibilityIdentifier(AccessibilityID.pianoDiagram)
    }

    /// "C E G, root C, bass C" with sharps for black keys.
    private var accessibilityValue: String {
        let names = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]
        var parts = [voicing.foldedPitchClasses.map { names[$0.rawValue] }.joined(separator: " ")]
        parts.append("root \(names[voicing.root.rawValue])")
        if let bass = voicing.bass {
            parts.append("bass \(names[PitchClass(midi: bass).rawValue])")
        }
        return parts.joined(separator: ", ")
    }
}

/// The drawn keyboard without its name, sized to its geometry.
struct PianoDiagramCanvas: View {
    let geometry: PianoDiagramGeometry
    let voicing: PianoVoicing

    var body: some View {
        Canvas { context, _ in
            PianoDiagramRenderer(geometry: geometry, voicing: voicing).draw(in: &context)
        }
        .frame(width: geometry.size.width, height: geometry.size.height)
        .contentShape(Rectangle())
    }
}

private struct KeyTapModifier: ViewModifier {
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

/// Where the keys sit, in points: seven white keys C ... B with the five black keys over
/// their boundaries, and a marker row underneath for the bass.
struct PianoDiagramGeometry {
    let metrics: DiagramMetrics

    /// Pitch classes of the white keys, left to right.
    static let whiteKeys = [0, 2, 4, 5, 7, 9, 11]
    /// Black-key pitch class -> the white-key boundary it straddles (1 = between C and D).
    static let blackKeys: [Int: Int] = [1: 1, 3: 2, 6: 4, 8: 5, 10: 6]

    var whiteWidth: CGFloat {
        metrics.whiteKeyWidth
    }

    var keyboardHeight: CGFloat {
        metrics.whiteKeyHeight
    }

    var blackWidth: CGFloat {
        (whiteWidth * 0.62).rounded()
    }

    var blackHeight: CGFloat {
        (keyboardHeight * 0.6).rounded()
    }

    /// Inset so the outline's hairline is not clipped by the frame.
    var inset: CGFloat {
        metrics.lineWidth
    }

    var bassRowHeight: CGFloat {
        (whiteWidth * 0.95).rounded(.up)
    }

    var size: CGSize {
        CGSize(
            width: 7 * whiteWidth + 2 * inset,
            height: keyboardHeight + 2 * inset + bassRowHeight,
        )
    }

    func whiteRect(_ index: Int) -> CGRect {
        CGRect(
            x: inset + CGFloat(index) * whiteWidth,
            y: inset,
            width: whiteWidth,
            height: keyboardHeight,
        )
    }

    func blackRect(boundary: Int) -> CGRect {
        CGRect(
            x: inset + CGFloat(boundary) * whiteWidth - blackWidth / 2,
            y: inset,
            width: blackWidth,
            height: blackHeight,
        )
    }

    func isBlack(_ pitchClass: PitchClass) -> Bool {
        Self.blackKeys[pitchClass.rawValue] != nil
    }

    /// The horizontal centre of a key.
    func keyCentreX(_ pitchClass: PitchClass) -> CGFloat {
        if let boundary = Self.blackKeys[pitchClass.rawValue] {
            return blackRect(boundary: boundary).midX
        }
        let index = Self.whiteKeys.firstIndex(of: pitchClass.rawValue) ?? 0
        return whiteRect(index).midX
    }

    /// Dot diameter for a chord tone on a white or black key.
    func dotSize(black: Bool) -> CGFloat {
        black ? (blackWidth * 0.86).rounded() : (whiteWidth * 0.6).rounded()
    }

    /// Centre of the tone dot on a key, near the key's front edge.
    func dotCentre(_ pitchClass: PitchClass) -> CGPoint {
        let black = isBlack(pitchClass)
        let bottom = black ? inset + blackHeight : inset + keyboardHeight
        let size = dotSize(black: black)
        return CGPoint(
            x: keyCentreX(pitchClass),
            y: bottom - size / 2 - (whiteWidth * 0.22).rounded(),
        )
    }

    /// The key under `point`; black keys win where they overlap white ones.
    func pitchClass(at point: CGPoint) -> PitchClass? {
        guard point.y <= inset + keyboardHeight else { return nil }
        for (key, boundary) in Self.blackKeys where blackRect(boundary: boundary).contains(point) {
            return PitchClass(key)
        }
        let index = Int(((point.x - inset) / whiteWidth).rounded(.down))
        guard Self.whiteKeys.indices.contains(index) else { return nil }
        return PitchClass(Self.whiteKeys[index])
    }
}

/// Draws the keyboard into a `Canvas`. Light: paper keys, ink black keys. Dark stage: the
/// keys stay dark (stage ground with `lineStrong` black keys) so a strip of diagrams never
/// glows, with light tone dots.
private struct PianoDiagramRenderer {
    let geometry: PianoDiagramGeometry
    let voicing: PianoVoicing

    func draw(in context: inout GraphicsContext) {
        let dark = context.environment.colorScheme == .dark
        let colors = Palette(dark: dark)
        let metrics = geometry.metrics
        let keyboard = CGRect(
            x: geometry.inset,
            y: geometry.inset,
            width: 7 * geometry.whiteWidth,
            height: geometry.keyboardHeight,
        )
        let radius = (geometry.whiteWidth * 0.2).rounded()
        let outline = Path(roundedRect: keyboard, cornerRadius: radius)
        context.fill(outline, with: .color(colors.whiteKey))

        var separators = Path()
        for index in 1 ..< 7 {
            let x = keyboard.minX + CGFloat(index) * geometry.whiteWidth
            separators.move(to: CGPoint(x: x, y: keyboard.minY))
            separators.addLine(to: CGPoint(x: x, y: keyboard.maxY))
        }
        context.stroke(separators, with: .color(colors.keyLine), lineWidth: metrics.lineWidth)

        let blackRadius = (geometry.blackWidth * 0.18).rounded()
        for boundary in PianoDiagramGeometry.blackKeys.values {
            let rect = geometry.blackRect(boundary: boundary)
            let key = Path(roundedRect: rect, cornerRadii: RectangleCornerRadii(
                bottomLeading: blackRadius,
                bottomTrailing: blackRadius,
            ))
            context.fill(key, with: .color(colors.blackKey))
            if dark {
                context.stroke(key, with: .color(colors.keyLine), lineWidth: metrics.lineWidth)
            }
        }
        context.stroke(outline, with: .color(colors.keyLine), lineWidth: metrics.lineWidth)

        drawTones(in: &context, colors: colors)
        drawBass(in: &context)
    }

    private func drawTones(in context: inout GraphicsContext, colors: Palette) {
        for pitchClass in voicing.foldedPitchClasses where pitchClass != voicing.root {
            let black = geometry.isBlack(pitchClass)
            fillDot(
                at: geometry.dotCentre(pitchClass),
                diameter: geometry.dotSize(black: black),
                color: black ? colors.toneOnBlack : Theme.color.ink,
                in: &context,
            )
        }
        // The root: a larger cue dot, distinct by lightness and size, not hue alone.
        guard voicing.foldedPitchClasses.contains(voicing.root) else { return }
        let black = geometry.isBlack(voicing.root)
        let diameter = (geometry.dotSize(black: black) * 1.2).rounded()
        let centre = geometry.dotCentre(voicing.root)
        fillDot(at: centre, diameter: diameter + 2, color: colors.halo(black: black), in: &context)
        fillDot(at: centre, diameter: diameter, color: Theme.color.cue, in: &context)
    }

    /// An upward caret under the bass note's key, apart from the keyboard.
    private func drawBass(in context: inout GraphicsContext) {
        guard let bass = voicing.bass else { return }
        let x = geometry.keyCentreX(PitchClass(midi: bass))
        let width = (geometry.whiteWidth * 0.62).rounded()
        let height = (width * 0.75).rounded()
        let top = geometry.inset + geometry.keyboardHeight
            + (geometry.bassRowHeight - height) / 2 + geometry.metrics.lineWidth
        var caret = Path()
        caret.move(to: CGPoint(x: x, y: top))
        caret.addLine(to: CGPoint(x: x + width / 2, y: top + height))
        caret.addLine(to: CGPoint(x: x - width / 2, y: top + height))
        caret.closeSubpath()
        context.fill(caret, with: .color(Theme.color.ink))
    }

    private func fillDot(
        at centre: CGPoint,
        diameter: CGFloat,
        color: Color,
        in context: inout GraphicsContext,
    ) {
        context.fill(
            Path(ellipseIn: CGRect(
                x: centre.x - diameter / 2,
                y: centre.y - diameter / 2,
                width: diameter,
                height: diameter,
            )),
            with: .color(color),
        )
    }

    /// Token choices per appearance.
    private struct Palette {
        let dark: Bool

        var whiteKey: Color {
            Theme.color.ground
        }

        var blackKey: Color {
            dark ? Theme.color.lineStrong : Theme.color.ink
        }

        var keyLine: Color {
            Theme.color.muted
        }

        /// Chord-tone dot on a black key: paper on ink (light), ink on grey (dark).
        var toneOnBlack: Color {
            dark ? Theme.color.ink : Theme.color.ground
        }

        /// A thin ring behind the root dot so it separates from the key edge.
        func halo(black: Bool) -> Color {
            black ? blackKey : whiteKey
        }
    }
}
