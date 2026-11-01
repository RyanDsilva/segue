import ChordPro
import Editing
import Foundation
import Library
import Testing

/// The singer transform (P9-2 section 5): chords gone, lyric text byte for byte, comments and
/// names kept, wordless parts as "Instrumental".
struct SingerViewTests {
    private static func model(_ source: String, options: DisplayOptions = DisplayOptions())
        -> RenderModel
    {
        RenderModel(document: ChordProParser.parse(source).0, options: options)
    }

    private static func lyrics(_ section: RenderSection) -> [String] {
        section.items.compactMap { item in
            if case let .lyrics(line) = item {
                return line.lyrics
            }
            return nil
        }
    }

    private static func comments(_ section: RenderSection) -> [String] {
        section.items.compactMap { item in
            if case let .comment(text, _, _) = item {
                return text
            }
            return nil
        }
    }

    @Test(arguments: [
        ("Tu[G]jh mein [D]rab dikh[Em]ta hai", "Tujh mein rab dikhta hai"),
        ("Ke[A]sari[E]ya te[F#m]ra", "Kesariya tera"),
        ("Hello [G]world [D]", "Hello world"),
        ("  Indented   inner  [C]", "  Indented   inner"),
        ("[Am]चलते चलते [G]इस राह पे", "चलते चलते इस राह पे"),
        ("प[G]्यार", "प्यार"),
    ])
    func `a line loses its chords and keeps its text`(source: String, expected: String) throws {
        let model = Self.model("{start_of_verse: Verse}\n\(source)\n{end_of_verse}")
        let section = try #require(SingerView.sections(model.sections).first)
        #expect(Self.lyrics(section) == [expected])
        for case let .lyrics(line) in section.items {
            #expect(line.chords.isEmpty)
        }
    }

    @Test(arguments: [
        ("[G] [D] [Em]", false),
        ("| G . . | D . . |", false),
        ("x2", false),
        ("(x3)", false),
        ("×2", false),
        ("- - -", false),
        ("Oh oh oh", true),
        ("(Hum hum)", true),
        ("Tujh mein rab x2", true),
        ("Tujh mein rab (x2)", true),
    ])
    func `lines without lyric words are dropped`(line: String, kept: Bool) throws {
        let model = Self.model("{start_of_verse: Verse}\nSing this\n\(line)\n{end_of_verse}")
        let section = try #require(SingerView.sections(model.sections).first)
        let lines = Self.lyrics(section)
        #expect(lines.count == (kept ? 2 : 1), "\(line)")
        if kept {
            #expect(lines.last == line)
        }
    }

    @Test(arguments: [
        ("G D Em C", false),
        ("Am | F | C G", false),
        ("N.C. G", false),
        ("Key change", true),
        ("Softly", true),
        ("Am I dreaming", true),
        ("All together", true),
    ])
    func `comments stay unless they are a chord line`(comment: String, kept: Bool) throws {
        let model = Self.model(
            "{start_of_chorus: Chorus}\n{c: \(comment)}\nSing [G]this\n{end_of_chorus}",
        )
        let section = try #require(SingerView.sections(model.sections).first)
        #expect(Self.comments(section) == (kept ? [comment] : []))
    }

    @Test
    func `tab, grids and fill tabs go and stanza breaks collapse`() throws {
        let source = """
        {start_of_verse: Verse}

        One [G]line


        Two [D]line
        [G] [D]

        {end_of_verse}
        {start_of_tab: Riff}
        e|---0---|
        {end_of_tab}
        """
        let model = Self.model(source)
        let singer = SingerView.sections(model.sections)
        let verse = try #require(singer.first)
        let kinds = verse.items.map { item -> String in
            switch item {
            case .lyrics: "line"
            case .stanzaBreak: "break"
            default: "other"
            }
        }
        #expect(kinds == ["line", "break", "line"])
        let tab = try #require(singer.last)
        #expect(tab.label == "Riff")
        #expect(Self.comments(tab) == [SingerView.instrumentalText])
        #expect(!tab.items.contains {
            if case .verbatim = $0 {
                true
            } else {
                false
            }
        })
    }

    @Test
    func `a labelled wordless part reads Instrumental after its comments`() throws {
        let source = """
        {start_of_verse: Intro}
        {c: Guitar only}
        [Am] [G] [F] [E]
        {end_of_verse}
        {start_of_verse: Verse}
        Sing [Am]here
        {end_of_verse}
        """
        let model = Self.model(source)
        let intro = try #require(SingerView.sections(model.sections).first)
        #expect(intro.label == "Intro")
        #expect(Self.comments(intro) == ["Guitar only", SingerView.instrumentalText])
        #expect(SingerView.isInstrumental(model.sections[0]))
        #expect(!SingerView.isInstrumental(model.sections[1]))
        guard case let .comment(_, style, _) = intro.items.last else {
            Issue.record("no placeholder")
            return
        }
        #expect(style == .italic)
    }

    @Test
    func `an unlabelled wordless block is left out of previews but kept as a stage pass`() {
        let source = """
        [G] [D] [Em]

        {start_of_verse: Verse}
        Sing [Am]here
        {end_of_verse}
        """
        let model = Self.model(source)
        #expect(model.sections.count == 2)
        let singer = SingerView.sections(model.sections)
        #expect(singer.map(\.label) == ["Verse"])
        // The stage keeps every pass (the map names it), so one section never vanishes.
        let pass = SingerView.section(model.sections[0])
        #expect(Self.comments(pass) == [SingerView.instrumentalText])
    }

    @Test
    func `a song of only an instrumental shows one Instrumental section`() throws {
        let model = Self.model("{title: Jam}\n[G] [D] [Em] [C]\n")
        let singer = SingerView.sections(model.sections)
        #expect(singer.count == 1)
        #expect(try Self.comments(#require(singer.first)) == [SingerView.instrumentalText])
    }

    @Test
    func `a chorus repeat stub is left for its target`() {
        let source = """
        {start_of_chorus}
        Sing [G]this
        {end_of_chorus}
        {chorus}
        """
        let model = Self.model(source)
        let singer = SingerView.sections(model.sections)
        #expect(singer.count == 2)
        #expect(singer[1] == model.sections[1])
        #expect(!SingerView.isInstrumental(model.sections[1]))
    }

    @Test(arguments: EditingFixtures.wellFormed)
    func `ids, paths, kinds, labels and order hold and lyrics are byte identical`(name: String)
        throws
    {
        let model = try LiveLayoutSupport.model(name)
        for original in model.sections {
            let singer = SingerView.section(original)
            #expect(singer.id == original.id)
            #expect(singer.path == original.path)
            #expect(singer.kind == original.kind)
            #expect(singer.label == original.label)
            #expect(singer.isRepeat == original.isRepeat)
            var source: [BlockPath: String] = [:]
            for case let .lyrics(line) in original.items {
                source[line.path] = line.lyrics
            }
            for case let .lyrics(line) in singer.items {
                #expect(line.chords.isEmpty)
                let written = try #require(source[line.path])
                #expect(Array(line.lyrics.utf8)
                    == Array(SingerViewSupport.trimmingTrailing(written).utf8))
            }
        }
        // The preview list keeps the source order.
        let ids = SingerView.sections(model.sections).map(\.id)
        #expect(ids == ids.sorted())
    }

    @Test
    func `the model drops diagrams and capo and names the sounding key`() {
        let source = "{title: T}\n{key: G}\n{capo: 2}\n[G]Sing [D]here\n"
        var options = DisplayOptions()
        options.transpose = 2
        options.showDiagrams = true
        let chart = Self.model(source, options: options)
        #expect(!chart.diagrams.isEmpty)
        let singer = SingerView.model(chart)
        #expect(singer.diagrams.isEmpty)
        #expect(singer.header.capo == nil)
        // G written, capo 2, transposed +2: it sounds in B.
        #expect(singer.header.key == "B")
        #expect(singer.header.title == chart.header.title)
        #expect(singer.header.artists == chart.header.artists)
    }

    @Test(arguments: PassMode.allCases)
    func `a chords only pass shows its first line in singer view`(mode: PassMode) {
        #expect(mode.singer == (mode == .chordsOnly ? .firstLine : mode))
    }
}

/// The byte-identity rule's reference: trailing whitespace trimmed, nothing else.
enum SingerViewSupport {
    static func trimmingTrailing(_ text: String) -> String {
        var text = text
        while text.last?.isWhitespace == true {
            text.removeLast()
        }
        return text
    }
}
