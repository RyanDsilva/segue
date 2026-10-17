import AppKit
import Editing
import Library
@testable import SegueUI
import Testing

/// The phase 1 build rulings (docs/decisions.md) through the real editor: Nashville number
/// entry in the visual popover and text-mode completion, inserting on a chord replaces it,
/// "Apply transposition to source" adds a `{key}`, and the diagram strip starts off.
@MainActor
struct EditorBuildRulingsTests {
    static let song = "{title: Raah}\n{key: G}\n\n[G]Dil ki [C]baat hai\n"

    private func editor(
        _ source: String = Self.song,
        prefs: DisplayPrefs = DisplayPrefs(nashville: true),
    ) -> SongEditorViewModel {
        SongEditorViewModel(mode: .create, source: source, prefs: prefs) { _ in
            throw CancellationError()
        }
    }

    /// Hosts a controller's view in a window, as the app does.
    private func window(_ view: NSView, focus: NSView) -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 800, height: 600),
            styleMask: [.titled],
            backing: .buffered,
            defer: false,
        )
        window.isReleasedWhenClosed = false
        window.contentView = view
        window.makeFirstResponder(focus)
        return window
    }

    @Test
    func `in Nashville view the canvas offers numbers and inserts source letters`() throws {
        let model = editor()
        model.setEditorMode(.visual)
        let canvas = model.visualEditor
        let host = window(canvas.container, focus: canvas.textView)
        defer { host.close() }

        #expect(model.paletteChords == ["1", "4"])
        let suggestions = model.displayChordSuggestions(prefix: "")
        #expect(Array(suggestions.prefix(4)) == ["1", "4", "2m", "3m"])
        #expect(model.displayChordSuggestions(prefix: "6").first == "6m")
        #expect(model.displayChordSuggestions(prefix: "b7").first == "b7")
        #expect(model.displayChordSuggestions(prefix: "5").contains("5(7)"))
        // A letter typed in Nashville view gets letter suggestions.
        #expect(model.displayChordSuggestions(prefix: "e").first == "Em")

        let line = try #require(model.snapshot.chords.first?.ref.line)
        // "5" on "ki" (no chord there): D is added.
        canvas.insert("5", at: .init(paragraph: 0, path: line, offset: 4, anchor: .zero))
        #expect(model.source.hasSuffix("[G]Dil [D]ki [C]baat hai\n"))
        // "6m" on "Dil", where G sits: G is replaced (no stacking).
        canvas.insert("6m", at: .init(paragraph: 0, path: line, offset: 0, anchor: .zero))
        #expect(model.source.hasSuffix("[Em]Dil [D]ki [C]baat hai\n"))
        // Letters are still accepted: F#m in the display key G.
        canvas.insert("F#m", at: .init(paragraph: 0, path: line, offset: 7, anchor: .zero))
        #expect(model.source.hasSuffix("[Em]Dil [D]ki [F#m]baat hai\n"))
    }

    @Test
    func `text-mode completion in Nashville view shows numbers and inserts letters`() {
        let model = editor()
        let source = model.sourceEditor
        let host = window(source.scrollView, focus: source.textView)
        defer { host.close() }

        let completions = model.chordCompletions(prefix: "4")
        #expect(completions.first == ChordCompletion(title: "4", insertion: "C"))
        #expect(model.chordCompletions(prefix: "b7").first
            == ChordCompletion(title: "b7", insertion: "F"))
        #expect(model.chordCompletions(prefix: "5/").isEmpty)
        // Letters in text mode are the chords as written.
        #expect(model.chordCompletions(prefix: "E").first
            == ChordCompletion(title: "Em", insertion: "Em"))

        // Type `[b7` at the end of the lyric line and accept: `[F]` lands in the source.
        let end = (source.textView.string as NSString).length - 1
        source.textView.setSelectedRange(NSRange(location: end, length: 0))
        source.textView.insertText(" [b7", replacementRange: source.textView.selectedRange())
        source.updateCompletion(typed: "[")
        #expect(source.completion.items.first == "b7")
        source.acceptCompletion()
        #expect(model.source == "{title: Raah}\n{key: G}\n\n[G]Dil ki [C]baat hai [F]\n")

        // Outside Nashville view numbers are not chords: plain letter suggestions only.
        let letters = editor(prefs: DisplayPrefs())
        #expect(letters.chordCompletions(prefix: "4").isEmpty)
    }

    @Test
    func `apply transposition adds the inferred key and the strip starts off`() {
        let model = editor(
            "{title: Unsigned}\n\n[C]Dil ki [F]baat [G]hai\n",
            prefs: DisplayPrefs(transpose: 2),
        )
        #expect(!model.options.showDiagrams)
        #expect(model.renderModel?.diagrams.isEmpty == true)
        #expect(model.renderModel?.header.keyStatus == .inferred)
        model.applyTranspositionToSource()
        #expect(model.source == "{title: Unsigned}\n{key: D}\n\n[D]Dil ki [G]baat [A]hai\n")
        #expect(model.options.transpose == 0)
        #expect(model.snapshot.document.metadata.key == "D")
    }
}
