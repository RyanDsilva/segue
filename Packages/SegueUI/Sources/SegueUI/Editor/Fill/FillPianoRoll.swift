// P8-7d (docs/phases/8-workstreams/P8-7-time-model-and-fills.md sections 12.5, 12.8). The other
// view: time across (the grid's columns, ruler and chord names), one row per semitone over
// the tuning's bass range with note names on the left, rows tinted per chord column (its
// tones strong, its passing scale light). Click to add (pitch snaps, ⌥ bypasses), drag to
// move, drag the right edge to resize, ⌥-drag to copy.

import AppKit
import MusicTheory
import SwiftUI

struct FillPianoRoll: View {
    let model: FillEditorModel
    @State private var drag: FillNoteDrag?
    @State private var dragSemitones = 0
    /// How far the roll is scrolled across (the pinned ruler follows it).
    @State private var scrolledX: CGFloat = 0

    static let rowHeight: CGFloat = 13
    static let inset: CGFloat = 44

    private var rows: ClosedRange<Int> {
        model.grid.rollRange
    }

    private var height: CGFloat {
        FillTimeAxis.rulerHeight + Self.rowHeight * CGFloat(rows.count) + 4
    }

    var body: some View {
        GeometryReader { proxy in
            let axis = FillTimeAxis.make(
                region: model.grid.region,
                width: proxy.size.width,
                inset: Self.inset,
            )
            ScrollView([.horizontal, .vertical]) {
                TimelineView(.animation(paused: model.sounding == nil)) { _ in
                    Canvas { context, _ in
                        draw(&context, axis: axis)
                    }
                }
                .frame(width: max(axis.width, proxy.size.width), height: height)
                .contentShape(Rectangle())
                .gesture(dragGesture(axis))
                .overlay(alignment: .topLeading) { notesForAccessibility(axis) }
            }
            // Opens on the span's bass notes, not the top of the range.
            .defaultScrollAnchor(UnitPoint(x: 0, y: anchorFraction(proxy.size.height)))
            .onScrollGeometryChange(for: CGFloat.self) { $0.contentOffset.x } action: { _, new in
                scrolledX = new
            }
            // The ruler and chord names stay in view as the rows scroll.
            .overlay(alignment: .topLeading) {
                Canvas { context, _ in
                    context.translateBy(x: -scrolledX, y: 0)
                    FillTimeAxis.drawRuler(
                        &context,
                        axis: axis,
                        grid: model.grid,
                        width: axis.width,
                    )
                }
                .frame(height: FillTimeAxis.rulerHeight)
                .background(Theme.color.ground)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(uiString("Piano roll"))
        .accessibilityIdentifier(AccessibilityID.fillPianoRoll)
    }

    /// Where the first chord's placed bass sits in the scrolled height.
    private func anchorFraction(_ visible: CGFloat) -> CGFloat {
        let center = y(model.grid.chords.first?.placed ?? rows.lowerBound) - visible / 2 + 40
        let travel = max(1, height - visible)
        return min(max(center / travel, 0), 1)
    }

    private func y(_ midi: Int) -> CGFloat {
        FillTimeAxis.rulerHeight + Self.rowHeight * CGFloat(rows.upperBound - midi)
    }

    private func midi(atY point: CGFloat) -> Int {
        rows.upperBound - Int(((point - FillTimeAxis.rulerHeight) / Self.rowHeight).rounded(.down))
    }

    // MARK: Drawing

    private func draw(_ context: inout GraphicsContext, axis: FillTimeAxis) {
        let grid = model.grid
        FillTimeAxis.drawRuler(&context, axis: axis, grid: grid, width: axis.width)
        drawTints(&context, axis: axis)
        drawKeys(&context, axis: axis)
        FillTimeAxis.drawColumns(
            &context,
            axis: axis,
            grid: grid,
            rhythm: model.rhythm,
            rows: FillTimeAxis.rulerHeight ... height - 4,
        )
        for note in model.draft.notes {
            drawNote(&context, note, axis: axis)
        }
        FillTimeAxis.drawPlayhead(&context, axis: axis, tick: model.playheadTick, height: height)
    }

    /// Per chord column: its tones strong, its passing scale light.
    private func drawTints(_ context: inout GraphicsContext, axis: FillTimeAxis) {
        let grid = model.grid
        for (index, chord) in grid.chords.enumerated() {
            let start = max(chord.onset, grid.region.lowerBound)
            let end = index + 1 < grid.chords.count
                ? grid.chords[index + 1].onset : grid.region.upperBound
            guard end > start else { continue }
            let tones = grid.allowed(.chordTones, chord: index) ?? []
            let scale = grid.allowed(.scale, chord: index) ?? []
            for midi in rows {
                let pitch = PitchClass(midi: midi)
                let color: Color? = tones.contains(pitch) ? Theme.color.cue.opacity(0.12)
                    : scale.contains(pitch) ? Theme.color.ink.opacity(0.05) : nil
                guard let color else { continue }
                context.fill(
                    Path(CGRect(
                        x: axis.x(start),
                        y: y(midi),
                        width: axis.x(end) - axis.x(start),
                        height: Self.rowHeight,
                    )),
                    with: .color(color),
                )
            }
        }
    }

    /// Keys on the left, row lines between octaves.
    private func drawKeys(_ context: inout GraphicsContext, axis: FillTimeAxis) {
        let names = [
            "C",
            "C\u{266F}",
            "D",
            "D\u{266F}",
            "E",
            "F",
            "F\u{266F}",
            "G",
            "G\u{266F}",
            "A",
            "A\u{266F}",
            "B",
        ]
        let black: Set = [1, 3, 6, 8, 10]
        for midi in rows {
            let pc = ((midi % 12) + 12) % 12
            let rect = CGRect(x: 0, y: y(midi), width: Self.inset - 4, height: Self.rowHeight)
            context.fill(Path(rect), with: .color(black.contains(pc)
                    ? Theme.color.surfaceAlt : Theme.color.ground))
            if !black.contains(pc) {
                context.draw(
                    Text(names[pc] + (pc == 0 ? "\(midi / 12 - 1)" : ""))
                        .font(SchibstedGrotesk.semiBold.font(size: 9))
                        .foregroundStyle(pc == 0 ? Theme.color.ink : Theme.color.muted),
                    at: CGPoint(x: Self.inset - 8, y: rect.midY),
                    anchor: .trailing,
                )
            }
            if pc == 0 || pc == 5 {
                var line = Path()
                line.move(to: CGPoint(x: Self.inset, y: rect.maxY - 0.5))
                line.addLine(to: CGPoint(x: axis.width, y: rect.maxY - 0.5))
                context.stroke(
                    line,
                    with: .color(Theme.color.line.opacity(pc == 0 ? 1 : 0.5)),
                    lineWidth: 1,
                )
            }
        }
    }

    private func drawNote(
        _ context: inout GraphicsContext,
        _ note: FillDraft.Note,
        axis: FillTimeAxis,
    ) {
        let grid = model.grid
        var start = grid.tick(of: note.event)
        var midi = grid.midi(of: note.event)
        var length = note.event.len
        if let drag {
            if drag.ids.contains(note.id) {
                start += drag.ticks
                midi += dragSemitones
            } else if drag.resizing == note.id {
                length = max(model.rhythm.ticks, length + drag.ticks)
            }
        }
        let rect = CGRect(
            x: axis.x(start) + 1,
            y: y(midi) + 1,
            width: max(8, CGFloat(length) * axis.scale - 2),
            height: Self.rowHeight - 2,
        )
        let selected = model.draft.selection.contains(note.id)
        let shape = Path(roundedRect: rect, cornerRadius: 3)
        let fill = selected ? Theme.color.cue : Theme.color.cue.opacity(0.55)
        context.fill(shape, with: .color(fill))
        if grid.isOutside(note.event) {
            context.stroke(
                shape,
                with: .color(Theme.color.cueText),
                style: StrokeStyle(lineWidth: 1, dash: [3, 2]),
            )
        }
        if rect.width > 26 {
            context.draw(
                Text(FillNoteLabels.prefix(note.event.articulations) + model.name(of: note))
                    .font(SchibstedGrotesk.bold.font(size: 9))
                    .foregroundStyle(Theme.color.ground),
                at: CGPoint(x: rect.minX + 4, y: rect.midY),
                anchor: .leading,
            )
        }
    }

    // MARK: Gestures

    private func dragGesture(_ axis: FillTimeAxis) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                if drag == nil {
                    drag = FillNoteDrag.begin(
                        at: value.startLocation,
                        hit: hit(value.startLocation, axis: axis),
                        selection: model.draft.selection,
                        extending: NSEvent.modifierFlags.contains(.shift),
                    )
                }
                drag?.update(value.translation.width, axis: axis, rhythm: model.rhythm)
                dragSemitones = drag?.resizing == nil
                    ? -Int((value.translation.height / Self.rowHeight).rounded()) : 0
                if abs(value.translation.height) > 3 {
                    drag?.moved = true
                }
            }
            .onEnded { value in
                defer {
                    drag = nil
                    dragSemitones = 0
                }
                guard let current = drag else { return }
                let bypass = NSEvent.modifierFlags.contains(.option)
                if !current.moved {
                    guard value.startLocation.y > FillTimeAxis.rulerHeight,
                          value.startLocation.x > Self.inset
                    else { return }
                    let tick = model.grid.snap(
                        axis.tick(atX: value.startLocation.x),
                        to: model.rhythm,
                    )
                    model.tapRoll(
                        tick: tick,
                        midi: midi(atY: value.startLocation.y),
                        note: current.hit?.id,
                        extending: NSEvent.modifierFlags.contains(.shift),
                        bypass: bypass,
                    )
                } else {
                    model.finishRoll(current, rawSemitones: dragSemitones, bypass: bypass)
                }
            }
    }

    private func hit(_ point: CGPoint, axis: FillTimeAxis) -> (id: Int, edge: Bool)? {
        let grid = model.grid
        let pitch = midi(atY: point.y)
        for note in model.draft.notes where grid.midi(of: note.event) == pitch {
            let start = axis.x(grid.tick(of: note.event))
            let end = start + CGFloat(note.event.len) * axis.scale
            if point.x >= start, point.x <= end {
                return (note.id, point.x >= end - 5)
            }
        }
        return nil
    }

    // MARK: Accessibility

    /// Each note an element: "F sharp 2, bar 2 beat 4 and, an eighth".
    private func notesForAccessibility(_ axis: FillTimeAxis) -> some View {
        let grid = model.grid
        return ZStack(alignment: .topLeading) {
            ForEach(model.draft.ordered(on: grid)) { note in
                let tick = grid.tick(of: note.event)
                Color.clear
                    .frame(
                        width: max(8, CGFloat(note.event.len) * axis.scale),
                        height: Self.rowHeight,
                    )
                    .offset(x: axis.x(tick), y: y(grid.midi(of: note.event)))
                    .accessibilityElement()
                    .accessibilityLabel(model.spokenRollNote(note))
                    .accessibilityAddTraits(.isButton)
                    .accessibilityAction { model.draft.selection = [note.id] }
                    .accessibilityAdjustableAction { direction in
                        model.draft.selection = [note.id]
                        model.transposeSelection(
                            by: direction == .increment ? 1 : -1,
                            octave: false,
                        )
                    }
                    .accessibilityActions {
                        Button(uiString("Lengthen")) {
                            model.draft.selection = [note.id]
                            model.lengthen(by: 1, in: .pianoRoll)
                        }
                        Button(uiString("Shorten")) {
                            model.draft.selection = [note.id]
                            model.lengthen(by: -1, in: .pianoRoll)
                        }
                        Button(uiString("Delete")) {
                            model.draft.delete([note.id], on: grid)
                        }
                    }
            }
        }
    }
}
