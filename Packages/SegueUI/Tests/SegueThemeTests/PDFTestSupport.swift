import AppKit
import ChordPro
import Diagrams
import Editing
import ImageIO
import Library
import PDFKit
import Printing
@testable import SegueUI
import Setlists
import Support
import SwiftUI
import Testing
import UniformTypeIdentifiers

/// Fixtures and helpers for the P9-1 PDF suites: real songs through the real print path
/// (`PrintRequests` -> `PrintAssembler` -> `PDFRenderer`), read back with PDFKit.
@MainActor
enum PDFTestSupport {
    static let date = Date(timeIntervalSince1970: 1_793_000_000)

    /// `<repo>/.build/screenshots/p9-1`.
    static let screenshots = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent()
        .appending(path: ".build/screenshots/p9-1", directoryHint: .isDirectory)

    static let harbour = """
    {title: Harbour Lights}
    {artist: Mira Sol}
    {artist: The Quay Band}
    {album: Low Tide}
    {key: G}
    {capo: 2}
    {tempo: 96}
    {start_of_verse: Intro}
    [G] [D/F#] [Em] [C]
    {end_of_verse}
    {start_of_verse: Verse 1}
    [G]Lanterns on the [D/F#]water line, [Em]boats come [C]in,
    [G]Rope and salt and [D]diesel smoke, the [C]night begins,
    [Em]Every window [D]on the hill is [C]burning gold,
    [G]Someone's singing [D]songs that never [G]get old.
    {end_of_verse}
    {start_of_chorus}
    [C]Harbour [D]lights, [G]carry me [Em]home,
    [C]Over the [D]dark where the [G]cold winds [Em]roam,
    [C]If I [D]drift, if [Em]I [C]fall,
    [Am]Harbour [D]lights, you [G]know us all.
    {end_of_chorus}
    {start_of_verse: Verse 2}
    [G]Fishermen in [D/F#]yellow coats, [Em]nets to [C]mend,
    [G]Talking of the [D]ones who sailed and [C]didn't send,
    [Em]Word of where the [D]current took them, [C]far from shore,
    [G]Still we leave a [D]light on by the [G]door.
    {end_of_verse}
    {chorus}
    {start_of_bridge}
    [Am]Tide comes up and [Em]the tide goes [D]out, [G]
    [Am]That's the one [Em]thing no [D]one [D7]doubts.
    {comment: Hold the last chord}
    {end_of_bridge}
    {chorus}
    {start_of_verse: Outro}
    [C] [D] [G]
    {end_of_verse}
    """

    static func record(_ source: String, index: UInt8 = 0, path: String? = nil) -> SongRecord {
        let id = SongID(ULID(milliseconds: 1, randomness: Array(repeating: index, count: 10)))
        let (document, diagnostics) = ChordProParser.parse(source)
        return SongRecord(
            id: id,
            relativePath: path ?? "songs/song-\(index).cho",
            source: source,
            document: document,
            diagnostics: diagnostics,
            sidecar: Sidecar(id: id, createdAt: .distantPast, updatedAt: .distantPast),
            revision: SongRevision(contentHash: "", sidecarHash: nil),
        )
    }

    static func snapshot(
        _ content: PDFSnapshot.Content,
        profile: InstrumentProfile = InstrumentProfile(),
    ) -> PDFSnapshot {
        PDFSnapshot(
            content: content,
            profile: profile,
            userShapes: .empty,
            defaultChangeover: 0,
            date: date,
        )
    }

    static func options(
        _ part: PrintPart = .chords,
        paper: PrintPaper = .letter,
        configure: (inout PrintOptions) -> Void = { _ in },
    ) -> PrintOptions {
        var options = PrintOptions(part: part, paper: paper)
        configure(&options)
        return options
    }

    static func make(_ snapshot: PDFSnapshot, _ options: PrintOptions) async throws
        -> PDFExport.Output
    {
        _ = Theme.registerFonts()
        return try await PDFExport.make(snapshot, options: options)
    }

    static func text(_ pdf: PDFDocument, page: Int) -> String {
        pdf.page(at: page)?.string ?? ""
    }

    static func allText(_ pdf: PDFDocument) -> String {
        (0 ..< pdf.pageCount).map { text(pdf, page: $0) }.joined(separator: "\n")
    }

    /// Setlist ids for fixtures.
    static func item(_ index: Int) -> SetlistItemID {
        SetlistItemID(ULID(milliseconds: 2, randomness: Array(repeating: UInt8(index), count: 10)))
    }

    static func setlistID(_ index: UInt8 = 9) -> SetlistID {
        SetlistID(ULID(milliseconds: 3, randomness: Array(repeating: index, count: 10)))
    }

    // MARK: Images

    /// Page `index` rasterised at `scale` on white.
    static func image(_ pdf: PDFDocument, page index: Int, scale: CGFloat = 2) throws -> CGImage {
        let page = try #require(pdf.page(at: index))
        let box = page.bounds(for: .mediaBox)
        let width = Int(box.width * scale), height = Int(box.height * scale)
        let context = try #require(CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue,
        ))
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.scaleBy(x: scale, y: scale)
        page.draw(with: .mediaBox, to: context)
        return try #require(context.makeImage())
    }

    static func writePNG(_ image: CGImage, name: String) throws {
        try FileManager.default.createDirectory(at: screenshots, withIntermediateDirectories: true)
        let url = screenshots.appending(path: "\(name).png")
        let destination = try #require(CGImageDestinationCreateWithURL(
            url as CFURL,
            UTType.png.identifier as CFString,
            1,
            nil,
        ))
        CGImageDestinationAddImage(destination, image, nil)
        #expect(CGImageDestinationFinalize(destination), "could not write \(url.path)")
    }

    /// Every page of `pdf` as `<name>-p<N>.png`.
    static func writePages(_ pdf: PDFDocument, name: String) throws {
        for index in 0 ..< pdf.pageCount {
            try writePNG(image(pdf, page: index), name: "\(name)-p\(index + 1)")
        }
    }

    struct RGB: CustomStringConvertible {
        var red: Int
        var green: Int
        var blue: Int

        var description: String {
            "rgb(\(red), \(green), \(blue))"
        }
    }

    /// `image` in sRGB, for sampling.
    static func bitmap(_ image: CGImage) throws -> NSBitmapImageRep {
        try #require(NSBitmapImageRep(cgImage: image).converting(
            to: .sRGB,
            renderingIntent: .default,
        ))
    }

    /// The sRGB colour of `image` at `point` (points from the top-left at `scale`).
    static func pixel(_ image: CGImage, at point: CGPoint, scale: CGFloat = 2) throws -> RGB {
        try pixel(bitmap(image), at: point, scale: scale)
    }

    static func pixel(_ bitmap: NSBitmapImageRep, at point: CGPoint, scale: CGFloat = 2) throws
        -> RGB
    {
        let color = try #require(bitmap.colorAt(x: Int(point.x * scale), y: Int(point.y * scale)))
        return RGB(
            red: Int((color.redComponent * 255).rounded()),
            green: Int((color.greenComponent * 255).rounded()),
            blue: Int((color.blueComponent * 255).rounded()),
        )
    }
}
