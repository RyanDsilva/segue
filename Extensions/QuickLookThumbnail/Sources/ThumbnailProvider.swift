import AppKit
import QuickLookThumbnailing
import SegueUI

/// Finder's thumbnail of a ChordPro song (P9-5 section 5, P3): the top of the app's own song
/// page, drawn by `SongThumbnail` from the file Quick Look hands over (sandboxed, read only).
final class ThumbnailProvider: QLThumbnailProvider {
    override func provideThumbnail(
        for request: QLFileThumbnailRequest,
        _ handler: @escaping (QLThumbnailReply?, (any Error)?) -> Void,
    ) {
        let data: Data
        do {
            data = try Data(contentsOf: request.fileURL)
        } catch {
            handler(nil, error)
            return
        }
        let source = String(data: data, encoding: .utf8) ?? String(decoding: data, as: UTF8.self)
        let size = SongThumbnail.contextSize(fitting: request.maximumSize)
        let scale = request.scale
        guard let image = Self.render(source: source, size: size, scale: scale) else {
            handler(nil, CocoaError(.fileReadCorruptFile))
            return
        }
        handler(QLThumbnailReply(contextSize: size) { context in
            // The context is in pixels (`size` times the request's scale): fill all of it.
            let bounds = context.width > 0
                ? CGRect(x: 0, y: 0, width: context.width, height: context.height)
                : CGRect(origin: .zero, size: size)
            context.draw(image, in: bounds)
            return true
        }, nil)
    }

    /// SwiftUI renders on the main thread; Quick Look calls in on its own queue.
    private static func render(source: String, size: CGSize, scale: CGFloat) -> CGImage? {
        if Thread.isMainThread {
            return MainActor.assumeIsolated {
                SongThumbnail.render(source: source, size: size, scale: scale)
            }
        }
        return DispatchQueue.main.sync {
            MainActor.assumeIsolated {
                SongThumbnail.render(source: source, size: size, scale: scale)
            }
        }
    }
}
