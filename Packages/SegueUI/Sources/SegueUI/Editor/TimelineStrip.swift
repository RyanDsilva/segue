#if os(macOS)
    import Library
    import Playback
    import SwiftUI

    /// The chord-length lane (P8-6 section 7.4, P8-7 section 8): one block per chord of the
    /// range, as wide as it lasts, labelled as the chart row shows it, over thin bar ticks,
    /// with a playhead while playing. The edge says where the length came from: solid for
    /// the chart's marks or a grid, dashed for the song's rule, a dot for a correction.
    /// Click a block to select it; then the Beats stepper, a digit 1-9, a drag on its right
    /// edge (snapping to beats) or Delete. P8-7b extends this file (sub-beat lengths, pushes,
    /// tap capture, markers, span selection), so the layout and selection stay open.
    struct TimelineStrip: View {
        @Bindable var model: PlayAlong
        @FocusState private var focused: Bool
        /// The block whose right edge is being dragged, and its length in pulses so far.
        @State private var drag: (index: Int, pulses: Int)?

        /// Points per quarter note.
        static let pointsPerQuarter: CGFloat = 18
        static let blockHeight: CGFloat = 34

        var body: some View {
            VStack(alignment: .leading, spacing: 6) {
                ScrollViewReader { proxy in
                    ScrollView(.horizontal) {
                        lane
                            .padding(.vertical, 2)
                    }
                    .scrollIndicators(.automatic)
                    .onChange(of: model.current) { _, current in
                        guard let current else { return }
                        proxy.scrollTo(current, anchor: .center)
                    }
                }
                BeatsControl(model: model)
            }
            .focusable()
            .focused($focused)
            .focusEffectDisabled()
            .onKeyPress(characters: .decimalDigits, phases: .down) { press in
                guard let selected = model.selected, let digit = Int(press.characters),
                      (1 ... 9).contains(digit)
                else { return .ignored }
                model.setBeats(selected, digit)
                return .handled
            }
            .onKeyPress(.delete) { clearSelected() }
            .onKeyPress(.deleteForward) { clearSelected() }
            .onKeyPress(.leftArrow) { moveSelection(by: -1) }
            .onKeyPress(.rightArrow) { moveSelection(by: 1) }
            .onKeyPress(.space) {
                model.togglePlay()
                return .handled
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Chord lengths")
            .accessibilityIdentifier(AccessibilityID.playAlongLane)
        }

        private var lane: some View {
            let grid = model.timeline.timeline
            let width = max(Self.x(grid.totalTicks), 1)
            return ZStack(alignment: .topLeading) {
                barTicks(grid, width: width)
                ForEach(model.timeline.timeline.chords.indices, id: \.self) { index in
                    block(index)
                        .id(index)
                }
                Playhead(model: model)
            }
            .frame(width: width + 8, height: Self.blockHeight + 10, alignment: .topLeading)
        }

        /// A thin tick at each bar line, a bar number every fourth.
        private func barTicks(_ grid: SongTimeline, width _: CGFloat) -> some View {
            var bars: [Int] = []
            var bar = 1
            while true {
                let tick = grid.tick(of: BarBeat(bar: bar, beat: 1, tick: 0))
                guard tick < grid.totalTicks, bars.count < 2000 else { break }
                bars.append(tick)
                bar += 1
            }
            return ForEach(bars, id: \.self) { tick in
                Rectangle()
                    .fill(Theme.color.line)
                    .frame(width: 1, height: Self.blockHeight + 8)
                    .offset(x: Self.x(tick))
                    .accessibilityHidden(true)
            }
        }

        private func block(_ index: Int) -> some View {
            let chord = model.timeline.timeline.chords[index]
            let pulses = drag?.index == index ? drag?.pulses : nil
            let length = pulses.map { $0 * chord.meter.ticksPerPulse } ?? chord.length
            let shift = drag.map { drag in
                drag.index < index
                    ? (drag.pulses * model.timeline.timeline.chords[drag.index].meter.ticksPerPulse)
                    - model.timeline.timeline.chords[drag.index].length : 0
            } ?? 0
            return TimelineBlock(
                title: title(index),
                chord: chord,
                isSelected: model.selected == index,
                isCurrent: model.current == index,
                corrected: chord.source == .user || chord.source == .tap,
                width: max(Self.x(length) - 2, 6),
                spoken: spoken(index),
                onSelect: {
                    model.selected = index
                    focused = true
                },
                adjust: { delta in
                    model.setBeats(index, Int(model.pulses(of: index).rounded()) + delta)
                },
            )
            .overlay(alignment: .trailing) {
                if model.canEditTiming, !chord.isSilent {
                    edgeHandle(index)
                }
            }
            .offset(x: Self.x(chord.onset + shift), y: 4)
        }

        /// The block's right edge: drag to change its length in whole beats (one write and
        /// one undo step when the drag ends).
        private func edgeHandle(_ index: Int) -> some View {
            let chord = model.timeline.timeline.chords[index]
            let pulse = Self.x(chord.meter.ticksPerPulse)
            let start = max(1, Int(model.pulses(of: index).rounded()))
            return Color.clear
                .frame(width: 8, height: Self.blockHeight)
                .contentShape(Rectangle())
                .pointerStyle(.columnResize)
                .gesture(
                    DragGesture(minimumDistance: 2)
                        .onChanged { value in
                            let pulses = start + Int((value.translation.width / pulse).rounded())
                            drag = (index, min(max(pulses, 1), SongTimeline.maximumPulses))
                        }
                        .onEnded { _ in
                            if let drag, drag.index == index {
                                model.setBeats(index, drag.pulses)
                            }
                            drag = nil
                        },
                )
                .accessibilityHidden(true)
        }

        /// What the chart row shows for chord `index` (the bass note in the bass-note view).
        private func title(_ index: Int) -> String {
            let chord = model.timeline.timeline.chords[index]
            return model.source?.cue(for: chord)?.text ?? chord.token
        }

        /// "G, 4 beats, from the chart" / "estimated" / "your change".
        private func spoken(_ index: Int) -> String {
            let chord = model.timeline.timeline.chords[index]
            let pulses = model.pulses(of: index)
            let count = pulses == pulses.rounded() ? "\(Int(pulses))" : String(
                format: "%.1f",
                pulses,
            )
            let beats = "\(count) \(pulses == 1 ? "beat" : "beats")"
            let origin = switch chord.source {
            case .chart, .grid: "from the chart"
            case .rule: "estimated"
            case .user: "your change"
            case .tap: "tapped"
            }
            let name = chord.isSilent ? "No chord" : title(index)
            return "\(name), \(beats), \(origin)"
        }

        static func x(_ ticks: Int) -> CGFloat {
            CGFloat(ticks) / CGFloat(Ticks.perQuarter) * pointsPerQuarter
        }

        private func clearSelected() -> KeyPress.Result {
            guard let selected = model.selected else { return .ignored }
            model.clearCorrection(selected)
            return .handled
        }

        private func moveSelection(by step: Int) -> KeyPress.Result {
            let count = model.timeline.timeline.chords.count
            guard count > 0 else { return .ignored }
            let next = (model.selected ?? (step > 0 ? -1 : count)) + step
            model.selected = min(max(next, 0), count - 1)
            return .handled
        }
    }

    /// One chord's block.
    struct TimelineBlock: View {
        let title: String
        let chord: TimedChord
        let isSelected: Bool
        let isCurrent: Bool
        let corrected: Bool
        let width: CGFloat
        let spoken: String
        let onSelect: () -> Void
        let adjust: (Int) -> Void

        private var shape: RoundedRectangle {
            RoundedRectangle(cornerRadius: 5)
        }

        private var fill: Color {
            if isCurrent {
                return Theme.color.cue.opacity(0.22)
            }
            return isSelected ? Theme.color.cue.opacity(0.12) : Theme.color.ground
        }

        private var stroke: StrokeStyle {
            StrokeStyle(
                lineWidth: isSelected ? 2 : 1,
                dash: chord.isEstimated && !isSelected ? [4, 3] : [],
            )
        }

        var body: some View {
            label
                .contentShape(shape)
                .onTapGesture(perform: onSelect)
                .help(spoken)
                .accessibilityElement()
                .accessibilityLabel(spoken)
                .accessibilityAddTraits(isSelected ? [.isSelected, .isButton] : .isButton)
                .accessibilityAction(.default, onSelect)
                .accessibilityAdjustableAction { direction in
                    switch direction {
                    case .increment: adjust(1)
                    case .decrement: adjust(-1)
                    @unknown default: break
                    }
                }
                .accessibilityIdentifier(AccessibilityID.playAlongBlock)
        }

        private var label: some View {
            Text(chord.isSilent ? "N.C." : title)
                .font(SchibstedGrotesk.bold.font(size: 13))
                .foregroundStyle(chord.isSilent ? Theme.color.muted : Theme.color.cueText)
                .lineLimit(1)
                .padding(.horizontal, 6)
                .frame(width: width, height: TimelineStrip.blockHeight, alignment: .leading)
                .background(shape.fill(fill))
                .overlay {
                    shape.strokeBorder(
                        isSelected ? Theme.color.cueText : Theme.color.lineStrong,
                        style: stroke,
                    )
                }
                .overlay(alignment: .topTrailing) {
                    if corrected {
                        Circle()
                            .fill(Theme.color.cueText)
                            .frame(width: 5, height: 5)
                            .padding(5)
                            .accessibilityHidden(true)
                    }
                }
                .clipShape(shape)
        }
    }

    /// The playhead line, redrawn on the display's clock only while playing.
    private struct Playhead: View {
        let model: PlayAlong

        var body: some View {
            if model.isPlaying {
                TimelineView(.animation(minimumInterval: 1 / 30)) { _ in
                    if let tick = model.playheadTick() {
                        Rectangle()
                            .fill(Theme.color.cueText)
                            .frame(width: 2, height: TimelineStrip.blockHeight + 8)
                            .offset(x: TimelineStrip.x(tick))
                    }
                }
                .allowsHitTesting(false)
                .accessibilityHidden(true)
            }
        }
    }

    /// "Beats" for the selected chord: - / value / +, and "Use the Song's Rule" when it has
    /// a correction.
    private struct BeatsControl: View {
        let model: PlayAlong

        var body: some View {
            HStack(spacing: 6) {
                BarLabel("Beats")
                if let selected = model.selected {
                    let pulses = Int(model.pulses(of: selected).rounded())
                    StepButton(symbol: "minus", label: "Fewer beats") {
                        model.setBeats(selected, pulses - 1)
                    }
                    .disabled(!model.canEditTiming || pulses <= 1)
                    Text("\(pulses)")
                        .font(SchibstedGrotesk.semiBold.font(size: 13))
                        .monospacedDigit()
                        .foregroundStyle(Theme.color.ink)
                        .frame(minWidth: 22)
                        .accessibilityLabel("Beats")
                        .accessibilityIdentifier(AccessibilityID.playAlongBeats)
                    StepButton(symbol: "plus", label: "More beats") {
                        model.setBeats(selected, pulses + 1)
                    }
                    .disabled(!model.canEditTiming || pulses >= SongTimeline.maximumPulses)
                    if model.correction(of: selected) != nil {
                        Button("Use the Song's Rule") { model.clearCorrection(selected) }
                            .buttonStyle(.segueSecondary)
                            .controlSize(.small)
                            .accessibilityIdentifier(AccessibilityID.playAlongUseRule)
                    }
                } else {
                    Text("Click a chord to change how long it lasts")
                        .font(.callout)
                        .foregroundStyle(Theme.color.muted)
                }
            }
        }
    }
#endif
