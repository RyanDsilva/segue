import AppKit
@testable import SegueUI
import SwiftUI
import Testing

/// Renders the real token swatch view (asset catalog colours, bundled fonts) in light and
/// dark and checks every swatch's pixels resolve to the `design/tokens.json` values.
@MainActor
struct ThemeTokenTests {
    @Test(arguments: [ColorScheme.light, .dark])
    func `swatches resolve to the token values`(scheme: ColorScheme) throws {
        #expect(Theme.registerFonts())
        let pixels = try render(ThemeSwatchView().environment(\.colorScheme, scheme))
        let size = Int(ThemeSwatchView.swatchSize)
        for (index, token) in ColorTokenValue.all.enumerated() {
            // Sample the centre of the token's swatch.
            let rendered = pixels.rgb(x: size / 2, y: index * size + size / 2)
            let expected = scheme == .dark ? token.dark : token.light
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
