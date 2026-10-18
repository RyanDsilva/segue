import AppKit
import Quartz
import SegueUI
import SwiftUI

/// The Quick Look preview of a ChordPro song (WS2b 4.7, B-20): the app's own song page,
/// in the light appearance, from the file Quick Look hands over (sandboxed, read only).
final class PreviewViewController: NSViewController, @preconcurrency QLPreviewingController {
    override var nibName: NSNib.Name? {
        nil
    }

    override func loadView() {
        view = NSView(frame: NSRect(x: 0, y: 0, width: 720, height: 900))
        view.appearance = NSAppearance(named: .aqua)
    }

    func preparePreviewOfFile(at url: URL, completionHandler handler: @escaping ((any Error)?) -> Void) {
        do {
            let data = try Data(contentsOf: url)
            _ = Theme.registerFonts()
            let source = String(data: data, encoding: .utf8)
                ?? String(decoding: data, as: UTF8.self)
            let host = NSHostingView(rootView: SongPreviewView(source: source))
            host.frame = view.bounds
            host.autoresizingMask = [.width, .height]
            view.subviews.forEach { $0.removeFromSuperview() }
            view.addSubview(host)
            preferredContentSize = NSSize(width: 720, height: 900)
            handler(nil)
        } catch {
            handler(error)
        }
    }
}
