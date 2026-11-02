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
                if let tap = model.tap {
                    TapCapturePanel(tap: tap)
                } else {
                    BeatsControl(model: model)
                }
            }
            .focusable()
            .focused($focused)
            .focusEffectDisabled()
            .onChange(of: model.tap == nil) { _, closed in
                // The tap panel takes the keys while it is open.
                focused = !closed
            }
            .onKeyPress(phases: .down) { press in
                tapKey(press)
            }
            .onKeyPress(characters: .decimalDigits, phases: .down) { press in
                guard model.tap == nil, let selected = model.selected,
                      let digit = Int(press.characters),
                      (1 ... 9).contains(digit)
                else { return .ignored }
                model.setBeats(selected, digit)
                return .handled
            }
            .onKeyPress(characters: CharacterSet(charactersIn: "<"), phases: .down) { _ in
                guard model.tap == nil, let selected = model.selected, model.canEditTiming
                else { return .ignored }
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
                guard model.tap == nil else { return .ignored }
                model.togglePlay()
                return .handled
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel(uiString("Chord lengths"))
            .accessibilityIdentifier(AccessibilityID.playAlongLane)
        }

        private var lane: some View {
            let grid = model.timeline.timeline
            let width = max(Self.x(grid.totalTicks), 1)
            let markers = model.laneMarkers
            let top: CGFloat = markers.isEmpty ? 0 : Self.markerHeight
            let review = reviewShifts()
            return ZStack(alignment: .topLeading) {
                barTicks(grid)
                    .offset(y: top)
                ForEach(markers, id: \.self) { marker in
                    markerLabel(marker)
                }
                ForEach(grid.chords.indices, id: \.self) { index in
                    block(index, top: top, review: review)
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

        /// Tap Timing's review: how far each block moves (the changes before it add up).
        private func reviewShifts() -> [Int]? {
            guard let tap = model.tap, tap.phase == .review, let proposal = tap.proposal,
                  proposal.chords.count == model.timeline.timeline.chords.count
            else { return nil }
            var shifts: [Int] = []
            var total = 0
            for chord in proposal.chords {
                shifts.append(total)
                total += chord.new - chord.old
            }
            return shifts
        }

        private func block(_ index: Int, top: CGFloat, review: [Int]?) -> some View {
            let chords = model.timeline.timeline.chords
            let chord = chords[index]
            let proposed = review == nil ? nil : model.tap?.proposal?.chords[index]
            let length = if let proposed {
                chord.length + proposed.new - proposed.old
            } else if drag?.index == index {
                (drag?.ticks ?? 0) + chord.length - model.gridTicks(of: index)
            } else {
                chord.length
            }
            let shift = review?[index] ?? drag.map { drag in
                drag.index < index ? drag.ticks - model.gridTicks(of: drag.index) : 0
            } ?? 0
            let tapping = model.tap?.phase == .tapping
            return TimelineBlock(
                title: title(index),
                chord: chord,
                isSelected: model.tap == nil
                    && (model.selected == index || model.span?.contains(index) == true),
                isCurrent: model.current == index || (tapping && model.tap?.next == index),
                edge: LaneEdge(chord.source),
                push: chord.push,
                width: max(Self.x(length) - 2, 6),
                spoken: spoken(index),
                review: proposed.flatMap { TapMark($0, ticksPerPulse: chord.meter.ticksPerPulse) },
                oldWidth: proposed.map { _ in max(Self.x(chord.length) - 2, 6) },
                oldOffset: -Self.x(shift),
                onSelect: {
                    guard model.tap == nil else { return }
                    model.select(index, extending: NSEvent.modifierFlags.contains(.shift))
                    focused = true
                },
                adjust: { delta in
                    model.setBeats(index, Int(model.pulses(of: index).rounded()) + delta)
                },
            )
            .overlay(alignment: .trailing) {
                if model.canEditTiming, !chord.isSilent, model.tap == nil {
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

        /// Tap Timing's keys while its panel is open: Space or Page Down taps (⌥ for half a
        /// beat), Tab skips, Return keeps the review, Esc stops, discards or closes.
        private func tapKey(_ press: KeyPress) -> KeyPress.Result {
            guard let tap = model.tap else { return .ignored }
            let half = press.modifiers.contains(.option)
            switch press.key {
            case KeyEquivalent("\u{00A0}"), .pageDown, .space:
                tap.tap(half: half)
            case .tab:
                tap.skip()
            case .return:
                guard tap.phase == .review else { return .ignored }
                tap.keep()
            case .escape:
                switch tap.phase {
                case .ready: tap.cancel()
                case .tapping: tap.stop()
                case .review: tap.discard()
                }
            default:
                return .ignored
            }
            return .handled
        }

        private func clearSelected() -> KeyPress.Result {
            guard model.tap == nil, let selected = model.selected else { return .ignored }
            model.clearCorrection(selected)
            return .handled
        }

        private func moveSelection(by step: Int, extending: Bool) -> KeyPress.Result {
            let count = model.timeline.timeline.chords.count
            guard count > 0, model.tap == nil else { return .ignored }
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
        /// Tap Timing's review of this chord, and its old width (ghosted under it).
        var review: TapMark?
        var oldWidth: CGFloat?
        /// Where the block started before, from where it starts now.
        var oldOffset: CGFloat = 0
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
                .overlay(alignment: .bottomLeading) {
                    // The old length, ghosted as a thin bar under where the block was.
                    if case .changed = review, let oldWidth {
                        Capsule()
                            .fill(Theme.color.muted.opacity(0.45))
                            .frame(width: max(oldWidth - 4, 2), height: 3)
                            .offset(x: oldOffset + 2, y: 6)
                            .accessibilityHidden(true)
                    }
                }
                .contentShape(shape)
                .onTapGesture(perform: onSelect)
                .help(review.map { "\(spoken), \($0.spoken)" } ?? spoken)
                .accessibilityElement()
                .accessibilityLabel(review.map { "\(spoken), \($0.spoken)" } ?? spoken)
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
            HStack(spacing: 5) {
                Text(chord.isSilent ? uiString("N.C.") : title)
                    .font(SchibstedGrotesk.bold.font(size: 13))
                    .foregroundStyle(chord.isSilent ? Theme.color.muted : Theme.color.cueText)
                // The review's "4 → 3" where it fits; VoiceOver and the tooltip always say it.
                if let review,
                   width >= CGFloat(title.count) * 9 + CGFloat(review.text.count) * 7 + 18
                {
                    Text(review.text)
                        .font(SchibstedGrotesk.semiBold.font(size: 11))
                        .monospacedDigit()
                        .foregroundStyle(Theme.color.muted)
                }
            }
            .lineLimit(1)
            .padding(.leading, push == nil ? 6 : 9)
            .padding(.trailing, 6)
            .frame(width: width, height: TimelineStrip.blockHeight, alignment: .leading)
            .background(shape.fill(review == .skipped ? Theme.color.surfaceAlt : fill))
            .overlay {
                shape.strokeBorder(
                    isSelected || review?.isChange == true
                        ? Theme.color.cueText : Theme.color.lineStrong,
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

#endif
