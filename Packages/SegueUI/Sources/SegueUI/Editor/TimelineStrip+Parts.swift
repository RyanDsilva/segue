#if os(macOS)
    import AppKit
    import Library
    import Playback
    import SwiftUI

    /// How Tap Timing's review marks a block: "4 → 3" for a new length, "skip".
    enum TapMark: Equatable {
        case changed(String)
        case skipped

        init?(_ chord: TapProposal.Chord, ticksPerPulse: Int) {
            switch chord.outcome {
            case .changed:
                let old = BeatsText.format(Double(chord.old) / Double(ticksPerPulse))
                let new = BeatsText.format(Double(chord.new) / Double(ticksPerPulse))
                self = .changed("\(old) \u{2192} \(new)")
            case .skipped:
                self = .skipped
            case .unchanged, .untapped:
                return nil
            }
        }

        var text: String {
            switch self {
            case let .changed(text): text
            case .skipped: "skip"
            }
        }

        var spoken: String {
            switch self {
            case let .changed(text): "tapped: " + text.replacingOccurrences(
                    of: "\u{2192}",
                    with: "to",
                ) + " beats"
            case .skipped: "skipped, keeps its length"
            }
        }

        var isChange: Bool {
            if case .changed = self {
                return true
            }
            return false
        }
    }

    /// A correction's dot; a tapped one has a tick beside it.
    struct SourceMark: View {
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
    struct PushNotch: View {
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

    /// "Beats" for the selected chord: - / a field ("2.5", "2½") / +, its push, and "Use the
    /// Song's Rule" when it has a correction.
    struct BeatsControl: View {
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
            .disabled(!model.canEditTiming || model.chord(index)?.isSilent != false)
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
#endif
