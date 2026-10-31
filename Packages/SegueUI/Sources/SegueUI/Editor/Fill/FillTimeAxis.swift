// P8-7d (docs/phases/8-workstreams/P8-7-time-model-and-fills.md sections 12.4, 12.5). The time
// axis the step grid and the piano roll share: the same columns, ruler and chord names, so
// a note sits at the same x in both views.

import SwiftUI

struct FillTimeAxis: Equatable {
    var region: Range<Int>
    /// Points per tick.
    var scale: CGFloat
    /// The label column's width (string names, note names).
    var inset: CGFloat

    /// A sixteenth is never narrower than 16 pt; a short fill stretches to fill the width.
    static func make(region: Range<Int>, width: CGFloat, inset: CGFloat) -> Self {
        let ticks = CGFloat(max(1, region.count))
        let fit = (width - inset - 12) / ticks
        return Self(region: region, scale: max(16.0 / 120.0, fit), inset: inset)
    }

    func x(_ tick: Int) -> CGFloat {
        inset + CGFloat(tick - region.lowerBound) * scale
    }

    func tick(atX x: CGFloat) -> Int {
        region.lowerBound + Int(((x - inset) / scale).rounded(.down))
    }

    var width: CGFloat {
        x(region.upperBound) + 12
    }

    static let rulerHeight: CGFloat = 30

    /// The ruler above both views: chord names at their onsets, bar numbers, beat ticks.
    static func drawRuler(
        _ context: inout GraphicsContext,
        axis: Self,
        grid: FillGrid,
        width: CGFloat,
    ) {
        for bar in grid.bars {
            let x = axis.x(bar.tick)
            context.draw(
                Text("\(bar.number)")
                    .font(SchibstedGrotesk.semiBold.font(size: 10))
                    .foregroundStyle(Theme.color.muted),
                at: CGPoint(x: x + 3, y: 6),
                anchor: .leading,
            )
        }
        for (index, chord) in grid.chords.enumerated() where grid.region.contains(chord.onset)
            || index == 0
        {
            let x = axis.x(max(chord.onset, grid.region.lowerBound))
            let landing = index == grid.chords.count - 1
            let label = Text(chord.name)
                .font(SchibstedGrotesk.bold.font(size: 13))
                .foregroundStyle(landing ? Theme.color.cueText : Theme.color.ink)
            context.draw(label, at: CGPoint(x: x + 3, y: 20), anchor: .leading)
        }
        var base = Path()
        base.move(to: CGPoint(x: axis.inset, y: rulerHeight - 0.5))
        base.addLine(to: CGPoint(x: width, y: rulerHeight - 0.5))
        context.stroke(base, with: .color(Theme.color.line), lineWidth: 1)
    }

    /// Step, beat and bar lines over `rows` (top ... bottom).
    static func drawColumns(
        _ context: inout GraphicsContext,
        axis: Self,
        grid: FillGrid,
        rhythm: FillRhythmSnap,
        rows: ClosedRange<CGFloat>,
    ) {
        let top = rows.lowerBound
        let bottom = rows.upperBound
        let bars = Set(grid.bars.map(\.tick))
        let pulses = Set(grid.pulses)
        for tick in grid.columns(rhythm) {
            let x = axis.x(tick).rounded() + 0.5
            var line = Path()
            line.move(to: CGPoint(x: x, y: top))
            line.addLine(to: CGPoint(x: x, y: bottom))
            let color = bars.contains(tick) ? Theme.color.lineStrong
                : pulses.contains(tick) ? Theme.color.line : Theme.color.line.opacity(0.45)
            context.stroke(line, with: .color(color), lineWidth: bars.contains(tick) ? 1.5 : 1)
        }
        // Each span chord's onset, a little stronger, so the chords read as regions.
        for chord in grid.chords.dropFirst() where grid.region.contains(chord.onset) {
            let x = axis.x(chord.onset).rounded() + 0.5
            var line = Path()
            line.move(to: CGPoint(x: x, y: top))
            line.addLine(to: CGPoint(x: x, y: bottom))
            context.stroke(line, with: .color(Theme.color.cue.opacity(0.45)), lineWidth: 1)
        }
    }

    /// The playhead while the sheet plays.
    static func drawPlayhead(
        _ context: inout GraphicsContext,
        axis: Self,
        tick: Int?,
        height: CGFloat,
    ) {
        guard let tick, axis.region.contains(tick) else { return }
        let x = axis.x(tick)
        var line = Path()
        line.move(to: CGPoint(x: x, y: 0))
        line.addLine(to: CGPoint(x: x, y: height))
        context.stroke(line, with: .color(Theme.color.cue), lineWidth: 1.5)
    }
}
