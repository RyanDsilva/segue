import ChordPro
import Editing
import Library
import MusicTheory
import Testing

/// Mid-song `{key}`, `{time}` and `{tempo}` count from where they are written (P8-7 section
/// 5.3, R167 Q3, R168 Q2), while the song's own value stays the first one.
struct PositionalDirectiveTests {
    static let lift = """
    {key: G}
    {tempo: 96}
    {start_of_verse}
    [G]Hello [C]there [D]friend
    {end_of_verse}
    {start_of_chorus}
    [G]Sing it [C]loud
    {end_of_chorus}
    {key: A}
    {start_of_chorus}
    [A]Sing it [D]loud
    {end_of_chorus}

    """

    static func timeline(_ source: String, order: [PlayedPass]? = nil) -> SongTimeline {
        let (document, _) = ChordProParser.parse(source)
        let model = RenderModel(document: document, options: DisplayOptions())
        return SongTimeline.build(
            document: document,
            sections: model.sections,
            units: SongSections.units(of: document),
            timing: ChordTiming(),
            order: order,
        )
    }

    @Test
    func `a key change before the last chorus counts from there, the song keeps G`() {
        let (document, _) = ChordProParser.parse(Self.lift)
        let model = RenderModel(document: document, options: DisplayOptions())
        let timeline = Self.timeline(Self.lift)
        #expect(timeline.chords.map { $0.key?.name ?? "-" } == ["G", "G", "G", "G", "G", "A", "A"])
        // The library, filters and header keep the first key.
        #expect(document.metadata.key == "G")
        #expect(model.header.key == "G")
        let maps = PositionalDirectives.scan(document, sections: model.sections)
        #expect(maps.keys.initial?.name == "G")
        #expect(maps.keys.changes == [
            KeyMap.Change(from: ChordPosition(section: 2, chord: 0), value: SongKey(parsing: "A")),
        ])
        #expect(maps.keys.value(at: ChordPosition(section: 1, chord: 1))?.name == "G")
        #expect(maps.keys.value(at: ChordPosition(section: 2, chord: 1))?.name == "A")
    }

    struct Row: Sendable, CustomTestStringConvertible {
        var name: String
        var source: String
        /// Per chord in written order.
        var expected: [String]
        var read: @Sendable (TimedChord) -> String

        var testDescription: String {
            name
        }
    }

    static let keyName: @Sendable (TimedChord) -> String = { $0.key?.name ?? "-" }
    static let meterName: @Sendable (TimedChord) -> String = { $0.meter.description }
    static let tempoName: @Sendable (TimedChord) -> String = { chord in
        chord.tempo.map { String(Int($0)) } ?? "-"
    }

    @Test(arguments: [
        Row(
            name: "time before the bridge",
            source: "{time: 4/4}\n[G]a [C]b\n\n{time: 3/4}\n{start_of_bridge}\n[D]c\n"
                + "{end_of_bridge}\n",
            expected: ["4/4", "4/4", "3/4"],
            read: meterName,
        ),
        Row(
            name: "tempo mid-song",
            source: "{tempo: 90}\n[G]a\n\n{tempo: 120}\n[C]b\n",
            expected: ["90", "120"],
            read: tempoName,
        ),
        Row(
            name: "between sections applies to the next section",
            source: "{key: G}\n{start_of_verse}\n[G]a\n{end_of_verse}\n{key: D}\n"
                + "{start_of_chorus}\n[D]b\n{end_of_chorus}\n",
            expected: ["G", "D"],
            read: keyName,
        ),
        Row(
            name: "inside a section before a line",
            source: "{key: G}\n{start_of_verse}\n[G]a [C]b\n{key: Bb}\n[Bb]c\n{end_of_verse}\n",
            expected: ["G", "G", "Bb"],
            read: keyName,
        ),
        Row(
            name: "an unparsable second key is skipped",
            source: "{key: G}\n[G]a\n{key: H#}\n[C]b\n",
            expected: ["G", "G"],
            read: keyName,
        ),
        Row(
            name: "a key after an intro is the initial key",
            source: "[C]intro\n\n{key: G}\n[G]verse\n",
            expected: ["G", "G"],
            read: keyName,
        ),
        Row(
            name: "a stub chorus after a change plays in the new key",
            source: "{key: G}\n{start_of_chorus}\n[G]a\n{end_of_chorus}\n{key: A}\n{chorus}\n",
            expected: ["G", "A"],
            read: keyName,
        ),
    ])
    func `directives apply from where they are written`(_ row: Row) {
        #expect(Self.timeline(row.source).chords.map(row.read) == row.expected)
    }

    @Test
    func `capo and a slot override move every key entry`() {
        let source = "{key: G}\n{capo: 2}\n[G]a\n\n{key: A}\n[A]b\n"
        let (document, _) = ChordProParser.parse(source)
        // The song's capo 2 plus a view transpose of 1; a slot's capo 4 with transpose -2.
        for (options, capo, expected) in [
            (DisplayOptions(transpose: 1), 2, ["Bb", "C"]),
            (DisplayOptions(transpose: -2), 4, ["A", "B"]),
        ] {
            let model = RenderModel(document: document, options: options, capo: capo)
            let timeline = SongTimeline.build(
                document: document,
                sections: model.sections,
                units: SongSections.units(of: document),
                timing: ChordTiming(),
                order: nil,
            )
            let concert = timeline.chords.compactMap { chord in
                chord.key.map { $0.transposed(by: model.transform.concertSemitones).name }
            }
            #expect(concert == expected)
        }
    }

    @Test
    func `the Nashville numbers and transposed spelling re-key after the change`() {
        let source = "{key: G}\n[G]a [D]b\n\n{key: Bb}\n[F]c [Dm]d\n"
        let (document, _) = ChordProParser.parse(source)
        func texts(_ options: DisplayOptions) -> [String] {
            RenderModel(document: document, options: options).sections.flatMap(\.items)
                .flatMap { item -> [String] in
                    guard case let .lyrics(line) = item else { return [] }
                    return line.chords.map(\.text)
                }
        }
        #expect(texts(DisplayOptions(nashville: true)) == ["1", "5", "5", "3m"])
        // Up a half step: G's chords spell in Ab, Bb's in B (F#, not Gb).
        #expect(texts(DisplayOptions(transpose: 1)) == ["Ab", "Eb", "F#", "D#m"])
        // The song (header, library) keeps G.
        #expect(RenderModel(document: document, options: DisplayOptions()).header.key == "G")
    }

    @Test
    func `transposing the source spells each chord in its own key`() {
        let source = "{key: G}\n[G]a\n\n{key: Bb}\n[F]b [Dm]c\n"
        let snapshot = SourceSnapshot(text: source)
        let rewrite = TranspositionRewrite.plan(semitones: 1, in: snapshot)
        let text = snapshot.text.applying(rewrite.change.edits)
        #expect(text.contains("[Ab]a"))
        #expect(text.contains("[F#]b [D#m]c"))
        #expect(text.contains("{key: B}"))
    }
}
