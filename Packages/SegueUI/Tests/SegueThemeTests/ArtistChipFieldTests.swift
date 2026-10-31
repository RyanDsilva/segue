import AppKit
import Library
import Observation
@testable import SegueUI
import SwiftUI
import Testing

/// The artist chip field (P8-8 section 3.3, 13.2): its rules (pure) and the field itself in
/// a real window, driven through its field editor as a user types.
@MainActor
struct ArtistChipFieldTests {
    // MARK: Rules

    @Test(arguments: [
        ("  Arijit Singh ", [], ArtistChipEditing.Commit.added(["Arijit Singh"])),
        ("Vishal & Shekhar", ["A"], .added(["A", "Vishal & Shekhar"])),
        ("arijit singh", ["Arijit Singh"], .duplicate(index: 0)),
        ("Arijít Singh", ["X", "Arijit Singh"], .duplicate(index: 1)),
        ("   ", ["A"], .empty),
    ])
    func `a commit keeps the text as typed and refuses duplicates`(
        typed: String,
        artists: [String],
        expected: ArtistChipEditing.Commit,
    ) {
        #expect(ArtistChipEditing.commit(typed, to: artists) == expected)
    }

    @Test
    func `a comma commits what is before it`() throws {
        let one = try #require(ArtistChipEditing.commas(in: "Arijit Singh,", artists: []))
        #expect(one.finished == ["Arijit Singh"] && one.rest.isEmpty)
        let two = try #require(ArtistChipEditing.commas(
            in: "Shreya Ghoshal, arijit singh, Sonu",
            artists: ["Arijit Singh"],
        ))
        #expect(two.finished == ["Shreya Ghoshal"] && two.rest == "Sonu")
        #expect(ArtistChipEditing.commas(in: "Vishal & Shekhar", artists: []) == nil)
    }

    @Test
    func `suggestions match normalized words and skip chips already there`() {
        let known = ["Shreya Ghoshal", "Arijit Singh", "Vishal & Shekhar", "Shaan"]
        #expect(ArtistChipEditing.suggestions(for: "shreya goshal", applied: [], known: known)
            == ["Shreya Ghoshal"])
        #expect(ArtistChipEditing.suggestions(for: "ghosh", applied: [], known: known)
            == ["Shreya Ghoshal"])
        #expect(ArtistChipEditing.suggestions(for: "sh", applied: ["Shaan"], known: known)
            == ["Shreya Ghoshal", "Vishal & Shekhar"])
        #expect(ArtistChipEditing.suggestions(for: " ", applied: [], known: known).isEmpty)
    }

    @Test
    func `split replaces the chip in place and reorder moves one`() {
        let list = ["Badshah", "Vishal & Shekhar feat. Badshah", "Neha Kakkar"]
        #expect(ArtistChipEditing.canSplit(list[1]) && !ArtistChipEditing.canSplit(list[0]))
        #expect(ArtistChipEditing.split(list, at: 1)
            == ["Badshah", "Vishal", "Shekhar", "Neha Kakkar"])
        #expect(ArtistChipEditing.split(list, at: 0) == nil)
        #expect(ArtistChipEditing.move(list, from: 2, by: -1)
            == ["Badshah", "Neha Kakkar", "Vishal & Shekhar feat. Badshah"])
        #expect(ArtistChipEditing.move(list, from: 0, by: -1) == nil)
        #expect(ArtistChipEditing.move(list, from: 0, to: 2)
            == ["Vishal & Shekhar feat. Badshah", "Neha Kakkar", "Badshah"])
    }

    // MARK: The field

    @Observable
    final class Box {
        var artists: [String]
        var changes: [ArtistChipChange] = []

        init(_ artists: [String]) {
            self.artists = artists
        }
    }

    private struct Host: View {
        let box: Box
        let known: [String]

        var body: some View {
            ArtistChipField(artists: box.artists, suggestions: known) { change in
                box.changes.append(change)
                box.artists = change.artists
            }
            .frame(width: 420)
        }
    }

    private func open(_ box: Box, known: [String] = [], disabled: Bool = false)
        throws -> (NSWindow, ComposerNSTextField)
    {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 240),
            styleMask: [.titled],
            backing: .buffered,
            defer: false,
        )
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: Host(box: box, known: known)
            .disabled(disabled))
        window.contentView?.layoutSubtreeIfNeeded()
        let field = try #require(Self.field(in: window.contentView))
        return (window, field)
    }

    @Test
    func `typing commits chips with Return and comma, and Backspace twice removes one`()
        throws
    {
        let box = Box(["Arijit Singh"])
        let (window, field) = try open(box, known: ["Shreya Ghoshal"])
        defer { window.close() }
        #expect(field.accessibilityIdentifier() == AccessibilityID.songCardArtistInput)
        window.makeFirstResponder(field)
        let editor = try #require(field.currentEditor() as? NSTextView)
        #expect(ComposerTextFieldCell.report(editor) == "continuousSpelling=off grammar=off "
            + "spelling=off replacement=off quotes=off dashes=off completion=off undo=off")

        // Return commits the typed text as typed, never the suggestion it matches.
        editor.insertText("shre", replacementRange: editor.selectedRange())
        settle(window)
        editor.doCommand(by: #selector(NSResponder.insertNewline(_:)))
        settle(window)
        #expect(box.artists == ["Arijit Singh", "shre"])

        // A comma commits; a duplicate is refused.
        editor.insertText("Mithoon,", replacementRange: editor.selectedRange())
        settle(window)
        #expect(box.artists == ["Arijit Singh", "shre", "Mithoon"])
        editor.insertText("arijit singh", replacementRange: editor.selectedRange())
        settle(window)
        editor.doCommand(by: #selector(NSResponder.insertNewline(_:)))
        settle(window)
        #expect(box.artists.count == 3)
        editor.selectAll(nil)
        settle(window)
        editor.insertText("", replacementRange: editor.selectedRange())
        settle(window)

        // Backspace in the empty input selects the last chip, a second one removes it.
        editor.doCommand(by: #selector(NSResponder.deleteBackward(_:)))
        settle(window)
        #expect(box.artists.count == 3)
        editor.doCommand(by: #selector(NSResponder.deleteBackward(_:)))
        settle(window)
        #expect(box.artists == ["Arijit Singh", "shre"])
        #expect(box.changes.map(\.edit) == [.add, .add, .remove])
    }

    @Test
    func `a suggestion applies only on an explicit pick`() throws {
        let box = Box([])
        let (window, field) = try open(box, known: ["Shreya Ghoshal", "Shaan"])
        defer { window.close() }
        window.makeFirstResponder(field)
        let editor = try #require(field.currentEditor() as? NSTextView)
        editor.insertText("shreya goshal", replacementRange: editor.selectedRange())
        settle(window)
        editor.doCommand(by: #selector(NSResponder.moveDown(_:)))
        settle(window)
        editor.doCommand(by: #selector(NSResponder.insertNewline(_:)))
        settle(window)
        #expect(box.artists == ["Shreya Ghoshal"])
        editor.insertText("sha", replacementRange: editor.selectedRange())
        settle(window)
        editor.doCommand(by: #selector(NSResponder.insertTab(_:)))
        settle(window)
        #expect(box.artists == ["Shreya Ghoshal", "Shaan"])
    }

    @Test
    func `a read-only song disables the field`() throws {
        let (window, field) = try open(Box(["Arijit Singh"]), disabled: true)
        defer { window.close() }
        #expect(!field.isEnabled)
    }

    /// Lets SwiftUI apply the state a command changed (the field's text follows it).
    private func settle(_ window: NSWindow) {
        RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        window.contentView?.layoutSubtreeIfNeeded()
    }

    private static func field(in view: NSView?) -> ComposerNSTextField? {
        guard let view else { return nil }
        if let field = view as? ComposerNSTextField {
            return field
        }
        return view.subviews.lazy.compactMap { field(in: $0) }.first
    }
}
