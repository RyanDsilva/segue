import AppKit
import Editing
import QuartzCore
@testable import SegueUI
import Testing

/// Acceptance criterion 9: the editor stays under 16 ms per keystroke on a 200-line song.
/// Drives the real editor (TextKit 2 views in an offscreen window, snapshot, highlighting,
/// tree edits, canvas re-projection) and times each keystroke from insert to laid-out
/// viewport. The UI E2E measures the same in the running app.
@MainActor
@Suite(.serialized)
struct EditorPerformanceTests {
    static let song: String = {
        var text = "{title: Long Song}\n{key: G}\n\n{start_of_verse}\n"
        for index in 4 ..< 199 {
            text += "[G]Line \(index) of the [C]long song, [D]tum hi [Em]ho\n"
        }
        return text + "{end_of_verse}\n"
    }()

    @Test
    func `typing in text mode stays under a frame`() throws {
        let (model, window) = try host()
        defer { window.close() }
        let textView = model.sourceEditor.textView
        textView.setSelectedRange(NSRange(location: (Self.song as NSString).length / 2, length: 0))
        let times = type("tum hi ho pyaar ki raah ", into: textView)
        report("text", times)
        #expect(percentile(times, 0.95) < 16, "text p95 \(percentile(times, 0.95)) ms")
    }

    @Test
    func `typing in visual mode stays under a frame`() throws {
        let (model, window) = try host()
        defer { window.close() }
        model.setEditorMode(.visual)
        let canvas = model.visualEditor
        attach(canvas.container, to: window)
        canvas.didAttach()
        let middle = try #require(canvas.projection.lyricParagraphs.values.sorted().dropFirst(90)
            .first)
        canvas.textView.setSelectedRange(NSRange(
            location: canvas.projection.starts[middle] + 4,
            length: 0,
        ))
        let times = type("dil se dil tak ", into: canvas.textView)
        report("visual", times)
        #expect(model.source.contains("Line"))
        #expect(percentile(times, 0.95) < 16, "visual p95 \(percentile(times, 0.95)) ms")
    }

    @Test
    func `stage costs on a 200-line song`() {
        let snapshot = SourceSnapshot(text: Self.song)
        let stages: [(String, () -> Void)] = [
            ("parse", { _ = SourceSnapshot(text: Self.song) }),
            ("render (no diagrams)", {
                var options = DisplayOptions()
                options.showDiagrams = false
                _ = RenderModel(document: snapshot.document, options: options)
            }),
            (
                "render (diagrams)",
                { _ = RenderModel(document: snapshot.document, options: DisplayOptions()) },
            ),
            ("highlights (1 line)", { _ = snapshot.highlights(in: 4000 ..< 4060) }),
            ("diagnostics", { _ = snapshot.diagnostics }),
            ("edit lyrics", {
                let position = snapshot.lyricPosition(atSourceOffset: 4000)
                if let position {
                    _ = try? DocumentEditor.change(
                        for: .editLyrics(position.line, range: 2 ..< 2, replacement: "x"),
                        in: snapshot,
                    )
                }
            }),
        ]
        for (name, stage) in stages {
            let times = (0 ..< 10).map { _ in measure(stage) }
            print("[perf] \(name): median \(format(percentile(times, 0.5))) ms")
        }
    }

    // MARK: - Helpers

    private func host() throws -> (SongEditorViewModel, NSWindow) {
        #expect(Theme.registerFonts())
        let model = SongEditorViewModel(mode: .create, source: "") { _ in
            throw CancellationError()
        }
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1100, height: 800),
            styleMask: [.titled],
            backing: .buffered,
            defer: false,
        )
        window.isReleasedWhenClosed = false
        let source = model.sourceEditor
        attach(source.scrollView, to: window)
        source.replaceAll(with: Self.song)
        #expect(model.source == Self.song)
        return (model, window)
    }

    private func attach(_ view: NSView, to window: NSWindow) {
        view.frame = NSRect(x: 0, y: 0, width: 1100, height: 800)
        window.contentView = view
        window.layoutIfNeeded()
    }

    /// Types each character as a keystroke would, timing insert + viewport layout.
    private func type(_ text: String, into textView: NSTextView) -> [Double] {
        text.map { character in
            measure {
                textView.insertText(String(character), replacementRange: textView.selectedRange())
                textView.textLayoutManager?.textViewportLayoutController.layoutViewport()
            }
        }
    }

    private func measure(_ work: () -> Void) -> Double {
        let start = CACurrentMediaTime()
        work()
        return (CACurrentMediaTime() - start) * 1000
    }

    private func percentile(_ times: [Double], _ fraction: Double) -> Double {
        let sorted = times.sorted()
        guard !sorted.isEmpty else { return 0 }
        return sorted[min(Int(Double(sorted.count) * fraction), sorted.count - 1)]
    }

    private func report(_ name: String, _ times: [Double]) {
        print(
            "[perf] \(name): n=\(times.count) median \(format(percentile(times, 0.5))) ms, "
                + "p95 \(format(percentile(times, 0.95))) ms, max \(format(times.max() ?? 0)) ms",
        )
    }

    private func format(_ value: Double) -> String {
        String(format: "%.2f", value)
    }
}
