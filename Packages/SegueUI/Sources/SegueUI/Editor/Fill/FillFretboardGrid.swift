// P8-7d (docs/phases/8-workstreams/P8-7-time-model-and-fills.md sections 12.4, 12.8). The
// default view: a neck above (the profile's tuning, frets 0 ... 15, low string at the
// bottom, tinted by the chord under the cursor or selection) and a tab-style step grid below
// (one row per string, one column per snap step, each note a block labelled with its fret or
// name). Keyboard first, Guitar Pro style: arrows move the cursor, a digit types a fret,
// `+` / `-` change the length, `R` or Delete rests.

import AppKit
import Diagrams
import Library
import MusicTheory
import SwiftUI

struct FillFretboardGrid: View {
    let model: FillEditorModel
    let focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            FillNeck(model: model)
            FillStepGrid(model: model, focused: focused)
        }
    }
}

// MARK: - The neck

struct FillNeck: View {
    let model: FillEditorModel

    static let fretWidth: CGFloat = 34
    static let stringGap: CGFloat = 18
    static let frets = 15
    static let labelWidth: CGFloat = 22

    private var strings: Int {
        model.grid.tuning.strings.count
    }

    private var height: CGFloat {
        Self.stringGap * CGFloat(max(1, strings - 1)) + 30
    }

    private var width: CGFloat {
        Self.labelWidth + Self.fretWidth * CGFloat(Self.frets + 1) + 8
    }

    var body: some View {
        ScrollView(.horizontal) {
            Canvas { context, _ in
                draw(&context)
            }
            .frame(width: width, height: height)
            .contentShape(Rectangle())
            .gesture(SpatialTapGesture().onEnded { value in click(value.location) })
        }
        .scrollIndicators(.never)
        .frame(height: height)
        .accessibilityHidden(true)
        .accessibilityIdentifier(AccessibilityID.fillNeck)
    }

    private func x(_ fret: Int) -> CGFloat {
        Self.labelWidth + (CGFloat(fret) + 0.5) * Self.fretWidth
    }

    private func y(_ string: Int) -> CGFloat {
        8 + Self.stringGap * CGFloat(strings - 1 - string)
    }

    /// The chord the neck is tinted by: under the selected note, else the cursor.
    private var chordIndex: Int {
        let draft = model.draft
        if let id = draft.selection.first, let note = draft.note(id) {
            return model.grid.chord(atTick: model.grid.tick(of: note.event))
        }
        return model.grid.chord(atTick: draft.cursor.tick)
    }

    private var selectedPosition: FretPosition? {
        let draft = model.draft
        guard let id = draft.selection.first, let note = draft.note(id) else { return nil }
        return model.grid.position(of: note.event)
    }

    private func draw(_ context: inout GraphicsContext) {
        let grid = model.grid
        let cursorString = model.draft.cursor.string
        // Open string names.
        for string in 0 ..< strings {
            let name = grid.tuning.openStringName(string)
            context.draw(
                Text(name)
                    .font(SchibstedGrotesk.bold.font(size: 11))
                    .foregroundStyle(string == cursorString ? Theme.color.cueText
                        : Theme.color.muted),
                at: CGPoint(x: 8, y: y(string)),
                anchor: .center,
            )
        }
        // Strings, the cursor's stronger.
        for string in 0 ..< strings {
            var line = Path()
            line.move(to: CGPoint(x: Self.labelWidth + Self.fretWidth, y: y(string)))
            line.addLine(to: CGPoint(x: width - 8, y: y(string)))
            let isCursor = string == cursorString
            context.stroke(
                line,
                with: .color(isCursor ? Theme.color.cueText.opacity(0.6) : Theme.color.lineStrong),
                lineWidth: isCursor ? 1.5 : 1 + CGFloat(strings - 1 - string) * 0.0,
            )
        }
        // Frets, the nut thicker.
        for fret in 1 ... Self.frets + 1 {
            let wire = Self.labelWidth + CGFloat(fret) * Self.fretWidth
            var line = Path()
            line.move(to: CGPoint(x: wire, y: y(strings - 1)))
            line.addLine(to: CGPoint(x: wire, y: y(0)))
            context.stroke(line, with: .color(Theme.color.line), lineWidth: fret == 1 ? 2.5 : 1)
        }
        // Fret numbers and inlays under the neck.
        let below = y(0) + 15
        for fret in [3, 5, 7, 9, 12, 15] {
            context.draw(
                Text(verbatim: "\(fret)")
                    .font(SchibstedGrotesk.semiBold.font(size: 9))
                    .foregroundStyle(Theme.color.muted),
                at: CGPoint(x: x(fret), y: below),
            )
        }
        drawTones(&context)
    }

    private func drawTones(_ context: inout GraphicsContext) {
        let grid = model.grid
        let index = chordIndex
        let tones = grid.neckTones(chord: index)
        let toneSet = Set(tones.map(\.position))
        drawScale(&context, chord: index, skipping: toneSet)
        let selected = selectedPosition
        let size: CGFloat = 15
        for tone in tones where tone.position.fret <= Self.frets {
            let center = CGPoint(x: x(tone.position.fret), y: y(tone.position.string))
            let rect = CGRect(
                x: center.x - size / 2,
                y: center.y - size / 2,
                width: size,
                height: size,
            )
            let isSelected = tone.position == selected
            let stroke: Color = switch tone.role {
            case .bass: Theme.color.cue
            case .root: Theme.color.ink
            case .tone: Theme.color.muted
            }
            if isSelected {
                context.fill(Path(ellipseIn: rect), with: .color(Theme.color.cue))
            } else {
                context.fill(Path(ellipseIn: rect), with: .color(Theme.color.ground))
                context.stroke(
                    Path(ellipseIn: rect.insetBy(dx: 0.5, dy: 0.5)),
                    with: .color(stroke),
                    lineWidth: 1,
                )
            }
            context.draw(
                Text(tone.degree)
                    .font(SchibstedGrotesk.bold.font(size: tone.degree.count > 2 ? 7 : 8.5))
                    .foregroundStyle(isSelected ? Theme.color.ground
                        : tone.role == .bass ? Theme.color.cueText : Theme.color.ink),
                at: center,
            )
        }
        drawSelectedOffTone(&context, skipping: toneSet, size: size)
    }

    /// The chord's passing scale, faint, where no chord tone is.
    private func drawScale(
        _ context: inout GraphicsContext,
        chord index: Int,
        skipping toneSet: Set<FretPosition>,
    ) {
        let grid = model.grid
        if let scale = grid.allowed(.scale, chord: index) {
            for string in 0 ..< strings {
                for fret in 0 ... Self.frets {
                    let position = FretPosition(string: string, fret: fret)
                    let pitch = PitchClass(midi: BassFretboard.pitch(position, tuning: grid.tuning))
                    guard scale.contains(pitch), !toneSet.contains(position) else { continue }
                    let rect = CGRect(x: x(fret) - 2, y: y(string) - 2, width: 4, height: 4)
                    let faint = Theme.color.muted.opacity(0.45)
                    context.fill(Path(ellipseIn: rect), with: .color(faint))
                }
            }
        }
    }

    /// The selected note off the chord's tones: a filled cue dot with its fret.
    private func drawSelectedOffTone(
        _ context: inout GraphicsContext,
        skipping toneSet: Set<FretPosition>,
        size: CGFloat,
    ) {
        let selected = selectedPosition
        if let selected, !toneSet.contains(selected), selected.fret <= Self.frets {
            let center = CGPoint(x: x(selected.fret), y: y(selected.string))
            let rect = CGRect(
                x: center.x - size / 2,
                y: center.y - size / 2,
                width: size,
                height: size,
            )
            context.fill(Path(ellipseIn: rect), with: .color(Theme.color.cue))
            context.draw(
                Text(verbatim: "\(selected.fret)")
                    .font(SchibstedGrotesk.bold.font(size: 8.5))
                    .foregroundStyle(Theme.color.ground),
                at: center,
            )
        }
    }

    /// A click on the neck: the selected note takes that position, pinned to that string
    /// (else a new note at the cursor).
    private func click(_ point: CGPoint) {
        let fret = Int(((point.x - Self.labelWidth) / Self.fretWidth).rounded(.down))
        let string = strings - 1 - Int(((point.y - 8) / Self.stringGap).rounded())
        guard (0 ... Self.frets).contains(fret), (0 ..< strings).contains(string) else { return }
        model.placeOnNeck(string: string, fret: fret)
    }
}

// MARK: - The step grid

struct FillStepGrid: View {
    let model: FillEditorModel
    let focused: Bool
    @State private var drag: FillNoteDrag?

    static let rowHeight: CGFloat = 22
    static let inset: CGFloat = 30

    private var strings: Int {
        model.grid.tuning.strings.count
    }

    private var height: CGFloat {
        FillTimeAxis.rulerHeight + Self.rowHeight * CGFloat(strings) + 6
    }

    var body: some View {
        GeometryReader { proxy in
            let axis = FillTimeAxis.make(
                region: model.grid.region,
                width: proxy.size.width,
                inset: Self.inset,
            )
            ScrollView(.horizontal) {
                TimelineView(.animation(paused: model.sounding == nil)) { _ in
                    Canvas { context, size in
                        draw(&context, axis: axis, size: size)
                    }
                }
                .frame(width: max(axis.width, proxy.size.width), height: height)
                .contentShape(Rectangle())
                .gesture(dragGesture(axis))
                .overlay(alignment: .topLeading) { accessibilitySteps(axis) }
            }
            .scrollIndicators(.automatic)
        }
        .frame(height: height + 4)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(uiString("Step grid"))
        .accessibilityIdentifier(AccessibilityID.fillGrid)
    }

    private func y(_ string: Int) -> CGFloat {
        FillTimeAxis.rulerHeight + Self.rowHeight * CGFloat(strings - 1 - string)
    }

    private func string(atY point: CGFloat) -> Int {
        let row = Int(((point - FillTimeAxis.rulerHeight) / Self.rowHeight).rounded(.down))
        return min(max(strings - 1 - row, 0), strings - 1)
    }

    // MARK: Drawing

    private func draw(_ context: inout GraphicsContext, axis: FillTimeAxis, size: CGSize) {
        let grid = model.grid
        let draft = model.draft
        FillTimeAxis.drawRuler(&context, axis: axis, grid: grid, width: axis.width)
        let bottom = y(0) + Self.rowHeight
        drawRows(&context, axis: axis)
        FillTimeAxis.drawColumns(
            &context,
            axis: axis,
            grid: grid,
            rhythm: model.rhythm,
            rows: FillTimeAxis.rulerHeight ... bottom,
        )
        drawCursor(&context, axis: axis, bottom: bottom)
        for note in draft.notes {
            drawNote(&context, note, axis: axis)
        }
        FillTimeAxis.drawPlayhead(&context, axis: axis, tick: model.playheadTick, height: bottom)
    }

    /// Row bands and string names.
    private func drawRows(_ context: inout GraphicsContext, axis: FillTimeAxis) {
        let grid = model.grid
        let draft = model.draft
        for string in 0 ..< strings {
            let top = y(string)
            if string % 2 == 1 {
                context.fill(
                    Path(CGRect(
                        x: axis.inset,
                        y: top,
                        width: axis.width - axis.inset,
                        height: Self.rowHeight,
                    )),
                    with: .color(Theme.color.surfaceAlt.opacity(0.5)),
                )
            }
            context.draw(
                Text(grid.tuning.openStringName(string))
                    .font(SchibstedGrotesk.bold.font(size: 11))
                    .foregroundStyle(string == draft.cursor.string && focused
                        ? Theme.color.cueText : Theme.color.muted),
                at: CGPoint(x: 12, y: top + Self.rowHeight / 2),
            )
        }
    }

    /// The cursor: its column faintly, its cell outlined.
    private func drawCursor(_ context: inout GraphicsContext, axis: FillTimeAxis, bottom: CGFloat) {
        let draft = model.draft
        let step = CGFloat(model.rhythm.ticks) * axis.scale
        let cursorX = axis.x(draft.cursor.tick)
        context.fill(
            Path(CGRect(
                x: cursorX,
                y: FillTimeAxis.rulerHeight,
                width: step,
                height: bottom - FillTimeAxis.rulerHeight,
            )),
            with: .color(Theme.color.cue.opacity(focused ? 0.08 : 0.04)),
        )
        if focused {
            let cell = CGRect(
                x: cursorX + 1,
                y: y(draft.cursor.string) + 1,
                width: step - 2,
                height: Self.rowHeight - 2,
            )
            context.stroke(
                Path(roundedRect: cell, cornerRadius: 4),
                with: .color(Theme.color.cue),
                lineWidth: 1.5,
            )
        }
    }

    private func drawNote(
        _ context: inout GraphicsContext,
        _ note: FillDraft.Note,
        axis: FillTimeAxis,
    ) {
        let grid = model.grid
        guard let position = grid.position(of: note.event) else { return }
        var start = grid.tick(of: note.event)
        var string = position.string
        if let drag, drag.ids.contains(note.id) {
            start += drag.ticks
            string = min(max(string, 0), strings - 1)
        }
        var length = note.event.len
        if let drag, drag.resizing == note.id {
            length = max(model.rhythm.ticks, length + drag.ticks)
            start = grid.tick(of: note.event)
        }
        let rect = CGRect(
            x: axis.x(start) + 1.5,
            y: y(string) + 3,
            width: max(10, CGFloat(length) * axis.scale - 3),
            height: Self.rowHeight - 6,
        )
        let selected = model.draft.selection.contains(note.id)
        let outside = grid.isOutside(note.event)
        let shape = Path(roundedRect: rect, cornerRadius: 5)
        context.fill(shape, with: .color(selected ? Theme.color.cue : Theme.color.cue.opacity(0.2)))
        if outside {
            context.stroke(
                shape,
                with: .color(Theme.color.cueText),
                style: StrokeStyle(lineWidth: 1, dash: [3, 2]),
            )
        } else if !selected {
            context.stroke(shape, with: .color(Theme.color.cue.opacity(0.7)), lineWidth: 1)
        }
        let label = model.showsNames ? model.name(of: note) : "\(position.fret)"
        let marks = FillNoteLabels.prefix(note.event.articulations)
        context.draw(
            Text(marks + label + (grid.isFolded(note.event) || outside ? " !" : ""))
                .font(SchibstedGrotesk.bold.font(size: 12))
                .monospacedDigit()
                .foregroundStyle(selected ? Theme.color.ground : Theme.color.ink),
            at: CGPoint(x: rect.minX + 6, y: rect.midY),
            anchor: .leading,
        )
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
            }
            .onEnded { value in
                defer { drag = nil }
                guard let current = drag else { return }
                if !current.moved {
                    tap(value.startLocation, axis: axis, hit: current.hit)
                } else {
                    model.finish(current, view: .fretboard)
                }
            }
    }

    /// The note under `point`, and whether it is its right edge.
    private func hit(_ point: CGPoint, axis: FillTimeAxis) -> (id: Int, edge: Bool)? {
        let grid = model.grid
        let string = string(atY: point.y)
        for note in model.draft.notes {
            guard grid.position(of: note.event)?.string == string else { continue }
            let start = axis.x(grid.tick(of: note.event))
            let end = start + CGFloat(note.event.len) * axis.scale
            if point.x >= start, point.x <= end {
                return (note.id, point.x >= end - 6)
            }
        }
        return nil
    }

    private func tap(_ point: CGPoint, axis: FillTimeAxis, hit: FillNoteDrag.HitNote?) {
        guard point.y > FillTimeAxis.rulerHeight else { return }
        let tick = model.grid.snap(axis.tick(atX: point.x), to: model.rhythm)
        let string = string(atY: point.y)
        model.tapGrid(
            tick: tick,
            string: string,
            note: hit?.id,
            extending: NSEvent.modifierFlags.contains(.shift),
        )
    }

    // MARK: Accessibility

    /// One element per step: "Bar 2 beat 4 and, over E, F sharp, A string fret 9, eighth
    /// note, slide" or "rest", adjustable (the fret) with Lengthen, Shorten, Rest and string
    /// actions.
    private func accessibilitySteps(_ axis: FillTimeAxis) -> some View {
        let columns = model.grid.columns(model.rhythm)
        let step = CGFloat(model.rhythm.ticks) * axis.scale
        return ZStack(alignment: .topLeading) {
            ForEach(columns, id: \.self) { tick in
                Color.clear
                    .frame(width: step, height: Self.rowHeight * CGFloat(strings))
                    .offset(x: axis.x(tick), y: FillTimeAxis.rulerHeight)
                    .accessibilityElement()
                    .accessibilityLabel(model.spokenStep(tick))
                    .accessibilityAdjustableAction { direction in
                        model.adjustStep(tick, up: direction == .increment)
                    }
                    .accessibilityActions {
                        Button(uiString("Lengthen")) { model.lengthenStep(tick, by: 1) }
                        Button(uiString("Shorten")) { model.lengthenStep(tick, by: -1) }
                        Button(uiString("Rest")) { model.restStep(tick) }
                        Button(uiString("String up")) { model.moveStepString(tick, by: 1) }
                        Button(uiString("String down")) { model.moveStepString(tick, by: -1) }
                    }
            }
        }
    }
}
