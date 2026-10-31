// P8-7d (docs/phases/8-workstreams/P8-7-time-model-and-fills.md sections 12.6, 12.8, 14.2): the
// mini tab of a fill, drawn from the pure `TabLayout` at the view's own width. The fill editor
// shows it full width; the stage draws the same layout as a block.

import AppKit
import Diagrams
import SwiftUI

/// A mini tab: string lines labelled G D A E (and B), frets placed by rhythm, beat ticks, bar
/// lines and chord names. One accessibility element reading the tab aloud.
struct MiniTabView: View {
    let notes: [TabNote]
    let chords: [(tick: Int, name: String)]
    let ticks: Range<Int>
    let pulses: [Int]
    let bars: [Int]
    let tuning: Tuning

    /// The face every label, fret and chord name is measured and drawn in: 10 pt semibold
    /// with tabular digits, so frets line up and layout and drawing agree.
    static func nsFont() -> NSFont {
        _ = FontRegistration.registerBundledFonts()
        let base = NSFont(name: SchibstedGrotesk.semiBold.rawValue, size: 10)
            ?? .systemFont(ofSize: 10, weight: .semibold)
        let tabular = base.fontDescriptor.addingAttributes([
            .featureSettings: [[
                NSFontDescriptor.FeatureKey.typeIdentifier: kNumberSpacingType,
                NSFontDescriptor.FeatureKey.selectorIdentifier: kMonospacedNumbersSelector,
            ]],
        ])
        return NSFont(descriptor: tabular, size: 10) ?? base
    }

    /// The layout at `width`, measured in `font` (what the view draws).
    func layout(width: Double, font: NSFont = nsFont()) -> TabLayout {
        TabLayout.layout(
            notes: notes,
            chords: chords,
            ticks: ticks,
            pulses: pulses,
            bars: bars,
            tuning: tuning,
            width: width,
        ) { text in
            Double((text as NSString).size(withAttributes: [.font: font]).width)
        }
    }

    /// The tab's height for a tuning (it does not depend on the width).
    static func height(for tuning: Tuning) -> CGFloat {
        CGFloat(TabLayout.layout(
            notes: [],
            chords: [],
            ticks: 0 ..< 1,
            pulses: [],
            bars: [],
            tuning: tuning,
            width: 0,
        ) { _ in 0 }.height)
    }

    var body: some View {
        GeometryReader { proxy in
            let font = Self.nsFont()
            let layout = layout(width: Double(proxy.size.width), font: font)
            let face = Font(font as CTFont)
            Canvas { context, _ in
                Self.draw(layout, face: face, in: &context)
            }
        }
        .frame(height: Self.height(for: tuning))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(TabLayout.spoken(notes, tuning: tuning))
        .accessibilityIdentifier(AccessibilityID.fillMiniTab)
    }

    private static func draw(_ layout: TabLayout, face: Font, in context: inout GraphicsContext) {
        let top = layout.lines.first?.y ?? 0
        let bottom = layout.lines.last?.y ?? 0
        for line in layout.lines {
            let label = CGPoint(x: line.labelX, y: line.y)
            text(&context, line.label, at: label, face: face, Theme.color.muted)
            for segment in line.segments {
                let start = CGPoint(x: segment.lowerBound, y: line.y)
                stroke(&context, from: start, to: CGPoint(x: segment.upperBound, y: line.y))
            }
        }
        for x in layout.barLines {
            let start = CGPoint(x: x, y: top)
            stroke(&context, from: start, to: CGPoint(x: x, y: bottom), Theme.color.lineStrong)
        }
        let tickLength = TabLayout.Metrics().tickLength
        for x in layout.beatTicks {
            let start = CGPoint(x: x, y: layout.rulerY)
            let end = CGPoint(x: x, y: layout.rulerY + tickLength)
            stroke(&context, from: start, to: end, Theme.color.muted)
        }
        for chord in layout.chords {
            text(&context, chord.text, at: CGPoint(x: chord.x, y: chord.y), face: face)
        }
        for glyph in layout.glyphs {
            let color = glyph.isLanding ? Theme.color.cueText
                : glyph.string == nil ? Theme.color.muted : Theme.color.ink
            text(&context, glyph.text, at: CGPoint(x: glyph.x, y: glyph.y), face: face, color)
        }
        for mark in layout.marks {
            text(&context, mark.text, at: CGPoint(x: mark.x, y: mark.y), face: face)
        }
    }

    /// `string` drawn from its leading edge, vertically centred on `point.y`.
    private static func text(
        _ context: inout GraphicsContext,
        _ string: String,
        at point: CGPoint,
        face: Font,
        _ color: Color = Theme.color.ink,
    ) {
        context.draw(Text(string).font(face).foregroundStyle(color), at: point, anchor: .leading)
    }

    private static func stroke(
        _ context: inout GraphicsContext,
        from start: CGPoint,
        to end: CGPoint,
        _ color: Color = Theme.color.line,
    ) {
        var path = Path()
        path.move(to: start)
        path.addLine(to: end)
        context.stroke(path, with: .color(color), lineWidth: 1)
    }
}
