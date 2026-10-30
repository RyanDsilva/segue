import AppKit
import ChordPro
import Editing
@testable import SegueUI
import Testing

/// Custom section names offered again (R159): the song's own names as extra chips after
/// Outro, in the section menus and VoiceOver actions, and Custom... suggesting the
/// library's names.
extension SectionBandTests {
    static let hooked = """
    {title: Hooks}

    [G]Loose one
    [C]Loose two

    {start_of_hook}
    [G]Hook line
    {end_of_hook}

    """

    private static func sections(_ names: [String]) -> String {
        "{title: Many}\n\n[G]Loose one\n\n" + names.map {
            "{start_of_\($0)}\n[G]\($0) line\n{end_of_\($0)}\n\n"
        }.joined()
    }

    private func rightClick(at point: CGPoint, in hosted: Hosted) throws -> NSEvent {
        try #require(NSEvent.mouseEvent(
            with: .rightMouseDown,
            location: hosted.canvas.textView.convert(point, to: nil),
            modifierFlags: [],
            timestamp: 0,
            windowNumber: hosted.window.windowNumber,
            context: nil,
            eventNumber: 0,
            clickCount: 1,
            pressure: 1,
        ))
    }

    private func menu(of band: Int, in hosted: Hosted) throws -> NSMenu {
        let frame = try #require(hosted.canvas.bandFrame(band))
        let point = CGPoint(x: frame.rect.midX, y: frame.rect.minY + 4)
        return try #require(hosted.canvas.bandMenu(for: rightClick(at: point, in: hosted)))
    }

    @Test
    func `a custom kind the song uses is a chip after Outro and one undo step`() throws {
        let hosted = host(Self.hooked)
        let (model, canvas) = (hosted.model, hosted.canvas)
        defer { hosted.window.close() }
        let slot = try #require(canvas.bands.bands.first { $0.kind == .slot })
        canvas.lineSelection = slot.paragraphs
        canvas.updateChipBar()
        let bar = try #require(canvas.chipBar.shown)
        #expect(bar.chipTitles == [
            "Verse", "Chorus", "Bridge", "Intro", "Outro", "Hook", "Custom...",
        ])

        let hook = try #require(bar.shownExtras.first)
        #expect(canvas.applySection(hook.kind))
        // A second, different hook: both are numbered (the usual rule).
        #expect(model.source.contains("""
        {start_of_hook: Hook 1}
        [G]Loose one
        [C]Loose two
        {end_of_hook}
        """), "\(model.source)")
        model.sourceEditor.undoManager.undo()
        #expect(model.source == Self.hooked)
    }

    @Test
    func `menus and VoiceOver offer the song's custom kinds`() throws {
        let hosted = host(Self.hooked)
        let canvas = hosted.canvas
        defer { hosted.window.close() }
        let slotIndex = try #require(canvas.bands.bands.firstIndex { $0.kind == .slot })
        let slotMenu = try menu(of: slotIndex, in: hosted)
        #expect(slotMenu.items.map(\.title) == [
            "Make Verse", "Make Chorus", "Make Bridge", "Make Intro", "Make Outro", "Make Hook",
        ])

        let hookIndex = try #require(canvas.bands.bands.firstIndex { $0.sectionPath != nil })
        let sectionMenu = try menu(of: hookIndex, in: hosted)
        let kinds = try #require(sectionMenu.items.first { $0.title == "Change Kind" }?.submenu)
        #expect(kinds.items.map(\.title) == [
            "Verse", "Chorus", "Bridge", "Intro", "Outro", "Hook", "Tab", "Custom...",
        ])

        let elements = canvas.overlayAccessibilityElements(for: canvas.container.overlay)
            .compactMap { $0 as? NSAccessibilityElement }
        let slot = try #require(elements.first {
            $0.accessibilityIdentifier() == AccessibilityID.sectionBandSlot
        })
        #expect(slot.accessibilityCustomActions()?.map(\.name).contains("Make Hook") == true)
    }

    @Test
    func `five custom kinds show four chips while the menus list all five`() throws {
        let names = ["hook", "tag", "solo", "antara", "mukhda"]
        let hosted = host(Self.sections(names))
        let canvas = hosted.canvas
        defer { hosted.window.close() }
        let slot = try #require(canvas.bands.bands.first { $0.kind == .slot })
        canvas.lineSelection = slot.paragraphs
        canvas.updateChipBar()
        let bar = try #require(canvas.chipBar.shown)
        #expect(bar.shownExtras.map(\.title) == ["Hook", "Tag", "Solo", "Antara"])
        #expect(canvas.sectionOffers.suffix(5).map(\.title)
            == ["Hook", "Tag", "Solo", "Antara", "Mukhda"])
    }

    @Test
    func `the custom name field suggests song then library names, uncorrected`() throws {
        let hosted = host(Self.hooked)
        let (model, canvas) = (hosted.model, hosted.canvas)
        defer { hosted.window.close() }
        let tag = SectionKind.custom("tag")
        model.librarySectionKinds = {
            SectionLabels.customKinds(in: [
                "{start_of_tag}\nA\n{end_of_tag}", "{start_of_tag}\nB\n{end_of_tag}",
                "{start_of_tag}\nC\n{end_of_tag}\n{start_of_hook}\nD\n{end_of_hook}",
                "{start_of_solo}\nE\n{end_of_solo}",
            ].map { ChordProParser.parse($0).0 })
        }
        #expect(model.librarySectionKinds().first == tag)

        let field = canvas.sectionNameField()
        #expect(field.objectValues as? [String] == ["Hook", "Tag", "Solo"])
        #expect(field.completes)
        #expect(field.accessibilityIdentifier() == AccessibilityID.sectionBandCustomField)

        hosted.window.contentView?.addSubview(field)
        #expect(hosted.window.makeFirstResponder(field))
        let editor = try #require(field.currentEditor() as? NSTextView)
        #expect(!editor.isAutomaticSpellingCorrectionEnabled)
        #expect(!editor.isAutomaticTextReplacementEnabled)
        #expect(editor.enabledTextCheckingTypes == 0)
        field.removeFromSuperview()
    }
}
