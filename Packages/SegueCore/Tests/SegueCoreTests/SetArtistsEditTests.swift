import ChordPro
import Editing
import Testing

/// `EditOperation.setArtists` (P8-8 section 3.2): one `{artist}` per artist, matched by
/// position, untouched bytes kept, one undo step "Set Artists".
struct SetArtistsEditTests {
    static func set(_ artists: [String], in source: String) throws -> (String, SourceChange) {
        let change = try DocumentEditor.change(
            for: .setArtists(artists),
            in: SourceSnapshot(text: source),
        )
        return (source.applying(change.edits), change)
    }

    static let three = "{title: Song}\n{artist: A}\n{ARTIST:  B }\n{artist: C}\n{key: G}\n[G]La\n"

    @Test
    func `an unchanged list is no edit`() throws {
        let (result, change) = try Self.set(["A", "B", "C"], in: Self.three)
        #expect(change.edits.isEmpty)
        #expect(result == Self.three)
    }

    @Test
    func `a one-artist file is untouched by an edit of its key`() throws {
        let source = "{t:Kalank}\r\n{artist:Arijit Singh}\r\n{key: G}\r\n[G]Ab\r\n"
        let change = try DocumentEditor.change(
            for: .setDirective(name: "key", value: "A"),
            in: SourceSnapshot(text: source),
        )
        let result = source.applying(change.edits)
        #expect(result == source.replacingOccurrences(of: "{key: G}", with: "{key: A}"))
        let (same, none) = try Self.set(["Arijit Singh"], in: source)
        #expect(none.edits.isEmpty)
        #expect(same == source)
    }

    @Test
    func `renaming artist 2 of 3 changes only that line and keeps its spelling`() throws {
        let (result, change) = try Self.set(["A", "Shreya", "C"], in: Self.three)
        let before = Self.three.split(separator: "\n", omittingEmptySubsequences: false)
        let after = result.split(separator: "\n", omittingEmptySubsequences: false)
        #expect(after.count == before.count)
        for index in before.indices where index != 2 {
            #expect(after[index] == before[index])
        }
        #expect(after[2].hasPrefix("{ARTIST:"))
        #expect(after[2].contains("Shreya"))
        #expect(change.actionName == "Set Artists")
        #expect(change.edits.count == 1)
        #expect(ChordProParser.parse(result).0.metadata.artists == ["A", "Shreya", "C"])
    }

    @Test(arguments: [
        // After the last {artist}.
        (
            "{title: S}\n{artist: A}\n{key: G}\n[G]La\n",
            "{title: S}\n{artist: A}\n{artist: B}\n{artist: C}\n{key: G}\n[G]La\n",
        ),
        // After {title} when there is no {artist}.
        (
            "{key: G}\n{title: S}\n{capo: 2}\n[G]La\n",
            "{key: G}\n{title: S}\n{artist: B}\n{artist: C}\n{capo: 2}\n[G]La\n",
        ),
        // After the leading metadata when there is no {title}.
        (
            "{key: G}\n{capo: 2}\n[G]La\n",
            "{key: G}\n{capo: 2}\n{artist: B}\n{artist: C}\n[G]La\n",
        ),
        // At the top when nothing leads.
        ("[G]La\n", "{artist: B}\n{artist: C}\n[G]La\n"),
        // CRLF files keep CRLF; a last line without an ending.
        ("{title: S}\r\n{artist: A}", "{title: S}\r\n{artist: A}\r\n{artist: B}\r\n{artist: C}"),
    ])
    func `added artists land in place`(source: String, expected: String) throws {
        let current = ChordProParser.parse(source).0.metadata.artists
        let (result, _) = try Self.set(current + ["B", "C"], in: source)
        #expect(result == expected)
    }

    @Test
    func `removed artists delete their lines`() throws {
        let (result, _) = try Self.set(["A"], in: Self.three)
        #expect(result == "{title: Song}\n{artist: A}\n{key: G}\n[G]La\n")
        let (none, _) = try Self.set([], in: Self.three)
        #expect(none == "{title: Song}\n{key: G}\n[G]La\n")
        let last = "{title: S}\n{artist: A}\n{artist: B}"
        let (trimmed, _) = try Self.set(["A"], in: last)
        #expect(trimmed == "{title: S}\n{artist: A}")
    }

    @Test
    func `reordering re-spells by position`() throws {
        let (result, _) = try Self.set(["C", "A", "B"], in: Self.three)
        #expect(ChordProParser.parse(result).0.metadata.artists == ["C", "A", "B"])
        #expect(result.hasPrefix("{title: Song}\n{artist: C}\n"))
        #expect(result.hasSuffix("{key: G}\n[G]La\n"))
    }

    @Test
    func `values are cleaned and blanks dropped`() throws {
        let source = "{title: S}\n[G]La\n"
        let (result, _) = try Self.set([" Arijit}\nSingh ", "  ", ""], in: source)
        #expect(result == "{title: S}\n{artist: Arijit Singh}\n[G]La\n")
    }

    @Test
    func `romanized names are written exactly as typed`() throws {
        let source = "{title: Tum Hi Ho}\n[G]La\n"
        let names = ["arijit singh", "Mithoon", "Shreya Goshal"]
        let (result, _) = try Self.set(names, in: source)
        #expect(ChordProParser.parse(result).0.metadata.artists == names)
    }
}
