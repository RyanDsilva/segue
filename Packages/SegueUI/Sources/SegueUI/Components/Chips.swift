import SwiftUI

/// A toggleable filter chip (brand.md section 7, "Chips"): 13 / 600 text, padding 4x10,
/// radius 6, 1px `controlBorder`, no fill. On, it takes the ink fill with paper text, like a
/// primary button (coral stays reserved for the cue).
struct FilterChip<Label: View>: View {
    let isOn: Bool
    let action: () -> Void
    @ViewBuilder let label: () -> Label

    var body: some View {
        Button(action: action) {
            label()
                .font(SchibstedGrotesk.semiBold.font(size: 13))
                .foregroundStyle(isOn ? Theme.color.ground : Theme.color.ink)
                .lineLimit(1)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(isOn ? Theme.color.ink : Color.clear),
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .strokeBorder(
                            isOn ? Theme.color.ink : Theme.color.controlBorder,
                            lineWidth: 1,
                        )
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}

extension FilterChip where Label == Text {
    init(_ title: String, isOn: Bool, action: @escaping () -> Void) {
        self.init(isOn: isOn, action: action) { Text(title) }
    }
}

/// The key chip of a song row: just the key ("G"), 13 / 600, padding 3x8, radius 6.
struct KeyChip: View {
    let key: String
    @Environment(\.onHighlight) private var onHighlight

    var body: some View {
        Text(key)
            .font(SchibstedGrotesk.semiBold.font(size: 13))
            .foregroundStyle(onHighlight ? Color.white : Theme.color.ink)
            .lineLimit(1)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .overlay {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(
                        onHighlight ? Color.white.opacity(0.6) : Theme.color.controlBorder,
                        lineWidth: 1,
                    )
            }
    }
}

/// A 1px hairline in `line` (dividers between rows and panes).
struct Rule: View {
    var axis: Axis = .horizontal

    var body: some View {
        Rectangle()
            .fill(Theme.color.line)
            .frame(
                width: axis == .vertical ? 1 : nil,
                height: axis == .horizontal ? 1 : nil,
            )
            .accessibilityHidden(true)
    }
}
