import SwiftUI

/// Every colour token as a labelled swatch, in `design/tokens.json` order. Used by the token
/// integration test (which samples each swatch's pixels) and handy as a design preview.
public struct ThemeSwatchView: View {
    /// Side length of each square swatch, in points.
    public static let swatchSize: CGFloat = 24

    public init() {}

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(ColorTokenValue.all, id: \.name) { token in
                HStack(spacing: 8) {
                    Rectangle()
                        .fill(Self.color(named: token.name))
                        .frame(width: Self.swatchSize, height: Self.swatchSize)
                    Text(token.name)
                        .font(Theme.font.label)
                        .foregroundStyle(Theme.color.ink)
                }
            }
        }
        .padding(.trailing, 8)
        .background(Theme.color.ground)
    }

    /// The token accessor for a token name, so the swatches exercise the public API.
    static func color(named name: String) -> Color {
        let tokens = Theme.color
        let byName: [String: Color] = [
            "cue": tokens.cue,
            "cueText": tokens.cueText,
            "ink": tokens.ink,
            "ground": tokens.ground,
            "muted": tokens.muted,
            "line": tokens.line,
            "played": tokens.played,
            "lineStrong": tokens.lineStrong,
            "surfaceAlt": tokens.surfaceAlt,
        ]
        return byName[name] ?? .clear
    }
}

#Preview("Light") {
    ThemeSwatchView().environment(\.colorScheme, .light)
}

#Preview("Dark") {
    ThemeSwatchView().environment(\.colorScheme, .dark)
}
