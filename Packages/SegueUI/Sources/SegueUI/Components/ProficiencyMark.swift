// Phase 2 frozen interface (docs/phases/2-interfaces.md). Owner: unit D; used by C (search
// results) and D (library, builder).

import Library
import SwiftUI

/// The proficiency mark (brand.md section 7): an 8px dot plus label at 14 / 600. Learning is
/// an outlined ring, Ready a filled grey dot, Pro a filled ink dot (white on stage), so the
/// states differ by fill and lightness, not hue.
public struct ProficiencyMark: View {
    let proficiency: Proficiency
    var showsLabel = true

    public init(_ proficiency: Proficiency, showsLabel: Bool = true) {
        self.proficiency = proficiency
        self.showsLabel = showsLabel
    }

    public var body: some View {
        HStack(spacing: 6) {
            dot
            if showsLabel {
                Text(Self.label(proficiency))
                    .font(SchibstedGrotesk.semiBold.font(size: 14))
                    .foregroundStyle(Theme.color.ink)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Self.label(proficiency))
    }

    private var dot: some View {
        ProficiencyDot(proficiency)
    }

    /// "Learning", "Ready", "Pro".
    public static func label(_ proficiency: Proficiency) -> String {
        switch proficiency {
        case .learning: "Learning"
        case .ready: "Ready"
        case .pro: "Pro"
        }
    }
}

/// The 8px proficiency dot alone (brand.md section 7). `inverted` draws it for an ink
/// ground (a chip that is on): the filled dots take the paper colour.
public struct ProficiencyDot: View {
    let proficiency: Proficiency
    var inverted = false

    public init(_ proficiency: Proficiency, inverted: Bool = false) {
        self.proficiency = proficiency
        self.inverted = inverted
    }

    public var body: some View {
        Group {
            switch proficiency {
            case .learning:
                Circle().strokeBorder(
                    inverted ? Theme.color.ground : Theme.color.muted,
                    lineWidth: 2,
                )
            case .ready:
                Circle().fill(inverted ? Theme.color.ground.opacity(0.6) : Theme.color.muted)
            case .pro:
                Circle().fill(inverted ? Theme.color.ground : Theme.color.ink)
            }
        }
        .frame(width: 8, height: 8)
        .accessibilityHidden(true)
    }
}
