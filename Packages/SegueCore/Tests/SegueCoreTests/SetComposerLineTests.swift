import MusicTheory
import Setlists
import Testing

/// The set composer's line grammar (P8-5 section 5): break, key token at the end, the rest
/// a query typed exactly as the user wrote it.
struct SetComposerLineTests {
    private static func key(_ text: String) -> SongKey? {
        SongKey(parsing: text)
    }

    @Test(arguments: [
        ("kesariya in A", "kesariya", "A", "in A"),
        ("kesariya in a", "kesariya", "A", "in a"),
        ("Kesariyaa (Am)", "Kesariyaa", "Am", "(Am)"),
        ("tum hi ho (D)", "tum hi ho", "D", "(D)"),
        ("tum hi ho key of D", "tum hi ho", "D", "key of D"),
        ("tum hi ho key D", "tum hi ho", "D", "key D"),
        ("tum hi ho key: D", "tum hi ho", "D", "key: D"),
        ("tum hi ho KEY OF d", "tum hi ho", "D", "KEY OF d"),
        ("channa mereya in f#m", "channa mereya", "F#m", "in f#m"),
        ("channa mereya in Bb", "channa mereya", "Bb", "in Bb"),
        ("channa mereya in bb", "channa mereya", "Bb", "in bb"),
        ("channa mereya in C minor", "channa mereya", "Cm", "in C minor"),
        ("pal in Cmin", "pal", "Cm", "in Cmin"),
        ("pal in E♭ major", "pal", "Eb", "in E♭ major"),
        ("pal in F♯m", "pal", "F#m", "in F♯m"),
        ("stuck in a", "stuck", "A", "in a"),
        ("  kesariya in A  ", "kesariya", "A", "in A"),
    ])
    func `a key token at the end splits off`(
        typed: String,
        query: String,
        keyName: String,
        token: String,
    ) throws {
        let expected = try #require(Self.key(keyName))
        #expect(SetComposerLine.parse(typed) == .song(query: query, key: expected, keyToken: token))
    }

    @Test(arguments: [
        // "H" is not a key: the whole line is the query.
        "tum hi ho in H",
        // The query part must be non-empty.
        "in A",
        "(Am)",
        "key of D",
        // Not at the end, or not a key.
        "in A tum hi ho",
        "tum hi ho (Live)",
        "tum hi ho (Acoustic)",
        "tum hi ho in C m",
        "tum hi ho in Cmi",
        "pal in Ab x",
        "--",
        "- -",
        "--- x",
        "--- Encore",
        "!!!",
    ])
    func `everything else is the whole line as the query`(typed: String) {
        let trimmed = typed.trimmingCharacters(in: .whitespaces)
        #expect(SetComposerLine.parse(typed) == .song(query: trimmed, key: nil, keyToken: nil))
    }

    @Test(arguments: [
        "---",
        "----",
        " --- ",
        "\u{2013}-",
        "\u{2014}",
        "\u{2013}\u{2013}",
    ])
    func `three dashes make a break`(typed: String) {
        #expect(SetComposerLine.parse(typed) == .breakRow)
    }

    @Test(arguments: ["", "   ", "\t", "\n"])
    func `blank lines are empty`(typed: String) {
        #expect(SetComposerLine.parse(typed) == .empty)
    }

    @Test
    func `the typed query keeps its spelling`() {
        #expect(SetComposerLine.parse("Kesariyaa  hain") == .song(
            query: "Kesariyaa  hain",
            key: nil,
            keyToken: nil,
        ))
    }
}

/// The " + " medley grammar (P9-3 section 10): each part a song query with its own key; the
/// typed text never rewritten.
struct SetComposerMedleyLineTests {
    @Test
    func `parts split on a spaced plus, each with its own key`() {
        let line = SetComposerLine.parse("kesariya in A + tum hi ho + channa mereya (Am)")
        guard case let .medley(parts) = line else {
            Issue.record("expected a medley, got \(line)")
            return
        }
        #expect(parts.map(\.query) == ["kesariya", "tum hi ho", "channa mereya"])
        #expect(parts.map(\.key) == [SongKey(parsing: "A"), nil, SongKey(parsing: "Am")])
        #expect(parts.map(\.text) == ["kesariya in A", "tum hi ho", "channa mereya (Am)"])
    }

    @Test(arguments: ["C++ Blues", "rock+roll", "a +b", "a+ b"])
    func `a plus without spaces around it stays one song`(typed: String) {
        #expect(SetComposerLine.parse(typed) == .song(query: typed, key: nil, keyToken: nil))
    }

    @Test
    func `a list of one song is just a song, and an empty middle part is kept`() {
        for typed in ["kesariya in A + ", "kesariya in A +"] {
            #expect(SetComposerLine.parse(typed)
                == .song(query: "kesariya", key: SongKey(parsing: "A"), keyToken: "in A"))
        }
        guard case let .medley(parts) = SetComposerLine.parse("kesariya +  + tum hi ho") else {
            Issue.record("expected a medley")
            return
        }
        #expect(parts.map(\.query) == ["kesariya", "", "tum hi ho"])
    }

    /// "kesariya in A + tum hi ho + chan": the joins sit at 13 and 25 (their "+" at 14 and
    /// 26). A caret up to a join's "+" is in the part on its left, after it on its right.
    @Test(arguments: [
        (0, 0), (8, 0), (13, 0), (14, 0), (15, 1), (16, 1), (20, 1),
        (25, 1), (26, 1), (27, 2), (28, 2), (32, 2),
    ])
    func `the caret maps to the part it sits in, joins included`(offset: Int, part: Int) {
        let typed = "kesariya in A + tum hi ho + chan"
        #expect(SetComposerLine.partIndex(atUTF16Offset: offset, in: typed) == part)
    }

    @Test
    func `caret mapping clamps, counts UTF-16, and follows the trimmed and empty parts`() {
        let typed = "kesariya in A + tum hi ho + chan"
        #expect(SetComposerLine.partIndex(atUTF16Offset: -4, in: typed) == 0)
        #expect(SetComposerLine.partIndex(atUTF16Offset: 999, in: typed) == 2)
        // No join: always the one song.
        #expect(SetComposerLine.partIndex(atUTF16Offset: 2, in: "C++ Blues") == 0)
        #expect(SetComposerLine.partIndex(atUTF16Offset: 0, in: "") == 0)
        // Leading spaces are trimmed as parse trims them.
        #expect(SetComposerLine.partIndex(atUTF16Offset: 4, in: "  a + b") == 0)
        #expect(SetComposerLine.partIndex(atUTF16Offset: 5, in: "  a + b") == 1)
        // Typing the join: after the "+" is the next part, still empty.
        #expect(SetComposerLine.partIndex(atUTF16Offset: 11, in: "kesariya + ") == 1)
        #expect(SetComposerLine.partIndex(atUTF16Offset: 10, in: "kesariya +") == 1)
        #expect(SetComposerLine.partIndex(atUTF16Offset: 9, in: "kesariya +") == 0)
        // An empty middle part is a part of its own, as parse keeps it.
        let gap = "a +  + b"
        #expect([2, 3, 5, 6].map { SetComposerLine.partIndex(atUTF16Offset: $0, in: gap) }
            == [0, 1, 1, 2])
        // A character outside the BMP counts two UTF-16 units (NSRange offsets).
        let emoji = "kesariya \u{1F3B5} + tum"
        #expect(SetComposerLine.partIndex(atUTF16Offset: 12, in: emoji) == 0)
        #expect(SetComposerLine.partIndex(atUTF16Offset: 13, in: emoji) == 1)
    }

    @Test
    func `romanized Hindi spellings stay as typed in every part`() {
        guard case let .medley(parts) = SetComposerLine.parse("Kesariyaa + tum hee ho") else {
            Issue.record("expected a medley")
            return
        }
        #expect(parts.map(\.query) == ["Kesariyaa", "tum hee ho"])
    }
}
