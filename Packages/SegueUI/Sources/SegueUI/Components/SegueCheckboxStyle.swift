import SwiftUI

/// A brand checkbox (docs/brand.md section 7): 15 pt, radius 4; on is an ink fill with a paper
/// check mark, off is a `controlBorder` outline (3:1 under Increase Contrast). The label is
/// part of the hit area. VoiceOver reads it as a checkbox with its on/off value.
struct SegueCheckboxStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        SegueCheckbox(configuration: configuration)
    }
}

extension ToggleStyle where Self == SegueCheckboxStyle {
    static var segueCheckbox: SegueCheckboxStyle {
        SegueCheckboxStyle()
    }
}

private struct SegueCheckbox: View {
    let configuration: ToggleStyle.Configuration
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        Button {
            configuration.isOn.toggle()
        } label: {
            HStack(alignment: .top, spacing: 10) {
                box
                    .padding(.top, 1)
                configuration.label
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .opacity(isEnabled ? 1 : 0.4)
        .accessibilityRepresentation {
            Toggle(isOn: configuration.$isOn) { configuration.label }
        }
    }

    private var box: some View {
        let shape = RoundedRectangle(cornerRadius: 4, style: .continuous)
        return ZStack {
            if configuration.isOn {
                shape.fill(Theme.color.ink)
                Image(systemName: "checkmark")
                    .font(.system(size: 9, weight: .heavy))
                    .foregroundStyle(Theme.color.ground)
            } else {
                shape.fill(Theme.color.ground)
                shape.strokeBorder(Theme.color.controlBorder, lineWidth: 1)
            }
        }
        .frame(width: 15, height: 15)
    }
}
