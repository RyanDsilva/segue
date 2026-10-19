#if os(macOS)
    import Library
    import SwiftUI

    /// The Learning / Ready / Pro chips. Clicking the selected chip clears it, so
    /// `onChange` receives `nil`. Writes the sidecar through its caller.
    struct ProficiencyPicker: View {
        let selection: Proficiency?
        var isDisabled = false
        let onChange: (Proficiency?) -> Void

        var body: some View {
            HStack(spacing: 6) {
                ForEach(Proficiency.allCases, id: \.self) { level in
                    let isOn = selection == level
                    let title = ProficiencyMark.label(level)
                    FilterChip(isOn: isOn) {
                        onChange(isOn ? nil : level)
                    } label: {
                        HStack(spacing: 6) {
                            ProficiencyDot(level, inverted: isOn)
                            Text(title)
                        }
                    }
                    .accessibilityLabel(title)
                    .accessibilityIdentifier(AccessibilityID.songProficiency(level))
                    .help(isOn ? "Clear the proficiency" : "Mark as \(title)")
                }
            }
            .disabled(isDisabled)
        }
    }
#endif
