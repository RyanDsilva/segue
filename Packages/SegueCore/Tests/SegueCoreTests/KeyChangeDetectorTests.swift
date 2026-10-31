import ChordPro
import Editing
import Library
import MusicTheory
import Testing

/// "Looks like a key change" (P8-7 section 6.2, R167 Q3): the fixtures the spec names.
struct KeyChangeDetectorTests {
    static func suggestions(_ source: String, dismissed: [KeyChangeDismissal] = []) -> [String] {
        let (document, _) = ChordProParser.parse(source)
        let model = RenderModel(document: document, options: DisplayOptions())
        let units = SongSections.units(of: document)
        let timeline = SongTimeline.build(
            document: document,
            sections: model.sections,
            units: units,
            timing: ChordTiming(),
            order: nil,
        )
        return KeyChangeDetector.suggestions(
            timeline: timeline,
            sections: model.sections,
            units: units,
            dismissed: dismissed,
        ).map { "\(units[$0.section].name): \($0.key.name)" }
    }

    static func song(key: String = "G", _ sections: [(String, String)]) -> String {
        "{key: \(key)}\n" + sections.map { kind, chords in
            "{start_of_\(kind)}\n" + chords.split(separator: " ").map { "[\($0)]la " }.joined()
                + "\n{end_of_\(kind)}\n"
        }.joined()
    }

    static let gVerse = ("verse", "G C D G Em C D G")
    static let gChorus = ("chorus", "C G D G C G D G")

    struct Row: Sendable, CustomTestStringConvertible {
        var name: String
        var source: String
        var expected: [String]

        var testDescription: String {
            name
        }
    }

    @Test(arguments: [
        Row(
            name: "a whole-step lift on the last chorus",
            source: song([gVerse, gChorus, ("chorus", "A B C#m D A B C#m D")]),
            expected: ["Chorus 2nd: A"],
        ),
        Row(
            name: "a half-step lift",
            source: song([gVerse, gChorus, ("chorus", "Ab Db Eb Ab Db Eb Ab")]),
            expected: ["Chorus 2nd: Ab"],
        ),
        Row(
            name: "a relative major bridge is no change",
            source: song(key: "Am", [
                ("verse", "Am Dm E Am Am Dm E Am"),
                ("bridge", "C F G C C F G C"),
            ]),
            expected: [],
        ),
        Row(
            name: "three chords are too few",
            source: song([gVerse, ("chorus", "A D E")]),
            expected: [],
        ),
        Row(
            name: "one borrowed bVII is no change",
            source: song([gVerse, ("chorus", "G C F G G C D G")]),
            expected: [],
        ),
        Row(
            name: "a section with its own key written",
            source: song([gVerse]) + "{key: A}\n"
                + song([("chorus", "A B C#m D A B C#m D")]).replacingOccurrences(
                    of: "{key: G}\n",
                    with: "",
                ),
            expected: [],
        ),
        Row(
            name: "only the first section in the new key",
            source: song([
                gVerse,
                ("chorus", "A B C#m D A B C#m D"),
                ("bridge", "A D E A A D E A"),
            ]),
            expected: ["Chorus: A"],
        ),
    ])
    func `key change fixtures`(_ row: Row) {
        #expect(Self.suggestions(row.source) == row.expected)
    }

    @Test
    func `a dismissed suggestion is not shown again`() throws {
        let source = Self.song([Self.gVerse, ("chorus", "A B C#m D A B C#m D")])
        let (document, _) = ChordProParser.parse(source)
        let model = RenderModel(document: document, options: DisplayOptions())
        let units = SongSections.units(of: document)
        let timeline = SongTimeline.build(
            document: document,
            sections: model.sections,
            units: units,
            timing: ChordTiming(),
            order: nil,
        )
        let found = KeyChangeDetector.suggestions(
            timeline: timeline,
            sections: model.sections,
            units: units,
            dismissed: [],
        )
        let suggestion = try #require(found.first)
        #expect(suggestion.from.name == "G")
        #expect(suggestion.insertBefore == model.sections[1].path)
        #expect(Self.suggestions(source, dismissed: [suggestion.dismissal]).isEmpty)
        // Insert writes the key; the chip is then gone because a {key} is written there.
        let snapshot = SourceSnapshot(text: source)
        let path = try #require(suggestion.insertBefore)
        let change = try DocumentEditor.change(
            for: .insertDirective(name: "key", value: suggestion.key.name, before: path),
            in: snapshot,
        )
        #expect(Self.suggestions(source.applying(change.edits)).isEmpty)
    }
}
