import ChordPro
import Editing
import Foundation
import Library
import Testing

/// Scripted operation fixtures: sequences of tree operations on corpus songs with golden
/// results, saved through the real store and re-opened from disk byte-for-byte.
struct EditingScriptTests {
    struct Script: CustomTestStringConvertible, Sendable {
        var fixture: String
        var label: String
        /// Builds the operation from the current snapshot (addresses are re-read each step).
        var steps: [@Sendable (SourceSnapshot) throws -> EditOperation]
        /// Every changed line after the script, as `(old, new)`; other lines are identical.
        var changedLines: [(old: String?, new: String?)]

        var testDescription: String {
            "\(fixture): \(label)"
        }
    }

    static let scripts: [Script] = [
        Script(
            fixture: "basic-verse-chorus.cho",
            label: "add, move and delete chords in verse 1",
            steps: [
                { snap in
                    try .insertChord("Am7", at: LyricPosition(line: lyricPath(snap, 0), offset: 9))
                },
                { snap in
                    try .moveChord(
                        ChordRef(line: lyricPath(snap, 0), index: 0),
                        to: LyricPosition(line: lyricPath(snap, 0), offset: 4),
                    )
                },
                { snap in try .deleteChord(ChordRef(line: lyricPath(snap, 1), index: 3)) },
            ],
            changedLines: [
                (
                    "[G]Lanterns on the [Em]water, drifting [C]out to the [D]bay",
                    "Lant[G]erns [Am7]on the [Em]water, drifting [C]out to the [D]bay",
                ),
                (
                    "[G]Every little [Em]light is a [C]word we didn't [D]say",
                    "[G]Every little [Em]light is a [C]word we didn't say",
                ),
            ],
        ),
        Script(
            fixture: "basic-verse-chorus.cho",
            label: "metadata: key, new tempo spelling, section label",
            steps: [
                { _ in .setDirective(name: "key", value: "A") },
                { _ in .setDirective(name: "tempo", value: nil) },
                { snap in
                    let verse = try #require(snap.document.blocks.firstIndex {
                        if case .section = $0 {
                            return true
                        }
                        return false
                    })
                    return .setSectionLabel(BlockPath(block: verse), label: "Opening")
                },
            ],
            changedLines: [
                ("{key: G}", "{key: A}"),
                ("{tempo: 92}", nil),
                ("{start_of_verse: Verse 1}", "{start_of_verse: Opening}"),
            ],
        ),
        Script(
            fixture: "short-aliases.cho",
            label: "title change keeps the short alias",
            steps: [{ _ in .setDirective(name: "title", value: "Renamed") }],
            changedLines: [],
        ),
        Script(
            fixture: "crlf-line-endings.cho",
            label: "insert a new directive with CRLF",
            steps: [
                { _ in .setDirective(name: "capo", value: "3") },
                { snap in
                    try .editLyrics(lyricPath(snap, 0), range: 0 ..< 0, replacement: "Oh ")
                },
            ],
            changedLines: [],
        ),
        Script(
            fixture: "mixed-endings-no-final-newline.cho",
            label: "meta tuning on a file without a final newline",
            steps: [
                { _ in .setMeta(name: "tuning", value: "Drop D") },
                { _ in .setMeta(name: "tuning", value: "DADGAD") },
            ],
            changedLines: [],
        ),
        Script(
            fixture: "hindi-pyaar-ki-raah.cho",
            label: "romanized Hindi lyric edit keeps chords on their syllables",
            steps: [
                { snap in
                    try .editLyrics(lyricPath(snap, 0), range: 0 ..< 6, replacement: "Chalo")
                },
            ],
            changedLines: [
                (
                    "[Am]Chalte chalte [G]is raah pe, [F]tera saath mila [E]hai",
                    "[Am]Chalo chalte [G]is raah pe, [F]tera saath mila [E]hai",
                ),
            ],
        ),
    ]

    @Test(arguments: scripts)
    func `scripted operations save, reload and change only touched text`(
        script: Script,
    ) async throws {
        let original = try EditingFixtures.load(script.fixture)
        var snapshot = SourceSnapshot(text: original)
        for step in script.steps {
            let operation = try step(snapshot)
            let change = try DocumentEditor.change(for: operation, in: snapshot)
            #expect(!change.isEmpty)
            try expectWellFormed(change, in: snapshot)
            snapshot = snapshot.applying(change)
        }
        #expect(
            Array(ChordProSerializer.serialize(snapshot.document).utf8) ==
                Array(snapshot.text.utf8),
        )

        if !script.changedLines.isEmpty {
            let before = lines(original)
            let after = lines(snapshot.text)
            let removed = before.filter { !after.contains($0) }
            let added = after.filter { !before.contains($0) }
            #expect(removed == script.changedLines.compactMap(\.old))
            #expect(added == script.changedLines.compactMap(\.new))
        }

        // Saved through the real store, re-opened from disk: the same bytes.
        let lib = try TestLibrary()
        let store = try await lib.openStore()
        let created = try await store.createSong(source: original)
        _ = try await store.updateSong(id: created.id, source: snapshot.text)
        let reopened = try await lib.openStore()
        let record = try #require(try await reopened.song(id: created.id))
        #expect(Array(record.source.utf8) == Array(snapshot.text.utf8))
        #expect(try Array(lib.read(record.relativePath).utf8) == Array(snapshot.text.utf8))
    }

    @Test
    func `short alias and CRLF scripts produce exact bytes`() throws {
        let aliases = try SourceSnapshot(text: EditingFixtures.load("short-aliases.cho"))
        let title = try DocumentEditor.change(
            for: .setDirective(name: "title", value: "Renamed"),
            in: aliases,
        )
        let titleLine = try #require(aliases.text.components(separatedBy: "\n").first)
        #expect(titleLine.hasPrefix("{t"))
        let renamed = aliases.text.applying(title.edits)
        #expect(renamed.components(separatedBy: "\n").first?.hasPrefix("{t") == true)
        #expect(renamed.components(separatedBy: "\n").first?.contains("Renamed") == true)
        #expect(title.edits.count == 1)

        let crlf = try SourceSnapshot(text: EditingFixtures.load("crlf-line-endings.cho"))
        let capo = try DocumentEditor.change(for: .setDirective(name: "capo", value: "3"), in: crlf)
        let withCapo = crlf.text.applying(capo.edits)
        #expect(withCapo.hasPrefix(
            "{title: Windows Line Endings}\r\n{artist: The CR LF Duo}\r\n{capo: 3}\r\n\r\n",
        ))
        #expect(capo.edits == [TextEdit(range: 56 ..< 56, replacement: "{capo: 3}\r\n")])

        let mixed = try SourceSnapshot(text: EditingFixtures.load(
            "mixed-endings-no-final-newline.cho",
        ))
        let tuning = try DocumentEditor.change(
            for: .setMeta(name: "tuning", value: "Drop D"),
            in: mixed,
        )
        let tuned = SourceSnapshot(text: mixed.text.applying(tuning.edits))
        #expect(tuned.document.metadata.extra["tuning"] == ["Drop D"])
        let removed = try DocumentEditor.change(
            for: .setMeta(name: "tuning", value: nil),
            in: tuned,
        )
        #expect(tuned.text.applying(removed.edits) == mixed.text)
    }

    @Test
    func `directive operations insert, replace and remove whole lines`() throws {
        let source = """
        # header comment
        {title: Defines}
        {key: C}
        {define: G base-fret 1 frets 3 2 0 0 0 3}

        [C]One [G]two
        {define: G base-fret 3 frets 1 3 3 2 1 1}
        """
        let snapshot = SourceSnapshot(text: source)

        let tempo = try DocumentEditor.change(
            for: .setDirective(name: "tempo", value: "120"),
            in: snapshot,
        )
        #expect(snapshot.text.applying(tempo.edits) == """
        # header comment
        {title: Defines}
        {key: C}
        {define: G base-fret 1 frets 3 2 0 0 0 3}
        {tempo: 120}

        [C]One [G]two
        {define: G base-fret 3 frets 1 3 3 2 1 1}
        """)

        let noop = try DocumentEditor.change(
            for: .setDirective(name: "capo", value: nil),
            in: snapshot,
        )
        #expect(noop.isEmpty)

        let removeKey = try DocumentEditor.change(
            for: .setDirective(name: "key", value: nil),
            in: snapshot,
        )
        #expect(!snapshot.text.applying(removeKey.edits).contains("{key"))

        // Last line without a newline: removal takes the previous line ending.
        let removeDefines = try DocumentEditor.change(for: .removeDefine(name: "G"), in: snapshot)
        #expect(snapshot.text.applying(removeDefines.edits) == """
        # header comment
        {title: Defines}
        {key: C}

        [C]One [G]two
        """)

        let noTitle = SourceSnapshot(text: "[C]Just a line\n")
        let title = try DocumentEditor.change(
            for: .setDirective(name: "title", value: "New"),
            in: noTitle,
        )
        #expect(noTitle.text.applying(title.edits) == "{title: New}\n[C]Just a line\n")
    }

    @Test
    func `section labels keep the directive spelling`() throws {
        let snapshot = SourceSnapshot(text: "{soc}\n[C]La la\n{eoc}\n{sov:Verse 1}\nHum\n{eov}\n")
        let chorus = try DocumentEditor.change(
            for: .setSectionLabel(BlockPath(block: 0), label: "Hook"),
            in: snapshot,
        )
        let verse = try DocumentEditor.change(
            for: .setSectionLabel(BlockPath(block: 1), label: nil),
            in: snapshot,
        )
        #expect(snapshot.text.applying(chorus.edits).hasPrefix("{soc: Hook}\n"))
        #expect(snapshot.text.applying(verse.edits).contains("\n{sov}\nHum\n"))
    }
}
