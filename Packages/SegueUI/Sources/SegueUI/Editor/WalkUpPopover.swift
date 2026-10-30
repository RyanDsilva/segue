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
    /// Hearing the options (P8-6 10.2): the Loop switch and the option sounding now
    /// (`options.count` is "Nothing here").
    @Environment(\.walkUpAudition) private var audition
    @State private var listening: WalkUpListening?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let details = picking.details(id) {
                header(details)
                rows(details.change)
                    .focusable()
                    .focusEffectDisabled()
                    .focused($focused)
                    .onKeyPress(keys: [.upArrow, .downArrow, .return, .space]) { press in
                        handle(press.key, change: details.change)
                    }
                    .onKeyPress(characters: CharacterSet(charactersIn: "abcdABCD")) { press in
                        letter(press.characters, change: details.change)
                    }
                    .onChange(of: highlighted) { _, new in
                        switchWhileLooping(to: new, change: details.change)
                    }
                    .onAppear {
                        if listening == nil, let audition {
                            listening = WalkUpListening(audition: audition)
                        }
                        highlighted = highlighted ?? shownIndex(details.change)
                        focused = true
                    }
                    .onDisappear { stopSound() }
            } else {
                Text("This change is no longer in the song.")
                    .font(Theme.font.body)
                    .foregroundStyle(Theme.color.muted)
            }
        }
        .padding(14)
        .frame(width: audition == nil ? 300 : 350, alignment: .leading)
        #if os(macOS)
            .onModifierKeysChanged(mask: .option) { _, new in
                optionHeld = new.contains(.option)
            }
        #endif
            .accessibilityIdentifier(AccessibilityID.walkUpPopover)
    }

    /// The options shown as rows (a `hold` is the "Nothing here" row).
    static func options(_ change: ChordChange) -> [WalkUpCandidate] {
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
        case .space:
            guard audition?.isEnabled == true else { return .ignored }
            toggleSound(current, change: change)
        default:
            pick(change, current < last ? options[current] : nil)
        }
        return .handled
    }

    private func header(_ details: WalkUpDetails) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline) {
                Text("\(details.change.fromName) \u{2192} \(details.change.toName)")
                    .font(SchibstedGrotesk.bold.font(size: 15))
                    .foregroundStyle(Theme.color.ink)
                Spacer(minLength: 8)
                if let audition {
                    Toggle("Loop", isOn: Binding(
                        get: { listening?.looping ?? false },
                        set: { isOn in
                            listening?.setLooping(
                                isOn,
                                { candidate($0, change: details.change) },
                                change: details.change,
                            )
                        },
                    ))
                    .toggleStyle(.switch)
                    .controlSize(.mini)
                    .font(SchibstedGrotesk.medium.font(size: 12))
                    .disabled(!audition.isEnabled)
                    .help(
                        audition.isEnabled ? "Repeat the change; choose another option to switch"
                            : SoundGate.offHelp,
                    )
                    .accessibilityLabel("Loop this change")
                    .accessibilityIdentifier(AccessibilityID.walkUpLoop)
                }
            }
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
        let index = Int(letter.unicodeScalars.first?.value ?? 65) - 65
        let spoken = "option \(letter), \(notes.joined(separator: ", ")) into \(change.toName)"
        return HStack(spacing: 0) {
            if audition != nil {
                playButton(index, change: change, label: spoken)
            }
            rowButton(
                letter: letter,
                candidate: candidate,
                change: change,
                suggested: suggested,
                selected: selected,
            )
            useButton(index, change: change)
        }
    }

    private func rowButton(
        letter: String,
        candidate: WalkUpCandidate,
        change: ChordChange,
        suggested: Bool,
        selected: Bool,
    ) -> some View {
        let notes = candidate.notes.map(\.chartName)
        let marked = zip(notes, candidate.chromatic).map { $0 + ($1 ? "\u{00B0}" : "") }
        let description = Self.describe(candidate, target: change.toName)
        let index = Int(letter.unicodeScalars.first?.value ?? 65) - 65
        return Button {
            rowClicked(index, change: change)
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
        .accessibilityIdentifier(AccessibilityID.walkUpOption(index))
    }

    private func nothingRow(_ change: ChordChange, selected: Bool) -> some View {
        let index = Self.options(change).count
        return HStack(spacing: 0) {
            if audition != nil {
                playButton(
                    index,
                    change: change,
                    label: "nothing here, \(change.fromName) into \(change.toName)",
                )
            }
            nothingButton(change, selected: selected)
            useButton(index, change: change)
        }
    }

    private func nothingButton(_ change: ChordChange, selected: Bool) -> some View {
        Button {
            rowClicked(Self.options(change).count, change: change)
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
}

extension WalkUpPopover {
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

extension WalkUpPopover {
    /// A-D highlight that option (switching what loops).
    private func letter(_ characters: String, change: ChordChange) -> KeyPress.Result {
        guard let scalar = characters.uppercased().unicodeScalars.first else { return .ignored }
        let index = Int(scalar.value) - 65
        guard Self.options(change).indices.contains(index) else { return .ignored }
        highlighted = index
        return .handled
    }

    /// Saves the pick (P8-4b) after stopping any sound, and closes.
    private func pick(_ change: ChordChange, _ candidate: WalkUpCandidate?) {
        stopSound()
        picking.choose(change, candidate)
        dismiss()
    }

    // MARK: Sound (P8-6 10.2)

    /// The option at `index` (nil: "Nothing here").
    private func candidate(_ index: Int, change: ChordChange) -> WalkUpCandidate? {
        let options = Self.options(change)
        return options.indices.contains(index) ? options[index] : nil
    }

    private func isSounding(_ index: Int) -> Bool {
        listening?.isSounding(index) ?? false
    }

    private func toggleSound(_ index: Int, change: ChordChange) {
        listening?.toggle(index, candidate(index, change: change), change: change)
        highlighted = index
    }

    private func switchWhileLooping(to index: Int?, change: ChordChange) {
        guard let index else { return }
        let name = index < Self.options(change).count
            ? "option \(String(UnicodeScalar(UInt8(65 + index))))" : "nothing here"
        listening?.select(index, candidate(index, change: change), change: change, name: name)
    }

    private func stopSound() {
        listening?.stop()
    }

    /// A click on a row picks it, except while a loop sounds, when it switches the option.
    private func rowClicked(_ index: Int, change: ChordChange) {
        if listening?.isLoopingSound == true {
            highlighted = index
        } else {
            pick(change, candidate(index, change: change))
        }
    }

    /// The ▶ / ■ button of a row (P8-6 10.2).
    private func playButton(_ index: Int, change: ChordChange, label: String) -> some View {
        WalkUpPlayButton(
            playing: isSounding(index),
            isEnabled: audition?.isEnabled == true,
            letter: index < Self.options(change).count
                ? String(UnicodeScalar(UInt8(65 + index))) : "nothing",
            label: label,
        ) {
            toggleSound(index, change: change)
        }
    }

    /// "Use this" on the highlighted row while hearing options.
    @ViewBuilder
    private func useButton(_ index: Int, change: ChordChange) -> some View {
        if audition != nil, highlighted == index {
            Button("Use this") {
                pick(change, candidate(index, change: change))
            }
            .buttonStyle(.segueSecondary)
            .controlSize(.mini)
            .accessibilityIdentifier(AccessibilityID.walkUpUse)
        }
    }
}
