import ChordPro
import Editing
import Testing

/// `{key}` and `{time}` value validation (R81) through the real parser and
/// `SourceSnapshot.diagnostics`, including the one-click key fixes.
struct DirectiveValidationTests {
    @Test(arguments: [
        ("Hm", "Bm"),
        ("H", "B"),
        ("hm", "Bm"),
        ("am", "Am"),
        ("G major", "G"),
        ("A minor", "Am"),
        ("Ebmin", "Ebm"),
    ])
    func `a fixable key gets a diagnostic whose fix writes the canonical key`(
        value: String,
        expected: String,
    ) throws {
        let text = "{title: Song}\n{key: \(value)}\n[G]La la\n"
        let diagnostic = try #require(SourceSnapshot(text: text).diagnostics.first { $0.line == 2 })
        #expect(diagnostic.kind == .malformedDirective)
        let fix = try #require(diagnostic.fix)
        #expect(fix.title == "Change to \(expected)")
        let fixed = text.applying(fix.change.edits)
        #expect(fixed == "{title: Song}\n{key: \(expected)}\n[G]La la\n")
        #expect(!SourceSnapshot(text: fixed).diagnostics.contains { $0.line == 2 })
    }

    @Test(arguments: ["G", "F#m", "Bb", "Dbm", "C♯m", "E♭"])
    func `a canonical key has no diagnostic`(value: String) {
        let text = "{key: \(value)}\n[G]La\n"
        #expect(SourceSnapshot(text: text).diagnostics.isEmpty)
    }

    @Test
    func `an unrecognisable key is flagged without a fix`() throws {
        let snapshot = SourceSnapshot(text: "{key: banana}\n")
        let diagnostic = try #require(snapshot.diagnostics.first)
        #expect(diagnostic.message == "Key 'banana' is not a key like G, Bb or F#m")
        #expect(diagnostic.fix == nil)
    }

    @Test
    func `every key change in a song is checked`() {
        let text = "{key: G}\n[G]One\n{key: Hm}\n[Bm]Two\n"
        let lines = SourceSnapshot(text: text).diagnostics.map(\.line)
        #expect(lines == [3])
    }

    @Test(arguments: ["4/4", "3/4", "6/8", "12/8", "7 / 8", "2/2"])
    func `a time signature is accepted`(value: String) {
        #expect(SourceSnapshot(text: "{time: \(value)}\n").diagnostics.isEmpty)
    }

    @Test(arguments: ["four", "4", "4/3", "0/4", "4/4/4", "33/4", "C"])
    func `a bad time signature is a malformed directive`(value: String) throws {
        let diagnostic = try #require(SourceSnapshot(text: "{time: \(value)}\n").diagnostics.first)
        #expect(diagnostic.kind == .malformedDirective)
        #expect(diagnostic.message.hasPrefix("Time '\(value)'"))
    }
}
