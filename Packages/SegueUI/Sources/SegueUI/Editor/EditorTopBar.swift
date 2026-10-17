#if os(macOS)
    import Diagrams
    import Editing
    import MusicTheory
    import SwiftUI

    /// The editor's display bar (mockup E2 b): transpose, capo, Shapes / Concert, Nashville,
    /// diagrams and instrument, and "Apply to source" while transposed. Toggles are view
    /// state saved to the song's sidecar; capo and "Apply to source" edit the ChordPro.
    struct EditorTopBar: View {
        let model: SongEditorViewModel

        var body: some View {
            HStack(alignment: .center, spacing: 0) {
                LyricFlowLayout(rowSpacing: 8) {
                    transposeGroup.frame(height: 30).padding(.trailing, 28)
                    capoGroup.frame(height: 30).padding(.trailing, 28)
                    displayGroup.frame(height: 30).padding(.trailing, 28)
                    diagramGroup.frame(height: 30).padding(.trailing, 20)
                    if model.options.transpose != 0 {
                        Button("Apply to Source") { model.applyTranspositionToSource() }
                            .buttonStyle(.segueSecondary)
                            .controlSize(.small)
                            .help("Rewrite the chords and {key} in the new key (keeps {capo})")
                            .accessibilityIdentifier(AccessibilityID.editorApplyTransposition)
                            .frame(height: 30)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                if model.editorMode == .visual {
                    Text("Click above a syllable to add a chord. Drag pills to move.")
                        .font(SchibstedGrotesk.medium.font(size: 14))
                        .foregroundStyle(Theme.color.muted)
                        .lineLimit(1)
                        .fixedSize()
                        .padding(.leading, 16)
                        .layoutPriority(-1)
                        .hiddenWhenTruncated()
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .overlay(alignment: .bottom) { Hairline() }
        }

        private var transposeGroup: some View {
            HStack(spacing: 8) {
                BarLabel("Transpose")
                StepButton(symbol: "minus", label: "Transpose down") { model.stepTranspose(by: -1) }
                    .accessibilityIdentifier(AccessibilityID.editorTransposeDown)
                Text(transposeText)
                    .font(SchibstedGrotesk.semiBold.font(size: 14))
                    .foregroundStyle(Theme.color.ink)
                    .frame(minWidth: 70)
                    .accessibilityIdentifier(AccessibilityID.editorTransposeValue)
                StepButton(symbol: "plus", label: "Transpose up") { model.stepTranspose(by: 1) }
                    .accessibilityIdentifier(AccessibilityID.editorTransposeUp)
            }
        }

        private var transposeText: String {
            let transpose = model.options.transpose
            let signed = transpose > 0 ? "+\(transpose)" : (transpose < 0 ? "\(transpose)" : "+0")
            guard let key = model.displayKeyName else { return signed }
            return "\(key), \(signed)"
        }

        private var capoGroup: some View {
            HStack(spacing: 8) {
                BarLabel("Capo")
                StepButton(symbol: "minus", label: "Capo down") { model.stepCapo(by: -1) }
                    .disabled(model.capo == 0)
                    .accessibilityIdentifier(AccessibilityID.editorCapoDown)
                Text("\(model.capo)")
                    .font(SchibstedGrotesk.semiBold.font(size: 14))
                    .foregroundStyle(Theme.color.ink)
                    .monospacedDigit()
                    .frame(minWidth: 24)
                    .accessibilityIdentifier(AccessibilityID.editorCapoValue)
                StepButton(symbol: "plus", label: "Capo up") { model.stepCapo(by: 1) }
                    .disabled(model.capo >= 11)
                    .accessibilityIdentifier(AccessibilityID.editorCapoUp)
            }
        }

        private var displayGroup: some View {
            HStack(spacing: 8) {
                SegmentedGroup {
                    SegmentButton(title: "Shapes", isOn: model.options.capoMode == .shapes) {
                        model.setCapoMode(.shapes)
                    }
                    .accessibilityIdentifier(AccessibilityID.editorShapes)
                    .help("Chords as written: guitar shapes for the capo")
                    SegmentButton(title: "Concert", isOn: model.options.capoMode == .concert) {
                        model.setCapoMode(.concert)
                    }
                    .accessibilityIdentifier(AccessibilityID.editorConcert)
                    .help("Chords at concert pitch (sounding), for keys and voice")
                }
                .disabled(model.capo == 0)
                SegmentedGroup {
                    SegmentButton(title: "Nashville", isOn: model.options.nashville) {
                        model.setNashville(!model.options.nashville)
                    }
                    .accessibilityIdentifier(AccessibilityID.editorNashville)
                    .help("Show chords as Nashville numbers")
                }
            }
        }

        private var diagramGroup: some View {
            HStack(spacing: 8) {
                SegmentedGroup {
                    SegmentButton(title: "Diagrams", isOn: model.options.showDiagrams) {
                        model.setShowDiagrams(!model.options.showDiagrams)
                    }
                    .accessibilityIdentifier(AccessibilityID.editorDiagramsToggle)
                }
                Menu {
                    Picker("Instrument", selection: instrument) {
                        Text("Guitar").tag(Instrument.guitar)
                        Text("Piano").tag(Instrument.piano)
                    }
                    .pickerStyle(.inline)
                    if model.options.instrument == .guitar {
                        Picker("Tuning", selection: tuning) {
                            ForEach(tuningChoices, id: \.self) { tuning in
                                Text(tuning.name).tag(tuning)
                            }
                        }
                        .pickerStyle(.inline)
                    }
                } label: {
                    Text(instrumentTitle)
                        .font(SchibstedGrotesk.semiBold.font(size: 13))
                }
                .menuStyle(.button)
                .buttonStyle(.segueSecondary)
                .controlSize(.small)
                .fixedSize()
                .accessibilityIdentifier(AccessibilityID.editorInstrument)
                .help("Instrument and tuning for chord diagrams")
            }
        }

        private var instrumentTitle: String {
            switch model.options.instrument {
            case .guitar:
                model.tuning == .standard ? "Guitar" : "Guitar, \(model.tuning.name)"
            case .piano:
                "Piano"
            }
        }

        private var tuningChoices: [Tuning] {
            Tuning.presets.contains(model.tuning) ? Tuning.presets : Tuning.presets + [model.tuning]
        }

        private var instrument: Binding<Instrument> {
            Binding(get: { model.options.instrument }, set: { model.setInstrument($0) })
        }

        private var tuning: Binding<Tuning> {
            Binding(get: { model.tuning }, set: { model.setTuning($0) })
        }
    }

    /// 1px `line` rule along an edge.
    struct Hairline: View {
        var body: some View {
            Rectangle().fill(Theme.color.line).frame(height: 1)
        }
    }

    /// Bar label: 14 / 700 muted (mockup "Transpose", "Capo").
    private struct BarLabel: View {
        let title: String

        init(_ title: String) {
            self.title = title
        }

        var body: some View {
            Text(title)
                .font(SchibstedGrotesk.bold.font(size: 14))
                .foregroundStyle(Theme.color.muted)
        }
    }

    /// 30 x 30 stepper button with a hairline border (mockup -/+).
    private struct StepButton: View {
        let symbol: String
        let label: String
        let action: () -> Void
        @Environment(\.isEnabled) private var isEnabled

        var body: some View {
            Button(action: action) {
                Image(systemName: symbol)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Theme.color.ink)
                    .frame(width: 30, height: 30)
                    .background(Theme.color.ground, in: RoundedRectangle(cornerRadius: 6))
                    .overlay {
                        RoundedRectangle(cornerRadius: 6)
                            .strokeBorder(Theme.color.controlBorder, lineWidth: 1)
                    }
                    .contentShape(RoundedRectangle(cornerRadius: 6))
                    .opacity(isEnabled ? 1 : 0.4)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(label)
            .help(label)
        }
    }

    /// The mockup's segmented track: `surfaceAlt` with 3pt padding, radius 8.
    struct SegmentedGroup<Content: View>: View {
        @ViewBuilder var content: Content
        @Environment(\.isEnabled) private var isEnabled

        var body: some View {
            HStack(spacing: 0) { content }
                .padding(3)
                .background(Theme.color.surfaceAlt, in: RoundedRectangle(cornerRadius: 8))
                .opacity(isEnabled ? 1 : 0.45)
        }
    }

    /// One segment: selected is a `ground` tile with ink text, others muted.
    struct SegmentButton: View {
        let title: String
        let isOn: Bool
        var fontSize: CGFloat = 13
        var horizontalPadding: CGFloat = 12
        var verticalPadding: CGFloat = 4
        let action: () -> Void

        var body: some View {
            Button(action: action) {
                Text(title)
                    .font(SchibstedGrotesk.semiBold.font(size: fontSize))
                    .foregroundStyle(isOn ? Theme.color.ink : Theme.color.muted)
                    .padding(.horizontal, horizontalPadding)
                    .padding(.vertical, verticalPadding)
                    .background {
                        if isOn {
                            RoundedRectangle(cornerRadius: 6)
                                .fill(Theme.color.ground)
                                .shadow(color: .black.opacity(0.06), radius: 1, y: 0.5)
                        }
                    }
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(isOn ? .isSelected : [])
            .accessibilityValue(isOn ? "on" : "off")
        }
    }

    private struct HiddenWhenTruncated: ViewModifier {
        func body(content: Content) -> some View {
            ViewThatFits(in: .horizontal) {
                content
                Color.clear.frame(width: 0, height: 0)
            }
        }
    }

    extension View {
        /// Drops the view rather than truncating it when there is no room.
        func hiddenWhenTruncated() -> some View {
            modifier(HiddenWhenTruncated())
        }
    }
#endif
