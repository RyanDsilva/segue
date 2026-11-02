import AppKit
import Foundation
@testable import SegueUI
import Testing

/// P9-5 section 5 (P3): Finder's thumbnail of a `.cho` is the top of the song page, drawn
/// in-process by the renderer the thumbnail extension calls.
@MainActor
struct QuickLookThumbnailTests {
    @Test(arguments: [
        (CGSize(width: 512, height: 512), CGSize(width: 395, height: 512)),
        (CGSize(width: 256, height: 128), CGSize(width: 98, height: 128)),
        (CGSize(width: 100, height: 400), CGSize(width: 100, height: 129)),
        (CGSize.zero, CGSize.zero),
    ])
    func `the thumbnail is the largest letter page that fits`(maximum: CGSize, size: CGSize) {
        #expect(SongThumbnail.contextSize(fitting: maximum) == size)
    }

    @Test
    func `a welcome chart draws its first lines at the top of a full page`() throws {
        let url = try #require(Bundle.module.url(forResource: "WelcomeLibrary", withExtension: nil))
        let source = try String(
            contentsOf: url.appending(path: "kitaabon-wali-gali.cho"),
            encoding: .utf8,
        )
        let size = SongThumbnail.contextSize(fitting: CGSize(width: 256, height: 256))
        let image = try #require(SongThumbnail.render(source: source, size: size, scale: 2))
        // ImageRenderer rounds the pixel size up.
        #expect(abs(image.width - Int(size.width * 2)) <= 2, "\(image.width)")
        #expect(abs(image.height - Int(size.height * 2)) <= 4, "\(image.height)")
        if let folder = ProcessInfo.processInfo.environment["SEGUE_THUMBNAIL_OUT"] {
            let png = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])
            try png?.write(to: URL(filePath: folder).appending(path: "thumbnail.png"))
        }
        let bitmap = try PDFTestSupport.bitmap(image)
        // Paper everywhere outside the ink: the page's top corner and its bottom corner.
        let paper = try PDFTestSupport.pixel(bitmap, at: CGPoint(x: 2, y: 2), scale: 2)
        let bottom = try PDFTestSupport.pixel(
            bitmap,
            at: CGPoint(x: 2, y: size.height - 3),
            scale: 2,
        )
        #expect(paper.description == bottom.description, "\(paper) vs \(bottom)")
        #expect(paper.red > 200 && paper.green > 200 && paper.blue > 200, "\(paper)")
        // Ink (the title) in the top tenth of the page.
        let top = Int(size.height * 2 / 10)
        var inked = 0
        for row in 0 ..< top {
            for column in stride(from: 0, to: bitmap.pixelsWide, by: 2) {
                if let color = bitmap.colorAt(x: column, y: row), color.brightnessComponent < 0.5 {
                    inked += 1
                }
            }
        }
        #expect(inked > 20, "no title in the top of the thumbnail")
    }
}
