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
            .accessibilityLabel("Walk-up: \(run.accessibility)")
            .accessibilityIdentifier(AccessibilityID.sheetWalkUp)
            .popover(isPresented: $isPresented, arrowEdge: .bottom) {
                WalkUpPopover(id: run.change, picking: picking) {
                    isPresented = false
                }
            }
        } else {
            label
        }
    }

    /// A pick reads as "yours": ink at 70% instead of muted.
    private var label: some View {
        Text(run.text)
            .font(SchibstedGrotesk.medium.font(size: size))
            .foregroundStyle(run.isPick ? Theme.color.ink.opacity(0.7) : Theme.color.muted)
    }
}

/// The ranked candidates (A-D), then "Nothing here", then "Reset to suggestion".
struct WalkUpPopover: View {
    let id: ChangeID
    let picking: WalkUpPicking
    let dismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let details = picking.details(id) {
                header(details)
                rows(details.change)
            } else {
                Text("This change is no longer in the song.")
                    .font(Theme.font.body)
                    .foregroundStyle(Theme.color.muted)
            }
        }
        .padding(14)
        .frame(width: 300, alignment: .leading)
        .accessibilityIdentifier(AccessibilityID.walkUpPopover)
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
        let options = change.candidates.filter { $0.kind != .hold }
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
                .accessibilityIdentifier(AccessibilityID.walkUpOption(index))
            }
            nothingRow(change, selected: shown.map { $0.kind == .hold } ?? true)
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
