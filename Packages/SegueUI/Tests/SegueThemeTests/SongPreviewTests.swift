import AppKit
import Foundation
@testable import SegueUI
import SwiftUI
import Testing

/// The Quick Look preview view (WS2b 4.7, B-20): each Welcome song and a malformed file
/// render to a non-empty light image; long files stop at 400 lines.
@MainActor
struct SongPreviewTests {
    private static func render(_ source: String) throws -> CGImage {
        #expect(Theme.registerFonts())
        let renderer = ImageRenderer(content: SongPreviewView(source: source).page
            .frame(width: 720)
            .background(Color.white)
            .environment(\.colorScheme, .light))
        renderer.scale = 1
        return try #require(renderer.cgImage)
    }

    /// Share of pixels that are not the light paper ground.
    private static func inkCoverage(_ image: CGImage) -> Double {
        let rep = NSBitmapImageRep(cgImage: image)
        var marked = 0
        var total = 0
        for y in stride(from: 0, to: rep.pixelsHigh, by: 4) {
            for x in stride(from: 0, to: rep.pixelsWide, by: 4) {
                total += 1
                if let color = rep.colorAt(x: x, y: y), color.brightnessComponent < 0.8 {
                    marked += 1
                }
            }
        }
        return Double(marked) / Double(max(total, 1))
    }

    @Test(arguments: [
        "soundcheck-at-seven", "kitaabon-wali-gali", "kettle-on-lights-low",
        "ferry-lights-over-calder-bay",
    ])
    func `each welcome song previews`(_ name: String) throws {
        let folder = try #require(PolishDependencies.bundledWelcomeFolder)
        let source = try String(contentsOf: folder.appending(path: "\(name).cho"), encoding: .utf8)
        let image = try Self.render(source)
        #expect(image.width == 720)
        let coverage = Self.inkCoverage(image)
        #expect(coverage > 0.01 && coverage < 0.5, "\(coverage)")
    }

    @Test
    func `a malformed file still previews and long files are cut`() throws {
        let malformed = "{title: Broken\n[G unclosed chord\n{start_of_chorus}\nno end\n\u{0}"
        #expect(try Self.inkCoverage(Self.render(malformed)) > 0.002)
        let long = (1 ... 600).map { "[C]Line \($0)" }.joined(separator: "\n")
        let view = SongPreviewView(source: long)
        #expect(view.plainText.split(separator: "\n").count == SongPreviewView.maxLines + 1)
        #expect(view.plainText.hasSuffix("…"))
    }
}
