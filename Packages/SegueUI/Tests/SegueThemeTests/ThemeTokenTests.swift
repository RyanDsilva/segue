import AppKit
@testable import SegueUI
import SwiftUI
import Testing

/// Renders the real token swatch view (asset catalog colours, bundled fonts) in light and
/// dark and checks every swatch's pixels resolve to the `design/tokens.json` values.
///
/// These (and the diagram snapshots) need the compiled asset catalog, which only Swift Build
/// produces: run them with `make test` (`swift test --build-system swiftbuild`), not plain
/// `swift test`, whose native build system copies the catalog uncompiled.
@MainActor
struct ThemeTokenTests {
    @Test
    func `the asset catalog is compiled (run make test)`() {
        #expect(
            NSColor(named: ColorTokenValue.all[0].name, bundle: Theme.bundle) != nil,
            "Theme colours are missing: run the SegueUI tests with `make test` (Swift Build)",
        )
    }

    @Test(arguments: [ColorScheme.light, .dark])
    func `swatches resolve to the token values`(scheme: ColorScheme) throws {
        #expect(Theme.registerFonts())
        let pixels = try render(ThemeSwatchView().environment(\.colorScheme, scheme))
        let size = Int(ThemeSwatchView.swatchSize)
        for (index, token) in ColorTokenValue.all.enumerated() {
            // Sample the centre of the token's swatch.
            let rendered = pixels.rgb(x: size / 2, y: index * size + size / 2)
            // A translucent token renders over the view's `ground`.
            let ground = try #require(ColorTokenValue.all.first { $0.name == "ground" })
            let expected = scheme == .dark
                ? blend(token.dark, alpha: token.darkAlpha, over: ground.dark)
                : blend(token.light, alpha: token.lightAlpha, over: ground.light)
            #expect(
                rendered.isClose(to: expected),
                "\(token.name) (\(scheme)): got \(hex(rendered.packed)), want \(hex(expected))",
            )
        }
    }

    @Test
    func `token values match the asset catalog in both appearances`() throws {
        for token in ColorTokenValue.all {
            let color = try #require(
                NSColor(named: token.name, bundle: Theme.bundle),
                "\(token.name)",
            )
            for (appearance, expected) in [
                (NSAppearance.Name.aqua, token.light),
                (.darkAqua, token.dark),
            ] {
                let appearance = try #require(NSAppearance(named: appearance))
                var resolved: NSColor?
                appearance.performAsCurrentDrawingAppearance {
                    resolved = color.usingColorSpace(.sRGB)
                }
                let srgb = try #require(resolved)
                let rgb = RGB(
                    red: UInt8((srgb.redComponent * 255).rounded()),
                    green: UInt8((srgb.greenComponent * 255).rounded()),
                    blue: UInt8((srgb.blueComponent * 255).rounded()),
                )
                #expect(rgb.packed == expected, "\(token.name) in \(appearance.name.rawValue)")
            }
        }
    }

    /// A contrast requirement: `foreground` on `background` reaches `minimum` (WCAG 2.x) in
    /// each of `appearances`. Text needs 4.5, state indicators and control edges 3.0
    /// (docs/brand.md section 5, WS2b 4.9.1).
    struct ContrastPair: Sendable, CustomTestStringConvertible {
        let foreground: String
        let background: String
        let minimum: Double
        let appearances: [NSAppearance.Name]

        var testDescription: String {
            "\(foreground) on \(background) >= \(minimum)"
        }
    }

    nonisolated static let standard: [NSAppearance.Name] = [.aqua, .darkAqua]
    nonisolated static let highContrast: [NSAppearance.Name] = [
        .accessibilityHighContrastAqua, .accessibilityHighContrastDarkAqua,
    ]

    /// Every pair Segue relies on. A43: control borders reach 3:1 under Increase Contrast
    /// only (Apple's criteria accept the setting for apps built on Apple's frameworks).
    nonisolated static let contrastPairs: [ContrastPair] = [
        // Text.
        ContrastPair(
            foreground: "ink",
            background: "ground",
            minimum: 4.5,
            appearances: standard + highContrast,
        ),
        ContrastPair(
            foreground: "muted",
            background: "ground",
            minimum: 4.5,
            appearances: standard + highContrast,
        ),
        ContrastPair(
            foreground: "cueText",
            background: "ground",
            minimum: 4.5,
            appearances: standard + highContrast,
        ),
        // State indicators: progress dots, unrated stars (A44).
        ContrastPair(
            foreground: "indicatorOff",
            background: "ground",
            minimum: 3,
            appearances: standard + highContrast,
        ),
        ContrastPair(
            foreground: "played",
            background: "ground",
            minimum: 3,
            appearances: standard + highContrast,
        ),
        ContrastPair(
            foreground: "cue",
            background: "ground",
            minimum: 3,
            appearances: standard + highContrast,
        ),
        // Control edges, under Increase Contrast (A43).
        ContrastPair(
            foreground: "controlBorder",
            background: "ground",
            minimum: 3,
            appearances: highContrast,
        ),
    ]

    @Test(arguments: contrastPairs)
    func `contrast meets its minimum`(pair: ContrastPair) throws {
        for name in pair.appearances {
            let foreground = try resolve(pair.foreground, in: name)
            let background = try resolve(pair.background, in: name)
            let ratio = Self.contrast(foreground, background)
            #expect(
                ratio >= pair.minimum,
                "\(pair.testDescription) in \(name.rawValue): \(String(format: "%.2f", ratio))",
            )
        }
    }

    @Test
    func `the indicator ratios match the approved A44 values`() throws {
        // token, appearance -> ratio on ground, as rendered for Ryan's approval.
        let expected: [String: Double] = [
            "indicatorOff/aqua": 3.43, "indicatorOff/darkAqua": 3.36,
            "played/aqua": 7.39, "played/darkAqua": 5.81,
        ]
        for (key, value) in expected {
            let parts = key.split(separator: "/").map(String.init)
            let name: NSAppearance.Name = parts[1] == "aqua" ? .aqua : .darkAqua
            let ratio = try Self.contrast(
                resolve(parts[0], in: name),
                resolve("ground", in: name),
            )
            #expect(abs(ratio - value) < 0.01, "\(key): \(ratio)")
        }
    }

    /// Token `name` as it shows in `appearance` (the High Contrast value under Increase
    /// Contrast, composited over `ground` when translucent), as sRGB components 0...1.
    /// Computed from the generated values, which `make tokens-check` keeps equal to the
    /// asset catalog: an in-process high-contrast `NSAppearance` does not select the
    /// catalog's `contrast: high` entries (only the system setting does), so the live
    /// rendering is checked in the manual Increase Contrast pass (WS2b 4.9.5).
    private func resolve(_ name: String, in appearance: NSAppearance.Name) throws -> [Double] {
        let token = try #require(ColorTokenValue.all.first { $0.name == name }, "\(name)")
        let ground = try #require(ColorTokenValue.all.first { $0.name == "ground" })
        let dark = appearance == .darkAqua || appearance == .accessibilityHighContrastDarkAqua
        let high = appearance == .accessibilityHighContrastAqua
            || appearance == .accessibilityHighContrastDarkAqua
        let value = dark
            ? (high ? token.darkHigh ?? token.dark : token.dark)
            : (high ? token.lightHigh ?? token.light : token.light)
        // High Contrast values are opaque; the standard ones may carry alpha.
        let alpha = high && (dark ? token.darkHigh : token.lightHigh) != nil
            ? 1
            : (dark ? token.darkAlpha : token.lightAlpha)
        let base = dark ? ground.dark : ground.light
        return [16, 8, 0].map { shift in
            let top = Double(value >> UInt32(shift) & 0xFF) / 255
            let bottom = Double(base >> UInt32(shift) & 0xFF) / 255
            return top * alpha + bottom * (1 - alpha)
        }
    }

    /// WCAG 2.x contrast ratio of two sRGB colours.
    static func contrast(_ lhs: [Double], _ rhs: [Double]) -> Double {
        func luminance(_ rgb: [Double]) -> Double {
            let linear = rgb.map { $0 <= 0.03928 ? $0 / 12.92 : pow(($0 + 0.055) / 1.055, 2.4) }
            return 0.2126 * linear[0] + 0.7152 * linear[1] + 0.0722 * linear[2]
        }
        let (high, low) = (max(luminance(lhs), luminance(rhs)), min(luminance(lhs), luminance(rhs)))
        return (high + 0.05) / (low + 0.05)
    }

    @Test
    func `bundled Schibsted Grotesk faces register and resolve`() {
        #expect(Theme.registerFonts())
        for face in SchibstedGrotesk.allCases {
            let font = NSFont(name: face.rawValue, size: 15)
            #expect(font?.fontName == face.rawValue, "\(face.rawValue) did not resolve")
        }
    }

    @Test(arguments: [22.0, 24.0, 40.0])
    func `chord size is 0.82 of the lyric size`(lyric: CGFloat) {
        #expect(FontTokens.liveChordSize(forLyricSize: lyric) == (lyric * 0.82).rounded())
    }

    @Test
    func `chord size at the 22pt lyric floor is 18`() {
        #expect(FontTokens.liveChordSize(forLyricSize: 22) == 18)
    }

    // MARK: - Rendering helpers

    private func render(_ view: some View) throws -> Bitmap {
        let renderer = ImageRenderer(content: view)
        renderer.scale = 1
        let image = try #require(renderer.cgImage, "ImageRenderer produced no image")
        return try Bitmap(image)
    }

    /// `value` at `alpha` composited over `base`, as 0xRRGGBB.
    private func blend(_ value: UInt32, alpha: Double, over base: UInt32) -> UInt32 {
        [16, 8, 0].reduce(0) { result, shift in
            let top = Double(value >> UInt32(shift) & 0xFF)
            let bottom = Double(base >> UInt32(shift) & 0xFF)
            return result | UInt32((top * alpha + bottom * (1 - alpha)).rounded()) << UInt32(shift)
        }
    }

    private func hex(_ value: UInt32) -> String {
        "#" + String(format: "%06X", value)
    }
}

/// 8-bit sRGB colour.
struct RGB: Equatable {
    let red: UInt8
    let green: UInt8
    let blue: UInt8

    var packed: UInt32 {
        UInt32(red) << 16 | UInt32(green) << 8 | UInt32(blue)
    }

    /// Within one step per channel (rendering may round differently from the catalog).
    func isClose(to value: UInt32) -> Bool {
        let other = [UInt8(value >> 16 & 0xFF), UInt8(value >> 8 & 0xFF), UInt8(value & 0xFF)]
        return zip([red, green, blue], other).allSatisfy { abs(Int($0) - Int($1)) <= 1 }
    }
}

/// A CGImage redrawn into a known sRGB RGBA8 layout so pixels can be read directly.
struct Bitmap {
    private let bytes: [UInt8]
    private let width: Int

    init(_ image: CGImage) throws {
        width = image.width
        var buffer = [UInt8](repeating: 0, count: image.width * image.height * 4)
        let space = try #require(CGColorSpace(name: CGColorSpace.sRGB))
        let drawn = buffer.withUnsafeMutableBytes { raw -> Bool in
            guard let context = CGContext(
                data: raw.baseAddress,
                width: image.width,
                height: image.height,
                bitsPerComponent: 8,
                bytesPerRow: image.width * 4,
                space: space,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue,
            ) else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
            return true
        }
        try #require(drawn, "could not create an sRGB bitmap context")
        bytes = buffer
    }

    /// The pixel at (x, y), with y measured from the top.
    func rgb(x: Int, y: Int) -> RGB {
        let offset = (y * width + x) * 4
        return RGB(red: bytes[offset], green: bytes[offset + 1], blue: bytes[offset + 2])
    }
}
