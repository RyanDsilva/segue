import AppKit
import ChordPro
import Editing
@testable import SegueUI
import Testing

/// The Text mode slash menu (R81, spec 16.0.2) through the real text view, parser and
/// section operation: fuzzy matching, wrapping a selection (one undo step, no lyric
/// change), inserting a numbered pair, Esc and mid-line `/`.
@MainActor
struct SlashMenuTests {
    static let lyrics = """
    {title: Raah}

    [Am]Purani si gali mein
    [F]Panne palatte haathon mein
    [Am]Chai ka cup thanda tha
    [F]Shaam ne dheere badle

    """

    @Test(arguments: [
        ("cho", "Chorus"), ("ch", "Chorus"), ("c", "Chorus"), ("soc", "Chorus"),
        ("v", "Verse"), ("sov", "Verse"), ("bri", "Bridge"), ("rep", "Chorus (repeat)"),
        ("no", "Note"), ("out", "Outro"), ("Intro", "Intro"), ("movie", "Movie / Album…"),
        ("film", "Movie / Album…"), ("album", "Movie / Album…"),
    ])
    func `fuzzy matching finds the item by word or alias`(query: String, title: String) {
        #expect(SlashMenu.matches(query, sections: .all).first?.title == title)
    }

    @Test
    func `sections are left out inside a section and alone when wrapping`() {
        let outside = SlashMenu.matches("", sections: .noSections).map(\.title)
        #expect(outside == [
            "Chorus (repeat)",
            "Note",
            "Movie / Album…",
            "Key…",
            "Tempo…",
            "Capo…",
            "Time…",
        ])
        let wrapping = SlashMenu.matches("", sections: .wrapOnly)
        #expect(wrapping.filter(\.isSection).count == wrapping.count)
        #expect(SlashMenu.matches("zzz", sections: .all).isEmpty)
    }

    @Test
    func `slash on a four line selection wraps it as one undo step with no lyric change`() {
        let editor = HostedSourceEditor(Self.lyrics)
        defer { editor.close() }
        let text = editor.source.textView.string as NSString
        let first = text.range(of: "[Am]Purani")
        let last = text.range(of: "badle")
        editor.select(first.location, length: last.location + last.length - first.location)

        editor.type("/cho")
        #expect(editor.source.completion.kind == .slash)
        #expect(editor.source.completion.items.first?.title == "Chorus")
        #expect(editor.source.textView.string == Self.lyrics, "typing filtered, not replaced")
        editor.accept()

        let wrapped = editor.model.source
        #expect(wrapped == """
        {title: Raah}

        {start_of_chorus}
        [Am]Purani si gali mein
        [F]Panne palatte haathon mein
        [Am]Chai ka cup thanda tha
        [F]Shaam ne dheere badle
        {end_of_chorus}

        """)
        let snapshot = SourceSnapshot(text: wrapped)
        #expect(snapshot.diagnostics.isEmpty)
        let before = SourceSnapshot(text: Self.lyrics).document.lyricText
        #expect(snapshot.document.lyricText == before)
        editor.source.undoManager.undo()
        #expect(editor.model.source == Self.lyrics)
    }

    @Test
    func `backspace edits the filter and esc leaves the selection alone`() {
        let editor = HostedSourceEditor(Self.lyrics)
        defer { editor.close() }
        let text = editor.source.textView.string as NSString
        let line = text.range(of: "[F]Panne palatte haathon mein")
        editor.select(line.location, length: line.length)
        editor.type("/vx")
        #expect(editor.source.completion.items.first?.title == "No match")
        editor.deleteBackward()
        #expect(editor.source.completion.items.first?.title == "Verse")
        _ = editor.source.handleCommand(#selector(NSResponder.cancelOperation(_:)))
        #expect(!editor.source.completion.isVisible)
        #expect(editor.source.textView.string == Self.lyrics)
    }

    @Test
    func `slash on an empty line inserts a numbered pair with the caret inside`() {
        let start = "{start_of_verse: Verse 1}\nLa\n{end_of_verse}\n\n"
        let editor = HostedSourceEditor(start)
        defer { editor.close() }
        editor.select((start as NSString).length)
        editor.type("/v")
        editor.accept()
        #expect(editor.model.source == start + "{start_of_verse: Verse 2}\n\n{end_of_verse}")
        let caret = editor.source.textView.selectedRange().location
        #expect(caret == (start as NSString).length + "{start_of_verse: Verse 2}\n".utf16.count)
    }

    @Test
    func `a second chorus numbers both in one undo step`() {
        let start = "{start_of_chorus}\nLa\n{end_of_chorus}\n\n"
        let editor = HostedSourceEditor(start)
        defer { editor.close() }
        editor.select((start as NSString).length)
        editor.type("/c")
        editor.accept()
        #expect(editor.model.source == """
        {start_of_chorus: Chorus 1}
        La
        {end_of_chorus}

        {start_of_chorus: Chorus 2}

        {end_of_chorus}
        """)
        editor.source.undoManager.undo()
        #expect(editor.model.source == start + "/c")
    }

    @Test
    func `esc leaves the slash typed and a mid-line slash is text`() {
        let editor = HostedSourceEditor("La la\n")
        defer { editor.close() }
        editor.select(6)
        editor.type("/")
        #expect(editor.source.completion.kind == .slash)
        _ = editor.source.handleCommand(#selector(NSResponder.cancelOperation(_:)))
        #expect(editor.model.source == "La la\n/")

        editor.select(5)
        editor.type(" /")
        #expect(!editor.source.completion.isVisible)
        #expect(editor.model.source == "La la /\n/")
    }

    @Test
    func `inside a section the menu offers no section`() {
        let editor = HostedSourceEditor("{start_of_verse}\nLa\n\n{end_of_verse}\n")
        defer { editor.close() }
        editor.select(20)
        editor.type("/")
        let titles = editor.source.completion.items.map(\.title)
        #expect(!titles.contains("Verse"))
        #expect(editor.source.completion.items.first?.title == "Chorus (repeat)")
    }
}

@MainActor
struct SlashMenuValueTests {
    @Test
    func `a value item writes the directive at the top and opens its choices`() {
        let start = "{title: Raah}\n\n[Am]Dil ki [Dm]baat [E]hai [Am]na\n"
        let editor = HostedSourceEditor(start)
        defer { editor.close() }
        editor.select((start as NSString).length)
        editor.type("/key")
        let menu = editor.source.completion.items
        #expect(menu.first?.title == "Key…", "\(menu)")
        editor.accept()
        let source = editor.model.source
        #expect(
            source == "{title: Raah}\n{key: }\n\n[Am]Dil ki [Dm]baat [E]hai [Am]na\n",
            "\(source)",
        )
        let keys = editor.source.completion.items
        #expect(keys.first == CompletionPopup.Entry(title: "Am", detail: "from chords"), "\(keys)")
        editor.accept()
        #expect(editor.model
            .source == "{title: Raah}\n{key: Am}\n\n[Am]Dil ki [Dm]baat [E]hai [Am]na\n")
        // The whole thing was one undo step for the directive, one for the value.
        editor.source.undoManager.undo()
        editor.source.undoManager.undo()
        #expect(editor.model.source == start + "/key")
    }

    @Test
    func `after key colon the key choices filter by what is typed`() {
        let editor = HostedSourceEditor("[G]La\n")
        defer { editor.close() }
        editor.select(0)
        editor.type("{key: F")
        #expect(editor.source.completion.items.map(\.title).prefix(2) == ["F", "F#"])
        editor.type("#m")
        #expect(editor.source.completion.items.first?.title == "F#m")
        editor.accept()
        #expect(editor.model.source.hasPrefix("{key: F#m"))
    }

    @Test
    func `time and capo offer their choices and tempo shows its format`() {
        let editor = HostedSourceEditor("")
        defer { editor.close() }
        editor.type("{time: ")
        #expect(editor.source.completion.items.map(\.title).prefix(3) == ["4/4", "3/4", "6/8"])
        editor.source.completion.hide()
        editor.type("}\n{tempo:")
        #expect(editor.source.completion.isVisible)
        #expect(editor.source.completion.items.isEmpty)
        // Return is not taken by the header-only hint.
        #expect(!editor.source.handleCommand(#selector(NSResponder.insertNewline(_:))))
    }
}

private extension SongDocument {
    /// Every lyric line's chords and words, in order (sections flattened).
    var lyricText: [[Segment]] {
        var lines: [[Segment]] = []
        for block in blocks {
            let items = if case let .section(section) = block {
                section.items
            } else {
                [block]
            }
            for case let .line(line) in items {
                lines.append(line.segments)
            }
        }
        return lines
    }
}
