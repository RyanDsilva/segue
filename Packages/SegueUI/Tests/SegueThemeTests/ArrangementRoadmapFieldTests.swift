import AppKit
import ChordPro
import Library
@testable import SegueUI
import SwiftUI
import Testing

/// Arrange Sections' roadmap field in a real window (P8-3 section 6.5): spell-check,
/// autocorrect and completion are off (romanized part labels), typing previews, Return
/// commits and Esc reverts through the field editor.
@MainActor
struct ArrangementRoadmapFieldTests {
    @Test
    func `the roadmap field checks no spelling and maps Return and Esc`() throws {
        let units = SongSections.units(of: ChordProParser.parse("""
        {start_of_verse: Verse 1}
        [G]Tum hi ho
        {end_of_verse}
        {start_of_chorus}
        [C]Kesariya tera
        {end_of_chorus}
        """).0)
        let draft = ArrangementDraft(arrangement: nil, units: units)
        var edits: [String] = []
        var commits = 0
        var reverts = 0
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 640, height: 200),
            styleMask: [.titled],
            backing: .buffered,
            defer: false,
        )
        window.isReleasedWhenClosed = false
        defer { window.close() }
        window.contentView = NSHostingView(rootView: ArrangementRoadmapField(
            draft: draft,
            isReadOnly: false,
            text: .constant("V1 C"),
            error: nil,
            isFocused: .constant(false),
            onEdit: { edits.append($0) },
            onCommit: { commits += 1 },
            onRevert: { reverts += 1 },
        ))
        window.contentView?.layoutSubtreeIfNeeded()
        let field = try #require(Self.field(in: window.contentView))
        #expect(field.accessibilityIdentifier() == AccessibilityID.arrangementRoadmap)
        #expect(field.stringValue == "V1 C")

        window.makeFirstResponder(field)
        let editor = try #require(field.currentEditor() as? NSTextView)
        #expect(ComposerTextFieldCell.report(editor) == "continuousSpelling=off grammar=off "
            + "spelling=off replacement=off quotes=off dashes=off completion=off undo=off")
        #expect(editor !== window.fieldEditor(true, for: nil))

        editor.insertText(" C:ch", replacementRange: NSRange(location: 4, length: 0))
        #expect(edits.last == "V1 C C:ch")
        editor.doCommand(by: #selector(NSResponder.insertNewline(_:)))
        #expect(commits == 1)
        editor.doCommand(by: #selector(NSResponder.cancelOperation(_:)))
        #expect(reverts == 1)
    }

    private static func field(in view: NSView?) -> ComposerNSTextField? {
        guard let view else { return nil }
        if let field = view as? ComposerNSTextField {
            return field
        }
        return view.subviews.lazy.compactMap { field(in: $0) }.first
    }
}
