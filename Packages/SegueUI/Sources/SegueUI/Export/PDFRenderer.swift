#if os(macOS)
    import CoreGraphics
    import Foundation
    import PDFKit
    import Printing
    import SwiftUI

    /// Draws a `PrintDocument` (P9-1 spec 7.2 steps 4-5): each page's SwiftUI view through
    /// `ImageRenderer.render` into one Core Graphics PDF context (vector, selectable text),
    /// then the outline, the set list's page links and the document attributes with PDFKit.
    @MainActor
    enum PDFRenderer {
        enum Failure: Error, Equatable {
            case context
            case unreadable
        }

        /// The PDF of `document`. Checks for cancellation and yields between pages, so a
        /// sheet stays responsive and an option change can stop a render in flight.
        static func render(
            _ document: PrintDocument,
            diagrams: [Int: PrintSongDiagrams] = [:],
        ) async throws -> PDFDocument {
            let paper = document.paper.size
            let data = NSMutableData()
            var box = CGRect(x: 0, y: 0, width: paper.width, height: paper.height)
            guard let consumer = CGDataConsumer(data: data as CFMutableData),
                  let context = CGContext(consumer: consumer, mediaBox: &box, nil)
            else { throw Failure.context }
            _ = Theme.registerFonts()
            for page in document.pages {
                try Task.checkCancellation()
                let renderer = ImageRenderer(content: PrintPageView(
                    page: page,
                    paper: document.paper,
                    diagrams: diagrams,
                ))
                context.beginPDFPage(nil)
                renderer.render { _, draw in draw(context) }
                context.endPDFPage()
                await Task.yield()
            }
            context.closePDF()
            try Task.checkCancellation()
            guard let pdf = PDFDocument(data: data as Data) else { throw Failure.unreadable }
            addLinks(document, to: pdf)
            addOutline(document, to: pdf)
            pdf.documentAttributes = attributes(document.metadata)
            return pdf
        }

        /// Each set list row with a page links to the top of that page.
        private static func addLinks(_ document: PrintDocument, to pdf: PDFDocument) {
            let paper = document.paper.size
            for (index, page) in document.pages.enumerated() {
                guard case let .setList(list) = page, let pdfPage = pdf.page(at: index) else {
                    continue
                }
                let top = PrintPageMetrics.top
                    + SetListMetrics.headHeight(continuation: list.head.isContinuation)
                for row in list.rows {
                    guard let target = row.target, let destination = pdf.page(at: target) else {
                        continue
                    }
                    let bounds = CGRect(
                        x: PrintPageMetrics.side,
                        y: paper.height - top - row.y - row.height,
                        width: PrintPageMetrics.bodyWidth(document.paper),
                        height: row.height,
                    )
                    let link = PDFAnnotation(bounds: bounds, forType: .link, withProperties: nil)
                    link.destination = PDFDestination(
                        page: destination,
                        at: CGPoint(x: 0, y: paper.height),
                    )
                    link.border = PDFBorder()
                    link.border?.lineWidth = 0
                    pdfPage.addAnnotation(link)
                }
            }
        }

        private static func addOutline(_ document: PrintDocument, to pdf: PDFDocument) {
            let paper = document.paper.size
            let root = PDFOutline()
            func outline(_ entry: PrintOutlineEntry) -> PDFOutline? {
                guard let page = pdf.page(at: entry.page) else { return nil }
                let item = PDFOutline()
                item.label = entry.title
                item.destination = PDFDestination(page: page, at: CGPoint(x: 0, y: paper.height))
                for child in entry.children {
                    if let node = outline(child) {
                        item.insertChild(node, at: item.numberOfChildren)
                    }
                }
                return item
            }
            for entry in document.outline {
                if let node = outline(entry) {
                    root.insertChild(node, at: root.numberOfChildren)
                }
            }
            pdf.outlineRoot = root
        }

        static func attributes(_ metadata: PrintMetadata) -> [AnyHashable: Any] {
            var attributes: [AnyHashable: Any] = [
                PDFDocumentAttribute.titleAttribute: metadata.title,
                PDFDocumentAttribute.creatorAttribute: metadata.creator,
                PDFDocumentAttribute.creationDateAttribute: metadata.date,
                PDFDocumentAttribute.modificationDateAttribute: metadata.date,
            ]
            if let author = metadata.author {
                attributes[PDFDocumentAttribute.authorAttribute] = author
            }
            if let subject = metadata.subject {
                attributes[PDFDocumentAttribute.subjectAttribute] = subject
            }
            if !metadata.keywords.isEmpty {
                attributes[PDFDocumentAttribute.keywordsAttribute] = metadata.keywords
            }
            return attributes
        }
    }
#endif
