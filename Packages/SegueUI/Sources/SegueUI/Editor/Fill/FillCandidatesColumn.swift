// P8-7d (docs/phases/8-workstreams/P8-7-time-model-and-fills.md sections 12.2, 12.3, 12.8).
// The fill sheet's left column: rows A-D (and the saved fill when editing one), each with its
// family, a contour sparkline, the note names and a ▶ button; "More" reveals E; then "Start
// from scratch". The selected row is the part being edited. ⌥ over a row shows its score
// breakdown (the walk-up picker's convention); VoiceOver reads it as custom content.

import SwiftUI

struct FillCandidatesColumn: View {
    let model: FillEditorModel
    /// The column has keyboard focus (the selected row shows a ring).
    var focused = false
    @State private var optionHeld = false
    @State private var hovered: FillEditorModel.Row?

    static let width: CGFloat = 232

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 2) {
                Text("OPTIONS")
                    .font(SchibstedGrotesk.bold.font(size: 11))
                    .tracking(0.88)
                    .foregroundStyle(Theme.color.muted)
                    .padding(.horizontal, 10)
                    .padding(.bottom, 4)
                    .accessibilityAddTraits(.isHeader)
                if model.candidates.isEmpty, model.editing == nil {
                    Text("No fill fits these chords. Start from scratch.")
                        .font(SchibstedGrotesk.medium.font(size: 12))
                        .foregroundStyle(Theme.color.muted)
                        .padding(.horizontal, 10)
                }
                ForEach(model.rows, id: \.self) { row in
                    rowView(row)
                }
                if model.hasMore {
                    moreButton
                }
                Rectangle().fill(Theme.color.line).frame(height: 1)
                    .padding(.vertical, 6)
                    .padding(.horizontal, 10)
                scratchRow
            }
            .padding(.vertical, 12)
            .padding(.horizontal, 8)
        }
        .scrollIndicators(.never)
        .frame(width: Self.width)
        .onModifierKeysChanged(mask: .option) { _, new in
            optionHeld = new.contains(.option)
        }
    }

    private func rowView(_ row: FillEditorModel.Row) -> some View {
        let selected = model.selected == row
        let letter = model.letter(row)
        let names = model.noteNames(row)
        return VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .top, spacing: 8) {
                Button {
                    model.select(row)
                } label: {
                    rowLabel(row, selected: selected, letter: letter, names: names)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(model.spokenRow(row))
                .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
                .accessibilityCustomContent("Score", breakdownText(row), importance: .default)
                .accessibilityIdentifier(AccessibilityID.fillCandidate(letter))
                playButton(row, letter: letter)
            }
            revertButton(row, letter: letter)
        }
        .padding(.vertical, 7)
        .padding(.leading, 8)
        .padding(.trailing, 4)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(selected ? Theme.color.surfaceAlt
                    : hovered == row ? Theme.color.surfaceAlt.opacity(0.5) : .clear),
        )
        .overlay {
            if selected, focused {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(Theme.color.cue.opacity(0.6), lineWidth: 1.5)
            }
        }
        .onHover { inside in
            hovered = inside ? row : (hovered == row ? nil : hovered)
        }
    }

    private func rowLabel(
        _ row: FillEditorModel.Row,
        selected: Bool,
        letter: String,
        names: [String],
    ) -> some View {
        HStack(alignment: .top, spacing: 9) {
            Text(row == .saved ? "\u{2713}" : letter)
                .font(SchibstedGrotesk.extraBold.font(size: 12))
                .foregroundStyle(selected ? Theme.color.ground : Theme.color.ink)
                .frame(width: 20, height: 20)
                .background(
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(selected ? Theme.color.cue : Theme.color.surfaceAlt),
                )
            VStack(alignment: .leading, spacing: 3) {
                titleLine(row)
                Text(model.subtitle(row))
                    .font(SchibstedGrotesk.medium.font(size: 11))
                    .foregroundStyle(Theme.color.muted)
                    .lineLimit(1)
                HStack(spacing: 8) {
                    Sparkline(values: model.contour(row))
                        .frame(width: 40, height: 14)
                    Text(names.isEmpty ? "No notes" : names.joined(separator: " "))
                        .font(SchibstedGrotesk.semiBold.font(size: 12))
                        .foregroundStyle(Theme.color.ink.opacity(0.8))
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                if optionHeld, hovered == row {
                    Text(breakdownText(row))
                        .font(.system(size: 10, weight: .medium).monospaced())
                        .foregroundStyle(Theme.color.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 0)
        }
    }

    /// The family and the row's badge.
    private func titleLine(_ row: FillEditorModel.Row) -> some View {
        HStack(spacing: 6) {
            Text(model.title(row))
                .font(SchibstedGrotesk.bold.font(size: 13))
                .foregroundStyle(Theme.color.ink)
                .lineLimit(1)
            if row == .saved {
                badge("Saved")
            } else if model.isEdited(row) {
                badge("Edited")
            } else if row == .candidate(0), model.editing == nil {
                badge("Suggested")
            }
        }
    }

    /// "Revert to A" under the selected row once it is edited.
    @ViewBuilder
    private func revertButton(_ row: FillEditorModel.Row, letter: String) -> some View {
        if model.selected == row, model.isEdited(row), row != .scratch {
            Button(row == .saved ? "Revert to Saved" : "Revert to \(letter)") {
                model.revert()
            }
            .buttonStyle(.link)
            .font(SchibstedGrotesk.semiBold.font(size: 12))
            .padding(.leading, 37)
            .accessibilityIdentifier(AccessibilityID.fillRevert)
        }
    }

    private func playButton(_ row: FillEditorModel.Row, letter: String) -> some View {
        let sounding = model.isSounding(row)
        return Button {
            model.toggle(row)
        } label: {
            Image(systemName: sounding ? "stop.fill" : "play.fill")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(sounding ? Theme.color.cueText : Theme.color.ink)
                .frame(width: 24, height: 24)
                .background(Circle().fill(Theme.color.ground))
                .overlay(Circle().strokeBorder(Theme.color.controlBorder, lineWidth: 1))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(!model.canPlay)
        .help(model.canPlay ? (sounding ? "Stop" : "Play this fill over its chords")
            : SoundGate.offHelp)
        .accessibilityLabel(sounding ? "Stop" : "Play")
        .accessibilityIdentifier(AccessibilityID.fillCandidatePlay(letter))
    }

    private var moreButton: some View {
        Button {
            withAnimation(.snappy(duration: 0.18)) { model.showsMore.toggle() }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: "chevron.right")
                    .font(.system(size: 9, weight: .bold))
                    .rotationEffect(.degrees(model.showsMore ? 90 : 0))
                Text(model.showsMore ? "Fewer" : "More")
                    .font(SchibstedGrotesk.semiBold.font(size: 12))
            }
            .foregroundStyle(Theme.color.muted)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(model.showsMore ? "Fewer options" : "More options")
        .accessibilityIdentifier(AccessibilityID.fillMore)
    }

    private var scratchRow: some View {
        let selected = model.selected == .scratch
        return Button {
            model.select(.scratch)
        } label: {
            HStack(spacing: 9) {
                Image(systemName: "plus")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(selected ? Theme.color.ground : Theme.color.ink)
                    .frame(width: 20, height: 20)
                    .background(
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .fill(selected ? Theme.color.cue : Theme.color.surfaceAlt),
                    )
                Text("Start from scratch")
                    .font(SchibstedGrotesk.semiBold.font(size: 13))
                    .foregroundStyle(Theme.color.ink)
                Spacer(minLength: 0)
            }
            .padding(.vertical, 6)
            .padding(.horizontal, 8)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(selected ? Theme.color.surfaceAlt : .clear),
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityIdentifier(AccessibilityID.fillScratch)
    }

    private func badge(_ text: String) -> some View {
        Text(text)
            .font(SchibstedGrotesk.semiBold.font(size: 10))
            .foregroundStyle(Theme.color.muted)
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background(Capsule().strokeBorder(Theme.color.lineStrong, lineWidth: 1))
    }

    private func breakdownText(_ row: FillEditorModel.Row) -> String {
        let terms = model.breakdown(row)
        guard !terms.isEmpty else { return "No score" }
        return terms.map { "\($0.term) \(String(format: "%+.2f", $0.value))" }
            .joined(separator: "\n")
    }
}

/// A tiny contour of a fill's pitches, left to right.
struct Sparkline: View {
    let values: [Int]

    var body: some View {
        Canvas { context, size in
            guard values.count > 1, let low = values.min(), let high = values.max() else {
                if values.count == 1 {
                    let dot = CGRect(x: 0, y: size.height / 2 - 1.5, width: 3, height: 3)
                    context.fill(Path(ellipseIn: dot), with: .color(Theme.color.cueText))
                }
                return
            }
            let span = Double(max(1, high - low))
            let width = min(size.width, CGFloat(values.count - 1) * 14)
            var path = Path()
            for (index, value) in values.enumerated() {
                let point = CGPoint(
                    x: width * CGFloat(index) / CGFloat(values.count - 1),
                    y: 1.5 + (size.height - 3) * (1 - CGFloat(Double(value - low) / span)),
                )
                if index == 0 {
                    path.move(to: point)
                } else {
                    path.addLine(to: point)
                }
            }
            context.stroke(
                path,
                with: .color(Theme.color.cueText),
                style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round),
            )
        }
        .accessibilityHidden(true)
    }
}
