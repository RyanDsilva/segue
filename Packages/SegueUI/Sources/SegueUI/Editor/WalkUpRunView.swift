import Editing
import SwiftUI

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
            .help(uiString("Shows other walk-ups"))
            .accessibilityLabel(Self.spokenName(run))
            .accessibilityHint(uiString("Shows other walk-ups"))
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
