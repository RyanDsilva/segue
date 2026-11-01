import ChordPro
import CoreGraphics
import Diagrams
import Editing
import LiveLayout
import PDFKit
@testable import SegueUI
import SwiftUI
import Testing

/// P9-1 decision 3 gate (spec 14.2, kept as a guard): SwiftUI drawn by `ImageRenderer` into a
/// Core Graphics PDF context writes vector content with selectable text, `Canvas` included
/// (a guitar diagram and a fill's mini tab), and no image XObject.
@MainActor
struct PDFSpikeTests {
    static let paper = CGSize(width: 612, height: 792)

    @Test
    func `a stage plan, a diagram and a mini tab render as vector PDF with real text`() throws {
        _ = Theme.registerFonts()
        let model = RenderModel(
            document: ChordProParser.parse("{title: Spike}\n[G]Lanterns on the [Em]water\n").0,
            options: DisplayOptions(),
        )
        let plan = LayoutEngine.plan(
            LayoutRequest(
                model: model,
                viewport: LayoutSize(width: 540, height: 600),
                minLyricSize: 11.5,
                style: .print(lyricSize: 11.5),
            ),
            metrics: StageTextMetrics(),
        )
        let page = Self.page(plan)
        let data = try Self.pdf([AnyView(page)], paper: Self.paper)
        let document = try #require(PDFDocument(data: data))
        #expect(document.pageCount == 1)
        let text = try #require(document.page(at: 0)?.string)
        #expect(text.contains("Lanterns on the"))
        #expect(text.contains("Em"))
        let images = try Self.imageXObjects(in: data)
        #expect(images == 0, "the page holds \(images) image XObject(s): not vector")
    }

    /// One page: the plan, a guitar diagram and a fill's mini tab, in the light scheme.
    static func page(_ plan: LayoutPlan) -> some View {
        let tab = FillTabBlock(
            part: "spike",
            notes: [
                TabNote(
                    tick: 0,
                    length: 480,
                    position: FretPosition(string: 1, fret: 7),
                    name: "E",
                ),
                TabNote(
                    tick: 480,
                    length: 480,
                    position: FretPosition(string: 1, fret: 9),
                    name: "F#",
                ),
            ],
            chords: [FillTabChord(tick: 0, name: "G")],
            ticks: 0 ..< 960,
            pulses: [0, 480],
            bars: [0],
            tuning: .bassStandard4,
            accessibility: "Tab",
        )
        return VStack(alignment: .leading, spacing: 12) {
            StagePlanView(plan: plan, style: .print(lyricSize: 11.5))
            GuitarDiagramView(
                name: "G",
                shape: GuitarShape(frets: [3, 2, 0, 0, 0, 3]),
                tuning: .standard,
                size: .compact,
            )
            MiniTabView(block: tab, size: 7, identifier: "spike.tab").frame(width: 300)
        }
        .padding(36)
        .frame(width: Self.paper.width, height: Self.paper.height, alignment: .topLeading)
        .background(Color.white)
        .environment(\.colorScheme, .light)
    }

    /// Each view drawn by `ImageRenderer.render` into one PDF context.
    static func pdf(_ pages: [AnyView], paper: CGSize) throws -> Data {
        let data = NSMutableData()
        var box = CGRect(origin: .zero, size: paper)
        let consumer = try #require(CGDataConsumer(data: data as CFMutableData))
        let context = try #require(CGContext(consumer: consumer, mediaBox: &box, nil))
        for page in pages {
            let renderer = ImageRenderer(content: page.frame(
                width: paper.width,
                height: paper.height,
            ))
            context.beginPDFPage(nil)
            renderer.render { _, draw in draw(context) }
            context.endPDFPage()
        }
        context.closePDF()
        return data as Data
    }

    /// Image XObjects on every page, nested form XObjects included.
    static func imageXObjects(in data: Data) throws -> Int {
        let provider = try #require(CGDataProvider(data: data as CFData))
        let document = try #require(CGPDFDocument(provider))
        var count = 0
        for index in 1 ... max(document.numberOfPages, 1) {
            guard let page = document.page(at: index), let dictionary = page.dictionary else {
                continue
            }
            var resources: CGPDFDictionaryRef?
            if CGPDFDictionaryGetDictionary(dictionary, "Resources", &resources), let resources {
                count += images(in: resources, depth: 0)
            }
        }
        return count
    }

    private static func images(in resources: CGPDFDictionaryRef, depth: Int) -> Int {
        guard depth < 8 else { return 0 }
        var objects: CGPDFDictionaryRef?
        guard CGPDFDictionaryGetDictionary(resources, "XObject", &objects), let objects else {
            return 0
        }
        var count = 0
        let visit: CGPDFDictionaryApplierBlock = { _, value, _ in
            var stream: CGPDFStreamRef?
            guard CGPDFObjectGetValue(value, .stream, &stream), let stream,
                  let dictionary = CGPDFStreamGetDictionary(stream)
            else { return true }
            var subtype: UnsafePointer<CChar>?
            guard CGPDFDictionaryGetName(dictionary, "Subtype", &subtype), let subtype else {
                return true
            }
            switch String(cString: subtype) {
            case "Image":
                count += 1
            case "Form":
                var inner: CGPDFDictionaryRef?
                if CGPDFDictionaryGetDictionary(dictionary, "Resources", &inner), let inner {
                    count += Self.images(in: inner, depth: depth + 1)
                }
            default:
                break
            }
            return true
        }
        CGPDFDictionaryApplyBlock(objects, visit, nil)
        return count
    }
}
