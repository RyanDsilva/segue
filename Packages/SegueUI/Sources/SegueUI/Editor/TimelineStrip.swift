#if os(macOS)
    import AppKit
    import Library
    import Playback
    import SwiftUI

    /// The chord-length lane (P8-6 section 7.4, P8-7 section 8): one block per chord of the
    /// range, as wide as it lasts, labelled as the chart row shows it, over thin bar ticks,
    /// with a playhead while playing. The edge says where the length came from: solid for
    /// the chart's marks or a grid, dashed for the song's rule, a dot for a correction, a dot
    /// with a tick for a tapped one. Click a block to select it (shift-click spans); then the
    /// Beats field ("2.5" or "2½"), a digit 1-9, a drag on its right edge (beats; eighths
    /// with ⌥, sixteenths with ⌥⇧), `<` to push it early, or Delete. Key, time and tempo
    /// changes are marked above the block where they start.
    struct TimelineStrip: View {
        @Bindable var model: PlayAlong
        @FocusState private var focused: Bool
        /// The block whose right edge is being dragged, and its grid length in ticks so far.
        @State private var drag: (index: Int, ticks: Int)?

        /// Points per quarter note.
        static let pointsPerQuarter: CGFloat = 18
        static let blockHeight: CGFloat = 34
        /// The marker row above the blocks, when the range has a change.
        static let markerHeight: CGFloat = 16

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
            .onKeyPress(characters: CharacterSet(charactersIn: "<"), phases: .down) { _ in
                guard let selected = model.selected, model.canEditTiming else { return .ignored }
                model.cyclePush(selected)
                return .handled
            }
            .onKeyPress(.delete) { clearSelected() }
            .onKeyPress(.deleteForward) { clearSelected() }
            .onKeyPress(.leftArrow, phases: .down) { press in
                moveSelection(by: -1, extending: press.modifiers.contains(.shift))
            }
            .onKeyPress(.rightArrow, phases: .down) { press in
                moveSelection(by: 1, extending: press.modifiers.contains(.shift))
            }
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
            let markers = model.laneMarkers
            let top: CGFloat = markers.isEmpty ? 0 : Self.markerHeight
            return ZStack(alignment: .topLeading) {
                barTicks(grid)
                    .offset(y: top)
                ForEach(markers, id: \.self) { marker in
                    markerLabel(marker)
                }
                ForEach(grid.chords.indices, id: \.self) { index in
                    block(index, top: top)
                        .id(index)
                }
                Playhead(model: model)
                    .offset(y: top)
            }
            .frame(width: width + 8, height: top + Self.blockHeight + 10, alignment: .topLeading)
        }

        /// A thin tick at each bar line.
        private func barTicks(_ grid: SongTimeline) -> some View {
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

        /// "Key: A", "3/4", "♩ 120" over the block where it changes.
        private func markerLabel(_ marker: LaneMarker) -> some View {
            let chord = model.timeline.timeline.chords[marker.index]
            return Text(marker.text)
                .font(SchibstedGrotesk.semiBold.font(size: 11))
                .foregroundStyle(Theme.color.muted)
                .lineLimit(1)
                .fixedSize()
                .offset(x: Self.x(chord.onset) + 1)
                .accessibilityLabel(marker.spoken)
                .accessibilityIdentifier(AccessibilityID.playAlongMarker)
        }

        private func block(_ index: Int, top: CGFloat) -> some View {
            let chords = model.timeline.timeline.chords
            let chord = chords[index]
            let length = drag?.index == index
                ? (drag?.ticks ?? 0) + chord.length - model.gridTicks(of: index)
                : chord.length
            let shift = drag.map { drag in
                drag.index < index ? drag.ticks - model.gridTicks(of: drag.index) : 0
            } ?? 0
            return TimelineBlock(
                title: title(index),
                chord: chord,
                isSelected: model.selected == index || model.span?.contains(index) == true,
                isCurrent: model.current == index,
                edge: LaneEdge(chord.source),
                push: chord.push,
                width: max(Self.x(length) - 2, 6),
                spoken: spoken(index),
                onSelect: {
                    model.select(index, extending: NSEvent.modifierFlags.contains(.shift))
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
            .offset(x: Self.x(chord.onset + shift), y: top + 4)
        }

        /// The block's right edge: drag to change its length, in beats (eighths with ⌥,
        /// sixteenths with ⌥⇧). One write and one undo step when the drag ends.
        private func edgeHandle(_ index: Int) -> some View {
            let chord = model.timeline.timeline.chords[index]
            let start = model.gridTicks(of: index)
            let pulse = chord.meter.ticksPerPulse
            return Color.clear
                .frame(width: 8, height: Self.blockHeight)
                .contentShape(Rectangle())
                .pointerStyle(.columnResize)
                .gesture(
                    DragGesture(minimumDistance: 2)
                        .onChanged { value in
                            let flags = NSEvent.modifierFlags
                            let snap = LaneSnap(
                                option: flags.contains(.option),
                                shift: flags.contains(.shift),
                            )
                            let raw = start + Self.ticks(value.translation.width)
                            drag = (index, snap.snap(raw, ticksPerPulse: pulse))
                        }
                        .onEnded { _ in
                            if let drag, drag.index == index, drag.ticks != start {
                                model.setLength(index, ticks: drag.ticks)
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

        /// "G, 2½ beats, from the chart, pushed an eighth early".
        private func spoken(_ index: Int) -> String {
            let chord = model.timeline.timeline.chords[index]
            let pulses = model.pulses(of: index)
            let beats = "\(BeatsText.format(pulses)) \(pulses == 1 ? "beat" : "beats")"
            let origin = switch chord.source {
            case .chart, .grid: "from the chart"
            case .rule: "estimated"
            case .user: "your change"
            case .tap: "tapped"
            }
            let name = chord.isSilent ? "No chord" : title(index)
            let push = chord.push.map { ", pushed \(BeatsText.spoken($0)) early" } ?? ""
            return "\(name), \(beats), \(origin)\(push)"
        }

        static func x(_ ticks: Int) -> CGFloat {
            CGFloat(ticks) / CGFloat(Ticks.perQuarter) * pointsPerQuarter
        }

        static func ticks(_ x: CGFloat) -> Int {
            Int((x / pointsPerQuarter * CGFloat(Ticks.perQuarter)).rounded())
        }

        private func clearSelected() -> KeyPress.Result {
            guard let selected = model.selected else { return .ignored }
            model.clearCorrection(selected)
            return .handled
        }

        private func moveSelection(by step: Int, extending: Bool) -> KeyPress.Result {
            let count = model.timeline.timeline.chords.count
            guard count > 0 else { return .ignored }
            let from = extending ? (model.spanEnd ?? model.selected) : model.selected
            let next = min(max((from ?? (step > 0 ? -1 : count)) + step, 0), count - 1)
            model.select(next, extending: extending)
            return .handled
        }
    }

    /// One chord's block.
    struct TimelineBlock: View {
        let title: String
        let chord: TimedChord
        let isSelected: Bool
        let isCurrent: Bool
        let edge: LaneEdge
        let push: Push?
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
                dash: edge == .estimated && !isSelected ? [4, 3] : [],
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
                .padding(.leading, push == nil ? 6 : 9)
                .padding(.trailing, 6)
                .frame(width: width, height: TimelineStrip.blockHeight, alignment: .leading)
                .background(shape.fill(fill))
                .overlay {
                    shape.strokeBorder(
                        isSelected ? Theme.color.cueText : Theme.color.lineStrong,
                        style: stroke,
                    )
                }
                .overlay(alignment: .topTrailing) {
                    if edge == .corrected || edge == .tapped {
                        SourceMark(tapped: edge == .tapped)
                            .padding(5)
                    }
                }
                .overlay(alignment: .leading) {
                    if let push {
                        PushNotch(width: TimelineStrip.x(push.ticks))
                    }
                }
                .clipShape(shape)
        }
    }

    /// A correction's dot; a tapped one has a tick beside it.
    private struct SourceMark: View {
        let tapped: Bool

        var body: some View {
            HStack(spacing: 2) {
                if tapped {
                    Capsule()
                        .fill(Theme.color.cueText)
                        .frame(width: 1.5, height: 7)
                }
                Circle()
                    .fill(Theme.color.cueText)
                    .frame(width: 5, height: 5)
            }
            .accessibilityHidden(true)
        }
    }

    /// The early part of a pushed block: a notch cut into its left edge, as wide as the
    /// push, ending at the beat the chord would start on.
    private struct PushNotch: View {
        let width: CGFloat

        var body: some View {
            ZStack(alignment: .trailing) {
                Rectangle()
                    .fill(Theme.color.cueText.opacity(0.10))
                    .frame(width: width)
                Rectangle()
                    .fill(Theme.color.cueText.opacity(0.55))
                    .frame(width: 1, height: TimelineStrip.blockHeight * 0.4)
            }
            .frame(height: TimelineStrip.blockHeight)
            .accessibilityHidden(true)
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

    /// "Beats" for the selected chord: - / a field ("2.5", "2½") / +, its push, and "Use the
    /// Song's Rule" when it has a correction.
    private struct BeatsControl: View {
        let model: PlayAlong
        @State private var text = ""
        @FocusState private var editing: Bool

        var body: some View {
            HStack(spacing: 6) {
                BarLabel("Beats")
                if let selected = model.selected {
                    let pulses = model.pulses(of: selected)
                    let whole = Int(pulses.rounded())
                    StepButton(symbol: "minus", label: "Fewer beats") {
                        model.setBeats(selected, Int(pulses.rounded(.up)) - 1)
                    }
                    .disabled(!model.canEditTiming || pulses <= 1)
                    TextField("Beats", text: $text)
                        .textFieldStyle(.plain)
                        .font(SchibstedGrotesk.semiBold.font(size: 13))
                        .monospacedDigit()
                        .multilineTextAlignment(.center)
                        .foregroundStyle(Theme.color.ink)
                        .frame(width: 40, height: 26)
                        .background(Theme.color.ground, in: RoundedRectangle(cornerRadius: 6))
                        .overlay {
                            RoundedRectangle(cornerRadius: 6)
                                .strokeBorder(
                                    editing ? Theme.color.cueText : Theme.color.controlBorder,
                                    lineWidth: 1,
                                )
                        }
                        .focused($editing)
                        .disabled(!model.canEditTiming)
                        .onSubmit { commit(selected) }
                        .onChange(of: editing) { _, isEditing in
                            if !isEditing {
                                commit(selected)
                            }
                        }
                        .onAppear { text = BeatsText.format(pulses) }
                        .onChange(of: pulses) { _, new in text = BeatsText.format(new) }
                        .onChange(of: selected) { text = BeatsText.format(pulses) }
                        .help("Type a length in beats: 3, 2.5 or 2½")
                        .accessibilityLabel("Beats")
                        .accessibilityValue(BeatsText.format(pulses))
                        .accessibilityIdentifier(AccessibilityID.playAlongBeats)
                    StepButton(symbol: "plus", label: "More beats") {
                        model.setBeats(selected, Int(pulses.rounded(.down)) + 1)
                    }
                    .disabled(!model.canEditTiming || whole >= SongTimeline.maximumPulses)
                    PushMenu(model: model, index: selected)
                        .padding(.leading, 6)
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

        private func commit(_ index: Int) {
            let shown = BeatsText.format(model.pulses(of: index))
            guard text != shown else { return }
            if !model.setLength(index, text: text) {
                NSSound.beep()
                text = shown
            }
        }
    }

    /// "Push": on the beat, an eighth or a sixteenth early (`<` cycles them).
    struct PushMenu: View {
        let model: PlayAlong
        let index: Int

        var body: some View {
            let push = model.push(of: index)
            Menu {
                choice("On the Beat", nil, push)
                choice("An Eighth Early", .eighth, push)
                choice("A Sixteenth Early", .sixteenth, push)
            } label: {
                Text(push.map { "Push: \(BeatsText.short($0))" } ?? "Push")
                    .font(SchibstedGrotesk.semiBold.font(size: 13))
            }
            .menuStyle(.button)
            .fixedSize()
            .disabled(!model.canEditTiming || model.timeline.timeline.chords[safe: index]?
                .isSilent != false)
            .help("Start this chord early, ahead of the beat (<)")
            .accessibilityLabel("Push")
            .accessibilityValue(push.map { "\(BeatsText.spoken($0)) early" } ?? "on the beat")
            .accessibilityIdentifier(AccessibilityID.playAlongPush)
        }

        private func choice(_ title: String, _ value: Push?, _ current: Push?) -> some View {
            Toggle(title, isOn: Binding(get: { current == value }, set: { isOn in
                if isOn {
                    model.setPush(index, value)
                }
            }))
        }
    }

    private extension Array {
        subscript(safe index: Int) -> Element? {
            indices.contains(index) ? self[index] : nil
        }
    }
#endif
