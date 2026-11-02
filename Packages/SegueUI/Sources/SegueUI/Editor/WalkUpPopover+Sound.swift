import SwiftUI

/// A walk-up option's ▶ / ■ button (P8-6 10.2).
struct WalkUpPlayButton: View {
    let playing: Bool
    let isEnabled: Bool
    /// "A" ... "D", or "nothing".
    let letter: String
    /// "option A, A, B into C".
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: playing ? "stop.fill" : "play.fill")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(playing ? Theme.color.cue : Theme.color.muted)
                .frame(width: 20, height: 20)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .help(isEnabled ? (playing ? uiString("Stop") : uiString("Play")) : SoundGate.offHelp)
        .accessibilityLabel(playing ? uiString("Stop \(label)") : uiString("Play \(label)"))
        .accessibilityIdentifier(AccessibilityID.walkUpPlay(letter))
    }
}
