import ChordPro
import Editing
@testable import SegueUI
import Testing

/// `{` directive completion after the R81 fixes: plain names beside directives, section
/// words offer `start_of_` (labelled and plain) first, short forms are aliases, and
/// accepting writes the directive through the real text view.
@MainActor
struct EditorCompletionTests {
    private func items(_ prefix: String, in text: String = "", open: String? = nil) -> [String] {
        let document = SourceSnapshot(text: text).document
        return DirectiveSuggestions.items(prefix: prefix, openSection: open, document: document)
            .map(\.body)
    }

    @Test
    func `a section word offers the labelled and plain start first`() {
        // The numbering rule (P3-11): the first chorus, bridge, intro or outro is unlabelled.
        #expect(Array(items("cho").prefix(2)) == ["start_of_chorus", "chorus"])
        let verse = "{start_of_verse: Verse 1}\nLa\n{end_of_verse}\n"
        #expect(Array(items("verse", in: verse).prefix(2)) == [
            "start_of_verse: Verse 2", "start_of_verse",
        ])
        #expect(items("bri").first == "start_of_bridge")
        #expect(items("int").first == "start_of_intro")
        #expect(items("out").first == "start_of_outro")
    }

    @Test
    func `the chorus directive is the repeat and every item has a plain name`() throws {
        let document = SongDocument(blocks: [])
        let all = DirectiveSuggestions.all(document: document)
        let repeatItem = try #require(all.first { $0.body == "chorus" })
        #expect(repeatItem.title == "Chorus (repeat)")
        #expect(repeatItem.detail == "{chorus}")
        let plain = all.filter { $0.title.first?.isUppercase == true }
        #expect(plain.count == all.count)
        #expect(all.first { $0.body == "duration: " }?.title == "Length")
    }

    @Test(arguments: [
        ("soc", "start_of_chorus"),
        ("eoc", "end_of_chorus"),
        ("sov", "start_of_verse: Verse 1"),
        ("eov", "end_of_verse"),
        ("sob", "start_of_bridge"),
        ("eob", "end_of_bridge"),
        ("c", "comment: "),
    ])
    func `short forms are aliases of their long forms`(alias: String, first: String) {
        #expect(items(alias).first == first)
    }

    @Test
    func `inside an open section its end comes first`() {
        #expect(items("", open: "chorus").first == "end_of_chorus")
        #expect(items("e", open: "verse").first == "end_of_verse")
    }

    @Test
    func `metadata prefixes still find their directive`() {
        #expect(items("ti").first == "title: ")
        #expect(items("len").first == "duration: ")
        #expect(items("time").first == "time: ")
        #expect(items("al").first == "album: ")
    }

    @Test
    func `accepting a section start writes it through the text view`() {
        let editor = HostedSourceEditor("{start_of_verse: Verse 1}\nLa\n{end_of_verse}\n\n")
        defer { editor.close() }
        editor.select(45)
        editor.type("{cho")
        #expect(editor.source.completion.kind == .directive)
        #expect(editor.source.completion.items.first
            == CompletionPopup.Entry(title: "Chorus", detail: "{start_of_chorus}"))
        editor.accept()
        #expect(editor.model.source.hasSuffix("\n{start_of_chorus}"))
    }
}
