import SwiftUI

/// Schibsted Grotesk type scale (docs/brand.md section 6).
public struct FontTokens: Sendable {
    /// Chord size as a fraction of the lyric size, shared by editor, live view and PDF.
    public static let chordToLyricRatio: CGFloat = 0.82

    /// Wordmark and onboarding: 64 / 800. Pair with `Theme.tracking.display`.
    public let display = SchibstedGrotesk.extraBold.font(size: 64)
    /// Song title and window headers: 28 / 800. Pair with `Theme.tracking.title`.
    public let title = SchibstedGrotesk.extraBold.font(size: 28)
    /// Library and settings headings: 20 / 700.
    public let sectionHeading = SchibstedGrotesk.bold.font(size: 20)
    /// UI body (buttons, lists): 15 / 500.
    public let body = SchibstedGrotesk.medium.font(size: 15)
    /// Section labels, captions, metadata: 13 / 700.
    public let label = SchibstedGrotesk.bold.font(size: 13)

    /// Live-mode lyric text: `size` / 400 (default 24, user minimum 22). Line height 1.25.
    public func liveLyric(size: CGFloat) -> Font {
        SchibstedGrotesk.regular.font(size: size)
    }

    /// Live-mode chord symbol: 0.82 x the lyric `size` / 700, drawn in `Theme.color.cueText`.
    public func liveChord(size: CGFloat) -> Font {
        SchibstedGrotesk.bold.font(size: Self.liveChordSize(forLyricSize: size))
    }

    /// The chord point size for a given lyric point size.
    public static func liveChordSize(forLyricSize lyricSize: CGFloat) -> CGFloat {
        (lyricSize * chordToLyricRatio).rounded()
    }
}

/// Letter-spacing as em fractions (multiply by the font size for SwiftUI `.tracking`).
public struct TrackingTokens: Sendable {
    /// Display / wordmark: -0.045em.
    public let display: CGFloat = -0.045
    /// Titles: -0.035em.
    public let title: CGFloat = -0.035
}

/// The bundled Schibsted Grotesk static faces, by PostScript name.
public enum SchibstedGrotesk: String, CaseIterable, Sendable {
    case regular = "SchibstedGrotesk-Regular"
    case medium = "SchibstedGrotesk-Medium"
    case semiBold = "SchibstedGrotesk-SemiBold"
    case bold = "SchibstedGrotesk-Bold"
    case extraBold = "SchibstedGrotesk-ExtraBold"

    /// A fixed-size SwiftUI font for this face. Registers the bundled fonts on first use, so
    /// the face resolves even if `Theme.registerFonts()` has not run yet.
    public func font(size: CGFloat) -> Font {
        _ = FontRegistration.registerBundledFonts()
        return .custom(rawValue, fixedSize: size)
    }
}
