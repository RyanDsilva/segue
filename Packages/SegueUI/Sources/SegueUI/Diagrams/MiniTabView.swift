// P8-7d (docs/phases/8-workstreams/P8-7-time-model-and-fills.md sections 12.6, 12.8, 14.2): the
// mini tab of a fill, drawn from the pure `TabLayout` at the view's own width. The fill editor
// shows it full width; the stage draws the same layout as a block.

import AppKit
import Diagrams
import Editing
import LiveLayout
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
    /// The glyph size: 10 pt in the fill editor; a chart or the stage draws a fill at its
    /// walk-up run size, every metric scaled with it (P8-7 14.2).
    var size: Double = PlacedFillTab.baseSize
    var identifier = AccessibilityID.fillMiniTab

    /// A saved fill's tab on a chart or the stage.
    init(block: FillTabBlock, size: Double, identifier: String) {
        notes = block.notes
        chords = block.chords.map { (tick: $0.tick, name: $0.name) }
        ticks = block.ticks
        pulses = block.pulses
        bars = block.bars
        tuning = block.tuning
        self.size = size
        self.identifier = identifier
    }

    init(
        notes: [TabNote],
        chords: [(tick: Int, name: String)],
        ticks: Range<Int>,
        pulses: [Int],
        bars: [Int],
        tuning: Tuning,
    ) {
        self.notes = notes
        self.chords = chords
        self.ticks = ticks
        self.pulses = pulses
        self.bars = bars
        self.tuning = tuning
    }

    private var metrics: TabLayout.Metrics {
        PlacedFillTab.metrics(scale: size / PlacedFillTab.baseSize)
    }

    /// The face every label, fret and chord name is measured and drawn in: semibold with
    /// tabular digits (10 pt by default), so frets line up and layout and drawing agree.
    static func nsFont(size: Double = PlacedFillTab.baseSize) -> NSFont {
        _ = FontRegistration.registerBundledFonts()
        let base = NSFont(name: SchibstedGrotesk.semiBold.rawValue, size: size)
            ?? .systemFont(ofSize: size, weight: .semibold)
        let tabular = base.fontDescriptor.addingAttributes([
            .featureSettings: [[
                NSFontDescriptor.FeatureKey.typeIdentifier: kNumberSpacingType,
                NSFontDescriptor.FeatureKey.selectorIdentifier: kMonospacedNumbersSelector,
            ]],
        ])
        return NSFont(descriptor: tabular, size: size) ?? base
    }

    /// The layout at `width`, measured in `font` (what the view draws; this view's size
    /// when nil).
    func layout(width: Double, font: NSFont? = nil) -> TabLayout {
        let font = font ?? Self.nsFont(size: size)
        return TabLayout.layout(
            notes: notes,
            chords: chords,
            ticks: ticks,
            pulses: pulses,
            bars: bars,
            tuning: tuning,
            width: width,
            metrics: metrics,
        ) { text in
            Double((text as NSString).size(withAttributes: [.font: font]).width)
        }
    }

    /// The tab's height for a tuning at `size` (it does not depend on the width).
    static func height(for tuning: Tuning, size: Double = PlacedFillTab.baseSize) -> CGFloat {
        CGFloat(PlacedFillTab.baseHeight(for: tuning) * size / PlacedFillTab.baseSize)
    }

    var body: some View {
        GeometryReader { proxy in
            let font = Self.nsFont(size: size)
            let layout = layout(width: Double(proxy.size.width), font: font)
            let face = Font(font as CTFont)
            let metrics = metrics
            Canvas { context, _ in
                Self.draw(layout, face: face, metrics: metrics, in: &context)
            }
        }
        .frame(height: Self.height(for: tuning, size: size))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(TabLayout.spoken(notes, tuning: tuning))
        .accessibilityIdentifier(identifier)
    }

    private static func draw(
        _ layout: TabLayout,
        face: Font,
        metrics: TabLayout.Metrics,
        in context: inout GraphicsContext,
    ) {
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
        let tickLength = metrics.tickLength
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
