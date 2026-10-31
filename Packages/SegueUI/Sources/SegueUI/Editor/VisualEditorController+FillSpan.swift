#if os(macOS)
    import AppKit
    import Editing
    import SwiftUI

    /// The canvas's fill span (P8-7 section 12.1): pills in it are tinted (painting), and
    /// the "Create Bass Fill..." capsule floats under the landing pill.
    extension VisualEditorController {
        /// Places the capsule under the span's landing pill, or hides it.
        func showSpanCapsule() {
            let selection = model.spanSelection
            guard let landing = selection.span?.upperBound,
                  let pill = landingPill(landing)
            else {
                spanCapsule?.isHidden = true
                return
            }
            let view = AnyView(
                FillSpanCapsule(actions: model.chordSpanActions)
                    .padding(6),
            )
            let host: NSHostingView<AnyView>
            if let existing = spanCapsule {
                existing.rootView = view
                host = existing
            } else {
                host = NSHostingView(rootView: view)
                container.addSubview(host)
                spanCapsule = host
            }
            let fitting = host.fittingSize
            let size = CGSize(width: ceil(fitting.width), height: ceil(fitting.height))
            // Beside the landing pill, on its row: it floats over the next pills rather
            // than the lyric it belongs to.
            let corner = textView.convert(
                CGPoint(x: pill.rect.maxX + 2, y: pill.rect.midY - size.height / 2),
                to: container,
            )
            let y = container.isFlipped ? corner.y : corner.y - size.height
            host.frame = CGRect(x: corner.x, y: y, width: size.width, height: size.height)
            host.isHidden = false
        }

        /// The pill of timeline chord `index`, when it is on the canvas.
        private func landingPill(_ index: Int) -> PillLayout? {
            let selection = model.spanSelection
            guard selection.timeline.chords.indices.contains(index) else { return nil }
            let path = selection.timeline.chords[index].line
            guard let paragraph = projection.lyricParagraphs[path],
                  let line = projection.paragraphs[paragraph].lyricLine,
                  let chord = line.chords.first(where: {
                      $0.kind == .chord && selection.index(line: path, offset: $0.offset) == index
                  })
            else { return nil }
            return layout(of: ChordSelection(
                path: path,
                offset: chord.offset,
                original: chord.original,
            ))
        }
    }
#endif
