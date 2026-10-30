// P8-4b (docs/phases/8-workstreams/P8-4-bass.md section 8.9). The walk-up picker: the ranked
// candidates of one chord change and "Nothing here", in the editor preview. Silent; P8-6
// adds play buttons to the same rows.

import Editing
import Library
import MusicTheory
import SwiftUI

/// One change as the popover shows it.
struct WalkUpDetails {
    var change: ChordChange
    /// "Verse 1"; nil for loose lines.
    var section: String?
    /// "Pop".
    var feel: String
}

/// What the preview's walk-up runs can do, injected by the editor.
struct WalkUpPicking {
    /// False for a song that is not saved yet (no sidecar to write).
    var isEnabled: Bool
    var details: @MainActor (ChangeID) -> WalkUpDetails?
    /// nil: "Nothing here".
    var choose: @MainActor (ChordChange, WalkUpCandidate?) -> Void
    var reset: @MainActor (ChordChange) -> Void
}

extension EnvironmentValues {
    @Entry var walkUpPicking: WalkUpPicking?
}

/// A walk-up run in a preview: plain text, or a button that opens the picker.
struct WalkUpRunView: View {
    let run: ApproachRun
    let size: CGFloat
    /// Set by the line's VoiceOver action for this run: opens the picker too.
    @Binding var requested: ChangeID?
    @Environment(\.walkUpPicking) private var picking
    @State private var isPresented = false
    @State private var isHovered = false

    var body: some View {
        if let picking, picking.isEnabled {
            Button {
                isPresented = true
            } label: {
                label.underline(isHovered)
            }
            .buttonStyle(.plain)
            .pointerStyle(.link)
            .onHover { isHovered = $0 }
            .help("Shows other walk-ups")
            .accessibilityLabel(Self.spokenName(run))
            .accessibilityHint("Shows other walk-ups")
            .accessibilityIdentifier(AccessibilityID.sheetWalkUp)
            .popover(isPresented: presented, arrowEdge: .bottom) {
                WalkUpPopover(id: run.change, picking: picking) {
                    presented.wrappedValue = false
                }
            }
        } else {
            label
        }
    }

    /// Open from a click or from the line's VoiceOver action.
    private var presented: Binding<Bool> {
        Binding(
            get: { isPresented || requested == run.change },
            set: { isOn in
                isPresented = isOn
                if !isOn, requested == run.change {
                    requested = nil
                }
            },
        )
    }

    /// "Walk-up into C: A, B" (section 8.12), the run's button and the line's action.
    static func spokenName(_ run: ApproachRun) -> String {
        let parts = run.accessibility.components(separatedBy: " into ")
        let notes = (parts.first ?? "")
            .replacingOccurrences(of: "walk up ", with: "")
            .replacingOccurrences(of: "walk down ", with: "")
            .replacingOccurrences(of: "walk ", with: "")
        guard parts.count == 2 else { return "Walk-up: \(run.accessibility)" }
        return "Walk-up into \(parts[1]): \(notes)"
    }

    /// A pick reads as "yours": ink at 70% instead of muted.
    private var label: some View {
        Text(run.text)
            .font(SchibstedGrotesk.medium.font(size: size))
            .foregroundStyle(run.isPick ? Theme.color.ink.opacity(0.7) : Theme.color.muted)
    }
}

extension View {
    /// A lyric line is one VoiceOver element, so each walk-up run on it is reached as one of
    /// the line's actions ("Walk-up into C: A, B"), which opens that run's picker.
    func walkUpActions(_ runs: [ApproachRun], requested: Binding<ChangeID?>) -> some View {
        modifier(WalkUpActions(runs: runs, requested: requested))
    }
}

private struct WalkUpActions: ViewModifier {
    let runs: [ApproachRun]
    @Binding var requested: ChangeID?
    @Environment(\.walkUpPicking) private var picking

    func body(content: Content) -> some View {
        content.accessibilityActions {
            if picking?.isEnabled == true {
                ForEach(runs, id: \.change) { run in
                    Button(WalkUpRunView.spokenName(run)) { requested = run.change }
                }
            }
        }
    }
}

/// The ranked candidates (A-D), then "Nothing here", then "Reset to suggestion". Up and Down
/// move, Return chooses, Esc closes; hovering a row with Option held shows its score
/// breakdown (for tuning the weights, section 8.9).
struct WalkUpPopover: View {
    let id: ChangeID
    let picking: WalkUpPicking
    let dismiss: () -> Void
    /// The keyboard (and hover) row: the options in rank order, then "Nothing here".
    @State private var highlighted: Int?
    @State private var optionHeld = false
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let details = picking.details(id) {
                header(details)
                rows(details.change)
                    .focusable()
                    .focusEffectDisabled()
                    .focused($focused)
                    .onKeyPress(keys: [.upArrow, .downArrow, .return]) { press in
                        handle(press.key, change: details.change)
                    }
                    .onAppear {
                        highlighted = highlighted ?? shownIndex(details.change)
                        focused = true
                    }
            } else {
                Text("This change is no longer in the song.")
                    .font(Theme.font.body)
                    .foregroundStyle(Theme.color.muted)
            }
        }
        .padding(14)
        .frame(width: 300, alignment: .leading)
        #if os(macOS)
            .onModifierKeysChanged(mask: .option) { _, new in
                optionHeld = new.contains(.option)
            }
        #endif
            .accessibilityIdentifier(AccessibilityID.walkUpPopover)
    }

    /// The options shown as rows (a `hold` is the "Nothing here" row).
    private static func options(_ change: ChordChange) -> [WalkUpCandidate] {
        change.candidates.filter { $0.kind != .hold }
    }

    /// The row of the walk-up shown now: the pick, else the suggestion, else "Nothing here".
    private func shownIndex(_ change: ChordChange) -> Int {
        let options = Self.options(change)
        guard let shown = change.pickCandidate ?? change.candidates.first, shown.kind != .hold
        else { return options.count }
        return options.firstIndex { Self.same($0, shown) } ?? 0
    }

    private func handle(_ key: KeyEquivalent, change: ChordChange) -> KeyPress.Result {
        let options = Self.options(change)
        let last = options.count
        let current = highlighted ?? shownIndex(change)
        switch key {
        case .upArrow:
            highlighted = max(0, current - 1)
        case .downArrow:
            highlighted = min(last, current + 1)
        default:
            picking.choose(change, current < last ? options[current] : nil)
            dismiss()
        }
        return .handled
    }

    private func header(_ details: WalkUpDetails) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("\(details.change.fromName) \u{2192} \(details.change.toName)")
                .font(SchibstedGrotesk.bold.font(size: 15))
                .foregroundStyle(Theme.color.ink)
            Text([details.section, details.feel].compactMap(\.self).joined(separator: " \u{00B7} "))
                .font(SchibstedGrotesk.medium.font(size: 12))
                .foregroundStyle(Theme.color.muted)
        }
    }

    @ViewBuilder
    private func rows(_ change: ChordChange) -> some View {
        let options = Self.options(change)
        let shown = change.pickCandidate ?? change.candidates.first
        if options.isEmpty {
            Text("No walk-up here. " + (change.suppressed?.reason ?? ""))
                .font(SchibstedGrotesk.medium.font(size: 12))
                .foregroundStyle(Theme.color.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
        VStack(alignment: .leading, spacing: 2) {
            ForEach(Array(options.enumerated()), id: \.offset) { index, candidate in
                row(
                    letter: String(UnicodeScalar(UInt8(65 + index))),
                    candidate: candidate,
                    change: change,
                    suggested: candidate == change.candidates.first,
                    selected: shown.map { Self.same($0, candidate) } ?? false,
                )
                .background(highlight(index))
                .onHover {
                    if $0 {
                        highlighted = index
                    }
                }
                .accessibilityIdentifier(AccessibilityID.walkUpOption(index))
            }
            nothingRow(change, selected: shown.map { $0.kind == .hold } ?? true)
                .background(highlight(options.count))
                .onHover {
                    if $0 {
                        highlighted = options.count
                    }
                }
        }
        if change.pick != nil {
            Button("Reset to suggestion") {
                picking.reset(change)
                dismiss()
            }
            .accessibilityIdentifier(AccessibilityID.walkUpReset)
        }
    }

    private func row(
        letter: String,
        candidate: WalkUpCandidate,
        change: ChordChange,
        suggested: Bool,
        selected: Bool,
    ) -> some View {
        let notes = candidate.notes.map(\.chartName)
        let marked = zip(notes, candidate.chromatic).map { $0 + ($1 ? "\u{00B0}" : "") }
        let description = Self.describe(candidate, target: change.toName)
        return Button {
            picking.choose(change, candidate)
            dismiss()
        } label: {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(letter)
                    .font(SchibstedGrotesk.medium.font(size: 12))
                    .foregroundStyle(Theme.color.muted)
                    .frame(width: 12, alignment: .leading)
                VStack(alignment: .leading, spacing: 1) {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(marked.joined(separator: " ") + " \u{203A}")
                            .font(SchibstedGrotesk.bold.font(size: 15))
                            .foregroundStyle(Theme.color.ink)
                        Text(candidate.degrees.joined(separator: " "))
                            .font(SchibstedGrotesk.medium.font(size: 12))
                            .foregroundStyle(Theme.color.muted)
                    }
                    Text(description + (suggested ? " \u{00B7} Suggested" : ""))
                        .font(SchibstedGrotesk.medium.font(size: 12))
                        .foregroundStyle(Theme.color.muted)
                    if optionHeld, highlighted == Self.options(change).firstIndex(of: candidate) {
                        Text(Self.breakdown(candidate))
                            .font(.system(size: 11, weight: .medium).monospaced())
                            .foregroundStyle(Theme.color.muted)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityIdentifier(AccessibilityID.walkUpBreakdown)
                    }
                }
                Spacer(minLength: 4)
                if selected {
                    Image(systemName: "checkmark")
                        .foregroundStyle(Theme.color.cue)
                }
            }
            .padding(.vertical, 4)
            .padding(.horizontal, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            "Option \(letter), \(notes.joined(separator: ", ")), \(description.lowercased())"
                + (suggested ? ", suggested" : "") + (selected ? ", selected" : ""),
        )
    }

    private func nothingRow(_ change: ChordChange, selected: Bool) -> some View {
        Button {
            picking.choose(change, nil)
            dismiss()
        } label: {
            HStack {
                Text("Nothing here")
                    .font(Theme.font.body)
                    .foregroundStyle(Theme.color.ink)
                Spacer(minLength: 4)
                if selected {
                    Image(systemName: "checkmark")
                        .foregroundStyle(Theme.color.cue)
                }
            }
            .padding(.vertical, 4)
            .padding(.horizontal, 6)
            .padding(.leading, 20)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Nothing here" + (selected ? ", selected" : ""))
        .accessibilityIdentifier(AccessibilityID.walkUpNothing)
    }

    /// The keyboard row's tint.
    private func highlight(_ index: Int) -> some View {
        RoundedRectangle(cornerRadius: 6, style: .continuous)
            .fill(highlighted == index ? Theme.color.line : Color.clear)
    }

    /// "prior 3 + resolution 2 + direction 1.5 = 6.5": each weighted term, in the
    /// vocabulary's order, summing to the score.
    static func breakdown(_ candidate: WalkUpCandidate) -> String {
        let terms = WalkUpTerm.allCases.compactMap { term in
            candidate.breakdown[term].map { "\(term.rawValue) \(number($0))" }
        }
        return terms.joined(separator: " + ") + " = \(number(candidate.score))"
    }

    private static func number(_ value: Double) -> String {
        value == value.rounded() ? String(Int(value)) : String(format: "%.1f", value)
    }

    /// Same notes and kind (a pick rebuilt from its offsets equals the generated one).
    private static func same(_ left: WalkUpCandidate, _ right: WalkUpCandidate) -> Bool {
        left.kind == right.kind && left.offsets == right.offsets
    }

    /// The plain description of a candidate's kind ("Scale walk up", "Fifth of C").
    static func describe(_ candidate: WalkUpCandidate, target: String) -> String {
        let way = candidate.direction == .down ? "down" : "up"
        return switch candidate.kind {
        case .scaleWalk: "Scale walk \(way)"
        case .scaleChrom: "Scale walk with a half step"
        case .diatonicNeighbour: "Step into the chord"
        case .chromBelow: "Half step below"
        case .chromAbove: "Half step above"
        case .fifth: "Fifth of \(target)"
        case .doubleChromAbove: "Two half steps from above"
        case .octavePickup: "Octave pickup"
        case .hold: "Nothing - the chords already walk"
        }
    }
}
