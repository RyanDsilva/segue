import AppKit
import Editing
@testable import SegueUI
import Testing

/// The visual editor's section band (P3-11) in process, on a real canvas in a window with
/// the real parser and editor: bands per section, lane selection -> key -> section, the
/// "exactly one section" relabel, text selections mapped to lines, accessibility actions.
@MainActor
struct SectionBandTests {
    static let song = """
    {title: Band}

    [G]Loose one
    [C]Loose two
    [D]Loose three

    {start_of_verse: Verse 1}
    [G]Verse line
    [C]Verse two
    {end_of_verse}

    {chorus}

    """

    struct Hosted {
        let model: SongEditorViewModel
        let canvas: VisualEditorController
        let window: NSWindow
    }

    func host(_ source: String = Self.song) -> Hosted {
        #expect(Theme.registerFonts())
        let model = SongEditorViewModel(mode: .create, source: source) { _ in
            throw CancellationError()
        }
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 900, height: 700),
            styleMask: [.titled],
            backing: .buffered,
            defer: false,
        )
        window.isReleasedWhenClosed = false
        _ = model.sourceEditor
        model.setEditorMode(.visual)
        let canvas = model.visualEditor
        canvas.container.frame = window.contentLayoutRect
        window.contentView = canvas.container
        window.layoutIfNeeded()
        canvas.didAttach()
        return Hosted(model: model, canvas: canvas, window: window)
    }

    private func key(_ character: String, in canvas: VisualEditorController) {
        let event = NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: [],
            timestamp: 0,
            windowNumber: canvas.textView.window?.windowNumber ?? 0,
            context: nil,
            characters: character,
            charactersIgnoringModifiers: character,
            isARepeat: false,
            keyCode: 0,
        )
        if let event {
            canvas.textView.keyDown(with: event)
        }
    }

    @Test
    func `bands follow the sections, loose lines and repeats`() throws {
        let hosted = host()
        defer { hosted.window.close() }
        let titles = hosted.canvas.bands.bands.map(\.kind)
        #expect(titles.count == 3)
        #expect(titles[0] == .slot)
        #expect(titles[2] == .repeatRef(label: "Chorus"))
        let verse = try #require(hosted.canvas.bands.bands.first { $0.sectionPath != nil })
        #expect(verse.title == "Verse 1")
        #expect(verse.paragraphs.count == 2)
        // Every lyric paragraph sits right of the lane.
        #expect(CanvasTypesetting.bandIndent > CanvasTypesetting.bandLaneWidth)
    }

    @Test
    func `selecting loose lines and pressing C makes a chorus around them`() throws {
        let hosted = host()
        let (model, canvas) = (hosted.model, hosted.canvas)
        defer { hosted.window.close() }
        let slot = try #require(canvas.bands.bands.first { $0.kind == .slot })
        canvas.lineSelection = slot.paragraphs
        canvas.updateChipBar()
        key("c", in: canvas)
        #expect(model.source.contains("""

        {start_of_chorus}
        [G]Loose one
        [C]Loose two
        [D]Loose three
        {end_of_chorus}

        """), "\(model.source)")
        #expect(canvas.lineSelection == nil)
        // One undo step takes it away again.
        model.sourceEditor.undoManager.undo()
        #expect(model.source == Self.song)
    }

    @Test
    func `pressing V on exactly one section relabels it, on part of one beeps`() throws {
        let hosted = host()
        let (model, canvas) = (hosted.model, hosted.canvas)
        defer { hosted.window.close() }
        let verse = try #require(canvas.bands.bands.first { $0.sectionPath != nil })
        canvas.lineSelection = verse.paragraphs
        key("c", in: canvas)
        #expect(model.source.contains("{start_of_chorus}\n[G]Verse line"), "\(model.source)")
        let chorus = try #require(canvas.bands.bands.first { $0.sectionPath != nil })
        canvas.lineSelection = chorus.paragraphs.lowerBound ... chorus.paragraphs.lowerBound
        let before = model.source
        #expect(!canvas.applySection(.verse))
        #expect(model.source == before)
    }

    @Test
    func `a text selection across lines picks those lines; inside one line it types`() throws {
        let hosted = host()
        let (model, canvas) = (hosted.model, hosted.canvas)
        defer { hosted.window.close() }
        let slot = try #require(canvas.bands.bands.first { $0.kind == .slot })
        let first = canvas.projection.range(of: slot.paragraphs.lowerBound)
        let second = canvas.projection.range(of: slot.paragraphs.lowerBound + 1)
        canvas.textView.setSelectedRange(NSRange(
            location: first.location + 1,
            length: NSMaxRange(second) - first.location - 2,
        ))
        #expect(canvas.textLineSelection == slot.paragraphs.lowerBound ... slot.paragraphs
            .lowerBound + 1)
        key("b", in: canvas)
        #expect(model.source.contains("{start_of_bridge}\n[G]Loose one\n[C]Loose two\n"))
        // Inside one lyric line, V is just a letter typed over the selection.
        canvas.lineSelection = nil
        let line = try #require(canvas.projection.paragraphs.firstIndex { $0.text == "Verse line" })
        let range = canvas.projection.range(of: line)
        canvas.textView.setSelectedRange(NSRange(location: range.location, length: 5))
        #expect(canvas.activeLineSelection == nil)
        canvas.textView.insertText("v", replacementRange: canvas.textView.selectedRange())
        #expect(model.source.contains("[G]v line"), "\(model.source)")
    }

    @Test
    func `band accessibility actions resize, unwrap and relabel without a drag`() throws {
        let hosted = host()
        let (model, canvas) = (hosted.model, hosted.canvas)
        defer { hosted.window.close() }
        let elements = canvas.overlayAccessibilityElements(for: canvas.container.overlay)
            .compactMap { $0 as? NSAccessibilityElement }
        let band = try #require(elements.first {
            $0.accessibilityIdentifier() == AccessibilityID.sectionBand
        })
        #expect(band.accessibilityLabel() == "Verse 1")
        let names = band.accessibilityCustomActions()?.map(\.name) ?? []
        for name in [
            "Rename",
            "Change to Chorus",
            "Extend Up One Line",
            "Unwrap",
            "Split in Half",
        ] {
            #expect(names.contains(name), "\(names)")
        }
        let extend = try #require(band.accessibilityCustomActions()?.first {
            $0.name == "Extend Up One Line"
        })
        #expect(extend.handler?() == true)
        #expect(
            model.source.contains("[C]Loose two\n{start_of_verse: Verse 1}\n[D]Loose three"),
            "\(model.source)",
        )
        let slot = try #require(elements.first {
            $0.accessibilityIdentifier() == AccessibilityID.sectionBandSlot
        })
        #expect(slot.accessibilityValue() as? String == "3 lines")
    }

    @Test
    func `the section menu offers the band actions`() throws {
        let hosted = host()
        let canvas = hosted.canvas
        defer { hosted.window.close() }
        let verse = try #require(canvas.bands.bands.firstIndex { $0.sectionPath != nil })
        let frame = try #require(canvas.bandFrame(verse))
        let point = canvas.textView.convert(
            CGPoint(x: frame.rect.midX, y: frame.rect.maxY - 10),
            to: nil,
        )
        let event = try #require(NSEvent.mouseEvent(
            with: .rightMouseDown,
            location: point,
            modifierFlags: [],
            timestamp: 0,
            windowNumber: hosted.window.windowNumber,
            context: nil,
            eventNumber: 0,
            clickCount: 1,
            pressure: 1,
        ))
        let menu = try #require(canvas.bandMenu(for: event))
        #expect(menu.items.map(\.title) == [
            "Rename...", "Change Kind", "Unwrap", "Split Here", "Merge with Next", "",
            "Section Notes...", "Add Note to Verse 1...", "",
            "Insert Key Change Here...", "Insert Time Change Here...",
            "Insert Tempo Change Here...",
        ])
        // The pointer is on the verse's second line: Split Here applies; nothing follows.
        #expect(menu.items[3].isEnabled)
        #expect(!menu.items[4].isEnabled)
    }
}
