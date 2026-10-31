import ChordPro
import Editing
import Foundation
import Library
import MusicTheory
import Testing

/// The phase 1 build rulings (docs/decisions.md) that changed the units' defaults, driven
/// through the real `LibraryStore` on a temp-dir library: chord inserts replace, Nashville
/// view accepts numbers, and the diagram strip is off by default. ("Apply transposition
/// adds a `{key}`" lives in `EditingTranspositionTests`.)
struct EditingBuildRulingsTests {
    // MARK: - Inserting where a chord sits replaces it

    @Test
    func `inserting a chord on a chord replaces it, saved and re-opened from disk`()
        async throws
    {
        let lib = try TestLibrary()
        let store = try await lib.openStore()
        let source = "{title: Replace}\n{key: G}\n\n[G]Dil ki [C]baat [A][B]hai\n"
        let created = try await store.createSong(source: source)

        var snapshot = SourceSnapshot(text: created.source)
        let line = try #require(snapshot.chords.first?.ref.line)
        // On "baat" (offset 7) where C sits; then on "hai" where an authored stack sits.
        let first = try DocumentEditor.change(
            for: .insertChord("Em", at: LyricPosition(line: line, offset: 7)),
            in: snapshot,
        )
        #expect(first.actionName == "Add Chord")
        snapshot = snapshot.applying(first)
        let second = try DocumentEditor.change(
            for: .insertChord("D", at: LyricPosition(line: line, offset: 12)),
            in: snapshot,
        )
        snapshot = snapshot.applying(second)
        // Where no chord sits, insert still adds one.
        let third = try DocumentEditor.change(
            for: .insertChord("Am", at: LyricPosition(line: line, offset: 4)),
            in: snapshot,
        )
        snapshot = snapshot.applying(third)
        // Only the touched chord text changed (minimal edits).
        #expect(first.edits == [TextEdit(range: 38 ..< 39, replacement: "Em")])
        _ = try await store.updateSong(id: created.id, source: snapshot.text)

        let record = try #require(try await lib.openStore().song(id: created.id))
        #expect(
            try lib.read(record.relativePath)
                == "{title: Replace}\n{key: G}\n\n[G]Dil [Am]ki [Em]baat [D]hai\n",
        )
        #expect(SourceSnapshot(text: record.source).chords.map(\.token.original) == [
            "G", "Am", "Em", "D",
        ])
    }

    // MARK: - Nashville number entry

    @Test
    func `in Nashville view typed numbers resolve against the display key to source letters`()
        async throws
    {
        let lib = try TestLibrary()
        let store = try await lib.openStore()
        let created = try await store.createSong(
            source: "{title: Numbers}\n{key: G}\n{capo: 2}\n\n[G]Dil ki [C]baat [D]hai\n",
        )
        // Shown up 2 (transpose) + 2 (concert) = in B; written in G.
        var options = DisplayOptions(transpose: 2, capoMode: .concert, nashville: true)
        _ = try await store.updateDisplayPrefs(id: created.id, DisplayPrefs(options))
        let record = try #require(try await lib.openStore().song(id: created.id))
        let model = RenderModel(
            document: record.document,
            options: record.sidecar.displayPrefs.displayOptions,
        )
        #expect(model.transform.displayKey?.name == "B")
        let transform = model.transform
        let cases: [(typed: String, source: String)] = [
            ("1", "G"), ("4", "C"), ("5", "D"), ("6m", "Em"), ("2m7", "Am7"),
            ("b7", "F"), ("b3", "Bb"), ("#4", "C#"), ("5/7", "D/F#"), ("3(7)", "B7"),
            ("1(6/9)", "G6/9"), ("5(7)/7", "D7/F#"), ("4maj7", "Cmaj7"), ("  6m ", "Em"),
            // Letters are still accepted, in the display key.
            ("E", "C"), ("F#m", "Dm"),
            // Not a number, not a chord: kept as typed (an unknown chord).
            ("8", "8"), ("57", "57"), ("4(", "4("),
        ]
        for entry in cases {
            #expect(
                transform.sourceChord(fromDisplayed: entry.typed) == entry.source,
                "\(entry.typed)",
            )
        }

        // A number typed in the visual popover lands as source letters on disk, and shows
        // back as the same number.
        var snapshot = SourceSnapshot(text: record.source)
        let line = try #require(snapshot.chords.first?.ref.line)
        let typed = transform.sourceChord(fromDisplayed: "6m")
        snapshot = try snapshot.applying(DocumentEditor.change(
            for: .insertChord(typed, at: LyricPosition(line: line, offset: 4)),
            in: snapshot,
        ))
        _ = try await store.updateSong(id: created.id, source: snapshot.text)
        let saved = try #require(try await lib.openStore().song(id: created.id))
        #expect(saved.source.contains("[G]Dil [Em]ki [C]baat"))
        let shown = RenderModel(document: saved.document, options: options)
        #expect(shown.sections.flatMap(\.items).flatMap { item -> [String] in
            if case let .lyrics(renderLine) = item {
                return renderLine.chords.map(\.text)
            }
            return []
        } == ["1", "6m", "4", "5"])

        // Numbers are only read as numbers in Nashville view.
        options.nashville = false
        let letters = DisplayTransform(options: options, key: transform.key, capo: 2)
        #expect(letters.sourceChord(fromDisplayed: "4") == "4")
    }

    @Test
    func `number entry in a minor key counts from the relative major`() throws {
        let key = try #require(SongKey(parsing: "Am"))
        let expected = ["6m": "Am", "4": "F", "5": "G", "3(7)": "E7", "b7": "Bb", "1": "C"]
        for (number, chord) in expected {
            #expect(Nashville.chord(parsing: number, in: key)?.original == chord, "\(number)")
        }
        // Minor leading tone always sharp; bIII and bVII flat.
        #expect(Nashville.chord(parsing: "#5", in: key)?.original == "G#")
        let dMinor = try #require(SongKey(parsing: "Dm"))
        #expect(Nashville.chord(parsing: "b3", in: dMinor)?.original == "Ab")
    }

    @Test
    func `number entry inverts Nashville rendering for every corpus chord`() throws {
        for name in EditingFixtures.wellFormed {
            let snapshot = try SourceSnapshot(text: EditingFixtures.load(name))
            guard let key = KeyContext(document: snapshot.document).writtenKey else { continue }
            for token in snapshot.chords.map(\.token) {
                guard let chord = token.chord else { continue }
                let number = Nashville.number(for: token, in: key)
                let parsed = try #require(
                    Nashville.chord(parsing: number, in: key)?.chord,
                    Comment(rawValue: "\(name): \(token.original) -> \(number)"),
                )
                #expect(parsed.symbol.root.pitchClass == chord.symbol.root.pitchClass)
                #expect(parsed.symbol.bass?.pitchClass == chord.symbol.bass?.pitchClass)
                #expect(parsed.symbol.suffix == chord.symbol.suffix)
            }
        }
    }

    // MARK: - Diagram strip off by default

    @Test
    func `the diagram strip is off for new songs and for sidecars without the field`()
        async throws
    {
        let lib = try TestLibrary()
        let id = SongID(lib.ids.next())
        try lib.write("{title: Older}\n[G]One [C]two\n", to: "songs/older.cho")
        try lib.write(
            #"{"schemaVersion": 2, "id": "\#(id)", "tags": [],"#
                + #" "displayPrefs": {"transpose": 1, "instrument": "piano"},"#
                + #" "createdAt": "2026-06-01T10:00:00Z", "updatedAt": "2026-06-01T10:00:00Z"}"#,
            to: "songs/older.segue.json",
        )
        let store = try await lib.openStore()
        let older = try #require(try await store.song(id: id))
        #expect(older.sidecar.displayPrefs.showDiagrams == false)
        #expect(older.sidecar.displayPrefs.transpose == 1)
        let model = RenderModel(
            document: older.document,
            options: older.sidecar.displayPrefs.displayOptions,
        )
        #expect(model.diagrams.isEmpty)

        let created = try await store.createSong(source: "{title: New}\n[G]One [C]two\n")
        #expect(created.sidecar.displayPrefs.showDiagrams == false)
        #expect(try lib.read(created.relativePath.replacingOccurrences(
            of: ".cho",
            with: ".segue.json",
        )).contains("\"showDiagrams\" : false"))

        // Turned on, the choice persists and the strip renders.
        var prefs = created.sidecar.displayPrefs
        prefs.showDiagrams = true
        _ = try await store.updateDisplayPrefs(id: created.id, prefs)
        let reopened = try #require(try await lib.openStore().song(id: created.id))
        #expect(reopened.sidecar.displayPrefs.showDiagrams)
        let shown = RenderModel(
            document: reopened.document,
            options: reopened.sidecar.displayPrefs.displayOptions,
        )
        #expect(shown.diagrams.map(\.name) == ["G", "C"])
    }
}

// MARK: - Undo names follow the directive (P8-8: `{duration}` is an ordinary directive)

extension EditingBuildRulingsTests {
    @Test
    func `a directive's undo step is named after it`() throws {
        let snapshot = SourceSnapshot(text: "{title: Harbour}\n{duration: 4:05}\nLine\n")
        let tempo = try DocumentEditor.change(
            for: .setDirective(name: "tempo", value: "90"),
            in: snapshot,
        )
        #expect(tempo.actionName == "Set Tempo")
        #expect(snapshot.text.applying(tempo.edits).contains("{duration: 4:05}\n"))
    }
}
