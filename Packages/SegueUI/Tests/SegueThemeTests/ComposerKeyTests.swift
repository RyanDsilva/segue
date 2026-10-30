import AppKit
import Foundation
import Library
@testable import SegueUI
import Setlists
import Support
import SwiftUI
import Testing

/// The set composer's text field in a real window (P8-5 section 13.4): the field editor's
/// key commands drive the composer, and every text substitution is off (romanized Hindi is
/// never corrected; "---" stays three hyphens).
@MainActor
struct ComposerKeyTests {
    private struct Hosted {
        var env: TestEnvironment
        var session: LibrarySession
        var window: NSWindow
        var field: ComposerNSTextField
        var friday: SetlistID
    }

    private static func host() async throws -> Hosted {
        let env = try TestEnvironment()
        for folder in ["songs", "setlists"] {
            try FileManager.default.createDirectory(
                at: env.libraryURL.appending(path: folder, directoryHint: .isDirectory),
                withIntermediateDirectories: true,
            )
        }
        for (slug, title) in [("a", "Tum Hi Ho"), ("b", "Tum Hi Ho Bandhu"), ("c", "Kesariya")] {
            try env.write("{title: \(title)}\n{key: G}\n[G]La la\n", to: "songs/\(slug).cho")
        }
        let fridayID = "01JC0000000000000000000F01"
        try env.write(
            #"{"schemaVersion": 3, "id": "\#(fridayID)", "name": "Friday", "entries": []}"#,
            to: "setlists/friday.setlist.json",
        )
        let app = try await env.openApp()
        let session = try #require(app.session)
        let friday = try SetlistID(#require(ULID(string: fridayID)))
        let setlist = try #require(session.setlists.setlist(friday))
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 900, height: 300),
            styleMask: [.titled],
            backing: .buffered,
            defer: false,
        )
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: SetComposerRow(
            setlist: setlist,
            model: session.setlists,
            library: session.library,
            composer: session.setlists.composer,
        ))
        window.contentView?.layoutSubtreeIfNeeded()
        let field = try #require(Self.field(in: window.contentView))
        return Hosted(env: env, session: session, window: window, field: field, friday: friday)
    }

    private static func field(in view: NSView?) -> ComposerNSTextField? {
        guard let view else { return nil }
        if let field = view as? ComposerNSTextField {
            return field
        }
        return view.subviews.lazy.compactMap { field(in: $0) }.first
    }

    /// Types `text` through the field editor, as keystrokes would.
    private func type(_ text: String, into hosted: Hosted) throws {
        let editor = try #require(hosted.field.currentEditor() as? NSTextView)
        editor.insertText(text, replacementRange: editor.selectedRange())
    }

    private func press(_ selector: Selector, in hosted: Hosted) throws {
        let editor = try #require(hosted.field.currentEditor() as? NSTextView)
        editor.doCommand(by: selector)
    }

    @Test
    func `the field editor keys drive the composer`() async throws {
        let hosted = try await Self.host()
        defer { hosted.window.close() }
        let composer = hosted.session.setlists.composer
        composer.requestFocus()
        hosted.window.makeFirstResponder(hosted.field)
        #expect(composer.isFocused)

        try type("tum hi", into: hosted)
        #expect(composer.text == "tum hi")
        #expect(composer.resolution.matches.count == 2)

        try press(#selector(NSResponder.moveDown(_:)), in: hosted)
        #expect(composer.choice == 1)
        #expect(composer.showsAlternatives)
        try press(#selector(NSResponder.insertTab(_:)), in: hosted)
        #expect(composer.choice == 0)
        try press(#selector(NSResponder.insertBacktab(_:)), in: hosted)
        #expect(composer.choice == 1)
        try press(#selector(NSResponder.moveUp(_:)), in: hosted)
        #expect(composer.choice == 0)
        // Tab never moves focus away while there is text.
        #expect(hosted.window.firstResponder === hosted.field.currentEditor())

        // Escape: close the list, then clear the line.
        try press(#selector(NSResponder.cancelOperation(_:)), in: hosted)
        #expect(!composer.showsAlternatives)
        #expect(composer.text == "tum hi")
        try press(#selector(NSResponder.cancelOperation(_:)), in: hosted)
        #expect(composer.text.isEmpty)
        // The field follows the model on SwiftUI's next update.
        try await hosted.env.waitFor { hosted.field.stringValue.isEmpty ? true : nil }

        // Return appends the shown song and clears the line, focus kept.
        try type("kesar", into: hosted)
        try press(#selector(NSResponder.insertNewline(_:)), in: hosted)
        try await hosted.env.waitFor {
            hosted.session.setlists.setlist(hosted.friday)?.songCount == 1 ? true : nil
        }
        try await hosted.env.waitFor { composer.text.isEmpty ? true : nil }
        #expect(hosted.field.stringValue.isEmpty)
        #expect(hosted.window.firstResponder === hosted.field.currentEditor())
    }

    @Test
    func `every substitution and the text undo are off in the field editor`() async throws {
        let hosted = try await Self.host()
        defer { hosted.window.close() }
        hosted.window.makeFirstResponder(hosted.field)
        let editor = try #require(hosted.field.currentEditor() as? NSTextView)
        #expect(ComposerTextFieldCell.report(editor) == "continuousSpelling=off grammar=off "
            + "spelling=off replacement=off quotes=off dashes=off completion=off undo=off")
        #expect(editor.enabledTextCheckingTypes == 0)
        #expect(editor.inlinePredictionType == .no)
        // The composer has its own field editor: the window's shared one is untouched.
        #expect(editor !== hosted.window.fieldEditor(true, for: nil))

        try type("---", into: hosted)
        #expect(hosted.session.setlists.composer.text == "---")
        #expect(hosted.session.setlists.composer.resolution.kind == .breakRow)
        try type(" kitaabon mein", into: hosted)
        #expect(hosted.field.stringValue == "--- kitaabon mein")
    }

    @Test
    func `the key commands map from the field editor selectors`() {
        typealias Coordinator = ComposerTextField.Coordinator
        #expect(Coordinator.command(for: #selector(NSResponder.insertNewline(_:))) == .accept)
        #expect(Coordinator.command(for: #selector(NSResponder.moveDown(_:))) == .next)
        #expect(Coordinator.command(for: #selector(NSResponder.moveUp(_:))) == .previous)
        #expect(Coordinator.command(for: #selector(NSResponder.insertTab(_:))) == .tab)
        #expect(Coordinator.command(for: #selector(NSResponder.insertBacktab(_:))) == .backtab)
        #expect(Coordinator.command(for: #selector(NSResponder.cancelOperation(_:))) == .escape)
        #expect(Coordinator.command(for: #selector(NSResponder.moveLeft(_:))) == nil)
    }
}
