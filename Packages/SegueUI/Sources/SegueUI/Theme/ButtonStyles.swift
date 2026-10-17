import SwiftUI

/// Segue's button styles (docs/brand.md section 7, "Buttons"):
///
/// - **Primary:** ink fill, paper text (`ground`), so in the dark appearance it is the light
///   ink tone with stage-coloured text.
/// - **Secondary:** paper (`ground`) fill, 1px `line` border, ink text.
///
/// Both are 600 weight with radius 8. `.large` controls use the brand metrics (15pt, padding
/// 10x18); regular and smaller controls (toolbars, sheets, list rows) use compact variants.
/// macOS 26 toolbars default to large controls, so toolbar buttons set `.controlSize(.regular)`
/// to sit at the height of the system toolbar capsules. Coral is never a button fill: it is
/// reserved for the cue.
///
/// Apply with `.buttonStyle(.seguePrimary)` / `.buttonStyle(.segueSecondary)`.
public struct SegueButtonStyle: ButtonStyle {
    public enum Prominence: Sendable {
        case primary
        case secondary
    }

    let prominence: Prominence

    public init(_ prominence: Prominence) {
        self.prominence = prominence
    }

    public func makeBody(configuration: Configuration) -> some View {
        SegueButtonBody(configuration: configuration, prominence: prominence)
    }
}

public extension ButtonStyle where Self == SegueButtonStyle {
    /// Ink fill, paper text. One per surface: the action the screen exists for.
    static var seguePrimary: SegueButtonStyle {
        SegueButtonStyle(.primary)
    }

    /// Paper fill with a `line` border.
    static var segueSecondary: SegueButtonStyle {
        SegueButtonStyle(.secondary)
    }
}

/// Metrics for one control size.
struct SegueButtonMetrics: Equatable {
    var fontSize: CGFloat
    var horizontalPadding: CGFloat
    var verticalPadding: CGFloat
    var cornerRadius: CGFloat = 8

    static func forControlSize(_ size: ControlSize) -> Self {
        switch size {
        case .extraLarge, .large:
            // brand.md: 15 / 600, padding 10x18, radius 8.
            Self(fontSize: 15, horizontalPadding: 18, verticalPadding: 10)
        case .mini, .small:
            Self(fontSize: 12, horizontalPadding: 10, verticalPadding: 3, cornerRadius: 6)
        default:
            Self(fontSize: 13, horizontalPadding: 14, verticalPadding: 7)
        }
    }
}

private struct SegueButtonBody: View {
    let configuration: ButtonStyle.Configuration
    let prominence: SegueButtonStyle.Prominence
    @Environment(\.controlSize) private var controlSize
    @Environment(\.isEnabled) private var isEnabled
    @State private var isHovered = false

    var body: some View {
        let metrics = SegueButtonMetrics.forControlSize(controlSize)
        let shape = RoundedRectangle(cornerRadius: metrics.cornerRadius, style: .continuous)
        configuration.label
            .font(SchibstedGrotesk.semiBold.font(size: metrics.fontSize))
            .lineLimit(1)
            .foregroundStyle(foreground)
            .padding(.horizontal, metrics.horizontalPadding)
            .padding(.vertical, metrics.verticalPadding)
            .background {
                ZStack {
                    shape.fill(fill)
                    // Hover and press feedback under the label, without a new colour:
                    // primary tints towards paper, secondary towards ink.
                    shape.fill(
                        (prominence == .primary ? Theme.color.ground : Theme.color.ink)
                            .opacity(feedbackOpacity),
                    )
                    if prominence == .secondary {
                        shape.strokeBorder(Theme.color.line, lineWidth: 1)
                    }
                }
            }
            .contentShape(shape)
            .opacity(isEnabled ? 1 : 0.4)
            .onHover { isHovered = $0 }
            .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
    }

    private var foreground: Color {
        prominence == .primary ? Theme.color.ground : Theme.color.ink
    }

    private var fill: Color {
        prominence == .primary ? Theme.color.ink : Theme.color.ground
    }

    private var feedbackOpacity: Double {
        guard isEnabled else { return 0 }
        if configuration.isPressed {
            return prominence == .primary ? 0.22 : 0.1
        }
        return isHovered ? 0.06 : 0
    }
}
