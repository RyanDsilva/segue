import SwiftUI

/// Segue's design tokens (docs/brand.md). The single entry point for colour and type in the
/// UI: `Theme.color.cueText`, `Theme.font.liveLyric(size: 24)`.
///
/// Colours are Asset Catalog colour sets with Any/Dark appearances, generated from
/// `design/tokens.json` by `scripts/gen-tokens`. Fonts are the bundled Schibsted Grotesk
/// statics; call `Theme.registerFonts()` once at startup before any view renders.
public enum Theme {
    /// Colour tokens (brand.md section 5). Each resolves per appearance (light UI / dark stage).
    public static let color = ColorTokens()

    /// Type scale (brand.md section 6), set in Schibsted Grotesk.
    public static let font = FontTokens()

    /// Letter-spacing for the tight display roles, as points per point of font size
    /// (apply with `.tracking(Theme.tracking.display * size)`).
    public static let tracking = TrackingTokens()

    /// The resource bundle holding the token asset catalog and the bundled fonts.
    static let bundle = Bundle.module

    /// Registers the bundled Schibsted Grotesk fonts with Core Text for this process.
    /// Idempotent and safe to call from any thread.
    @discardableResult
    public static func registerFonts() -> Bool {
        FontRegistration.registerBundledFonts()
    }
}
