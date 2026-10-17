import ChordPro
import Editing
import Foundation
import Library
import MusicTheory
import Testing

/// "Apply transposition to source" end to end (phase 1 spec, "Test strategy"): planned on
/// a snapshot, saved through the real `LibraryStore`, re-opened from disk, and checked in
/// the file bytes, `{key}`, the untouched `{capo}`, the flagged `{define}`s and the index.
struct EditingTranspositionTests {
    @Test
    func `apply transposition rewrites chords and key, keeps capo, flags defines`() async throws {
        let lib = try TestLibrary()
        let store = try await lib.openStore()
        let original = try EditingFixtures.load(EditingSongPipelineTests.defines)
        let created = try await store.createSong(source: original)
        #expect(try EditingSongPipelineTests.indexedKey(lib, id: created.id) == "G")

        let snapshot = SourceSnapshot(text: created.source)
        let rewrite = TranspositionRewrite.plan(semitones: 5, in: snapshot)
        #expect(rewrite.change.actionName == "Transpose")
        #expect(rewrite.newKey?.name == "C")
        #expect(rewrite.flaggedDefines == [
            DefineFlag(name: "Gadd9", line: 5, reason: .unused),
            DefineFlag(name: "C", line: 6, reason: .mismatched),
        ])
        let rewritten = created.source.applying(rewrite.change.edits)
        // Only chord tokens and the {key} value change: one edit each, never a line.
        #expect(rewrite.change.edits.count == 14)
        #expect(rewrite.change.edits.allSatisfy { !$0.replacement.contains("\n") })
        _ = try await store.updateSong(id: created.id, source: rewritten)

        let reopened = try await lib.openStore()
        let record = try #require(try await reopened.song(id: created.id))
        let expected = """
        {title: Harbour Lights}
        {artist: The Quiet Harbour}
        {key: C}
        {capo: 2}
        {define: Gadd9 base-fret 1 frets 3 2 0 2 0 3}
        {define: C base-fret 1 frets x 3 2 0 1 0}

        {start_of_verse}
        [C]Harbour lights are [Am]calling, [F]soft against the [G]rain
        [Cadd9]Every ship that [F]leaves us [G]sails back home a[C]gain
        {end_of_verse}

        {start_of_chorus}
        [F]Shine on, [C/E]shine [Dm7]on
        [N.C.]Hold the [G7sus4]line till [C]dawn
        {end_of_chorus}

        """
        #expect(try Array(lib.read(record.relativePath).utf8) == Array(expected.utf8))
        #expect(record.document.metadata.key == "C")
        #expect(record.document.metadata.capo == 2)
        #expect(try EditingSongPipelineTests.indexedKey(lib, id: created.id) == "C")

        // The editor shows the flags as diagnostics too, and transposing back restores the
        // original bytes.
        let after = SourceSnapshot(text: record.source)
        #expect(after.diagnostics.contains { $0.kind == .unusedDefine && $0.line == 5 })
        let back = TranspositionRewrite.plan(semitones: -5, in: after)
        #expect(record.source.applying(back.change.edits) == original)
        // The rewrite has no memory: both names now sit on chords rewritten from other
        // chords, so both are flagged for review again (the documented contract).
        #expect(back.flaggedDefines.map(\.reason) == [.mismatched, .mismatched])
    }

    @Test(arguments: EditingFixtures.wellFormed)
    func `transposing source by any interval and back restores the original`(name: String) throws {
        let original = try EditingFixtures.load(name)
        let snapshot = SourceSnapshot(text: original)
        guard snapshot.document.metadata.key.flatMap(SongKey.init(parsing:)) != nil else { return }
        for semitones in -11 ... 11 {
            let there = TranspositionRewrite.plan(semitones: semitones, in: snapshot)
            let moved = SourceSnapshot(text: original.applying(there.change.edits))
            #expect(moved.document.plainLyrics == snapshot.document.plainLyrics)
            #expect(moved.document.metadata.capo == snapshot.document.metadata.capo)
            let back = TranspositionRewrite.plan(semitones: -semitones, in: moved)
            #expect(
                moved.text.applying(back.change.edits) == original,
                "\(name) by \(semitones) does not round-trip",
            )
        }
        #expect(TranspositionRewrite.plan(semitones: 12, in: snapshot).change.isEmpty)
    }

    @Test
    func `apply transposition without a key adds the inferred key, saved and indexed`()
        async throws
    {
        let lib = try TestLibrary()
        let store = try await lib.openStore()
        let original = try EditingFixtures.load("editing-no-key.cho")
        let created = try await store.createSong(source: original)
        #expect(try EditingSongPipelineTests.indexedKey(lib, id: created.id) == nil)

        let snapshot = SourceSnapshot(text: created.source)
        let rewrite = TranspositionRewrite.plan(semitones: 2, in: snapshot)
        #expect(rewrite.newKey?.name == "D")
        _ = try await store.updateSong(
            id: created.id,
            source: created.source.applying(rewrite.change.edits),
        )

        let record = try #require(try await lib.openStore().song(id: created.id))
        let expected = """
        {title: Unsigned Song}
        {key: D}

        [D]Walking down the [Bm]empty road
        [G]Nothing but the [A]sky
        [D]Every step a [Bm]little lighter
        [G]Singing [A]by and [D]by

        """
        #expect(try Array(lib.read(record.relativePath).utf8) == Array(expected.utf8))
        #expect(record.document.metadata.key == "D")
        #expect(KeyContext(document: record.document).status == .declared)
        #expect(try EditingSongPipelineTests.indexedKey(lib, id: created.id) == "D")

        // No transposition, no rewrite: the inferred key is not written by a no-op.
        #expect(TranspositionRewrite.plan(semitones: 12, in: snapshot).change.isEmpty)
        #expect(TranspositionRewrite.plan(semitones: 0, in: snapshot).newKey == nil)
    }

    @Test
    func `an added key moves the flagged define lines below it`() {
        let source = """
        {title: Defines}
        {define: Gadd9 base-fret 1 frets 3 2 0 2 0 3}

        [G]One [C]two [D]three [G]four

        """
        let rewrite = TranspositionRewrite.plan(semitones: 2, in: SourceSnapshot(text: source))
        let text = source.applying(rewrite.change.edits)
        #expect(text.hasPrefix(
            "{title: Defines}\n{define: Gadd9 base-fret 1 frets 3 2 0 2 0 3}\n{key: A}\n",
        ))
        #expect(rewrite.flaggedDefines == [DefineFlag(name: "Gadd9", line: 2, reason: .unused)])

        let headed = "{define: Gadd9 base-fret 1 frets 3 2 0 2 0 3}\n" + source
        let shifted = TranspositionRewrite.plan(semitones: 2, in: SourceSnapshot(text: headed))
        #expect(headed.applying(shifted.change.edits).contains("{title: Defines}\n{define: Gadd9"))
        #expect(shifted.flaggedDefines.map(\.line) == [1, 3])

        // An unparseable `{key}` is left alone and no second one is added.
        let odd = "{key: ???}\n[G]One [C]two [D]three\n"
        let kept = TranspositionRewrite.plan(semitones: 2, in: SourceSnapshot(text: odd))
        #expect(odd.applying(kept.change.edits) == "{key: ???}\n[A]One [D]two [E]three\n")
        #expect(kept.newKey == nil)
    }
}
