#if os(macOS)
    import CoreGraphics
    import SwiftUI

    /// Finder's thumbnail of a ChordPro song (P9-5 section 5, P3): the top of the song page
    /// the Quick Look preview shows, on a letter-shaped light page, so a `.cho` in Finder's
    /// icon and gallery views shows its title and first lines instead of a generic icon.
    /// Song content is drawn exactly as written (romanized Hindi included).
    public enum SongThumbnail {
        /// The page is letter-shaped (8.5 x 11).
        public static let pageAspect: CGFloat = 8.5 / 11
        /// The width the page is laid out at before it is scaled down (the preview's width).
        static let pageWidth: CGFloat = 720

        /// The largest letter-shaped size inside `maximum`.
        public static func contextSize(fitting maximum: CGSize) -> CGSize {
            guard maximum.width > 0, maximum.height > 0 else { return .zero }
            let width = min(maximum.width, maximum.height * pageAspect)
            return CGSize(width: width.rounded(.down), height: (width / pageAspect).rounded(.down))
        }

        /// The thumbnail of `source` at `size` points and `scale` pixels per point; nil when
        /// it cannot be drawn.
        @MainActor
        public static func render(source: String, size: CGSize, scale: CGFloat) -> CGImage? {
            guard size.width > 0, size.height > 0, scale > 0 else { return nil }
            _ = Theme.registerFonts()
            let renderer = ImageRenderer(content: ThumbnailPage(source: source))
            // Laid out at the preview's width, at its natural height, drawn at the
            // thumbnail's pixel width; the top page-shaped part is kept.
            let pixelsPerPoint = scale * size.width / pageWidth
            renderer.scale = pixelsPerPoint
            renderer.proposedSize = ProposedViewSize(width: pageWidth, height: nil)
            guard let page = renderer.cgImage else { return nil }
            let width = page.width
            let height = Int((CGFloat(width) / pageAspect).rounded(.down))
            guard page.height >= height else { return page }
            return page.cropping(to: CGRect(x: 0, y: 0, width: width, height: height))
        }
    }

    /// The song page at its natural height and at least one page tall, always light.
    struct ThumbnailPage: View {
        let source: String

        var body: some View {
            SongPreviewView(source: source).page
                .frame(width: SongThumbnail.pageWidth, alignment: .top)
                .fixedSize(horizontal: false, vertical: true)
                .frame(
                    minHeight: SongThumbnail.pageWidth / SongThumbnail.pageAspect,
                    alignment: .top,
                )
                .background(Theme.color.ground)
                .environment(\.colorScheme, .light)
        }
    }
#endif
