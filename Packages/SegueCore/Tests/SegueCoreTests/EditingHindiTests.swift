import ChordPro
import Editing
import Foundation
import Library
import MusicTheory
import Testing

/// Romanized Hindi corpus (phase 1 spec, "Test strategy"): Latin-script Hindi lyrics round
/// trip byte-for-byte, and lyric words that look like chord names ("Am", "Ab", "Dm", "Bas")
/// are never parsed, highlighted, transposed or rendered as chords.
struct EditingHindiTests {
    static let fixtures = EditingFixtures.names.filter { $0.contains("hindi") }

    @Test
    func `the corpus has romanized Hindi fixtures`() {
        #expect(Self.fixtures.count >= 3)
    }

    @Test(arguments: fixtures)
    func `romanized Hindi fixtures round trip through the store byte for byte`(
        name: String,
    ) async throws {
        let source = try EditingFixtures.load(name)
        let lib = try TestLibrary()
        let store = try await lib.openStore()
        let created = try await store.createSong(source: source)
        let reopened = try #require(try await lib.openStore().song(id: created.id))
        #expect(Array(reopened.source.utf8) == Array(source.utf8))
        #expect(Array(ChordProSerializer.serialize(reopened.document).utf8) == Array(source.utf8))
    }

    @Test(arguments: fixtures)
    func `only bracketed tokens are chords in every view`(name: String) throws {
        let source = try EditingFixtures.load(name)
        let snapshot = SourceSnapshot(text: source)
        let bracketed = source.matches(of: /\[([^\[\]\n]*)\]/).map { String($0.output.1) }
        #expect(snapshot.chords.map(\.token.original) == bracketed)

        for transpose in [-5, 0, 3] {
            for nashville in [false, true] {
                let model = RenderModel(
                    document: snapshot.document,
                    options: DisplayOptions(transpose: transpose, nashville: nashville),
                )
                let lines = model.sections.flatMap(\.items).compactMap { item -> RenderLine? in
                    if case let .lyrics(line) = item {
                        return line
                    }
                    return nil
                }
                #expect(lines.flatMap(\.chords).map(\.original) == bracketed)
                let plain = Set(snapshot.document.plainLyrics.components(separatedBy: "\n"))
                #expect(lines.allSatisfy { plain.contains($0.lyrics) })
            }
        }

        // Syntax colouring never touches lyric text.
        let highlighted = snapshot.highlights(in: 0 ..< source.utf16.count)
            .filter { [.chord, .noChord, .unknownChord].contains($0.kind) }
            .map { substring(source, $0.range) }
        #expect(highlighted == bracketed.map { "[\($0)]" })
        #expect(!snapshot.diagnostics.contains { $0.kind == .unknownChord })
    }

    @Test
    func `chord lookalike words survive transposition and lyric edits`() throws {
        let source = try EditingFixtures.load("editing-hindi-chord-lookalikes.cho")
        let snapshot = SourceSnapshot(text: source)
        let lyrics = snapshot.document.plainLyrics
        for word in [
            "Ab bas kar",
            "Am ki daali",
            "Dm se dil",
            "Em sa koi",
            "C D E G sab",
            "Bas ek pal",
        ] {
            #expect(lyrics.contains(word))
        }

        let rewrite = TranspositionRewrite.plan(semitones: 3, in: snapshot)
        let moved = SourceSnapshot(text: source.applying(rewrite.change.edits))
        #expect(moved.document.plainLyrics == lyrics)
        #expect(moved.text.contains("[Cm]Ab bas kar, Am ki daali pe [Bb]baithi koyal"))

        // Typing chord-like words into a lyric line in visual mode adds no chord.
        let line = try #require(snapshot.chords.first?.ref.line)
        let before = snapshot.chords.count
        let typed = try DocumentEditor.change(
            for: .editLyrics(line, range: 0 ..< 0, replacement: "Am Dm Bas "),
            in: snapshot,
        )
        let after = snapshot.applying(typed)
        #expect(after.chords.count == before)
        #expect(after.text.contains("Am Dm Bas [Am]Ab bas kar"))
    }

    // MARK: - Chords inside a grapheme cluster (review finding 1)

    /// The visual editor's path: a UTF-16 position in the joined `RenderLine.lyrics` (what
    /// TextKit reports) becomes a lyric offset through the line's own table, and the edit
    /// lands on exactly that character.
    @Test(arguments: [
        // Devanagari conjunct split by a chord, combining acute, ZWJ emoji sequence.
        ("[C]\u{092A}[G]\u{094D}\u{092F}\u{093E}\u{0930} x\n", "\u{0930}"),
        ("[C]e[G]\u{0301}tude x\n", "e"),
        ("[C]\u{1F468}[G]\u{200D}\u{1F469} dil x\n", "l"),
    ])
    func `edits from canvas positions hit the right character`(
        source: String,
        target: String,
    ) throws {
        let snapshot = SourceSnapshot(text: source)
        let model = RenderModel(document: snapshot.document, options: DisplayOptions())
        let line = try #require(model.sections.flatMap(\.items).compactMap { item in
            if case let .lyrics(line) = item {
                return line
            }
            return nil
        }.first)
        #expect(line.characterStarts.count == line.lyricCount + 1)
        #expect(line.utf16Offset(ofLyricOffset: line.lyricCount) == line.lyrics.utf16.count)

        // Delete the last character ("x"), as Backspace at the end of the canvas line does.
        let end = line.lyrics.utf16.count
        let from = line.lyricOffset(atUTF16: end - 1)
        let to = line.lyricOffset(atUTF16: end)
        let deleted = try snapshot.applying(DocumentEditor.change(
            for: .editLyrics(line.path, range: from ..< to, replacement: ""),
            in: snapshot,
        ))
        #expect(deleted.text == String(source.dropLast(2)) + "\n")

        // A chord dropped on the character `target` (found by its UTF-16 position in the
        // joined lyrics) lands right before it in the source.
        let utf16 = try #require(line.lyrics.range(of: target, options: .backwards))
            .lowerBound.utf16Offset(in: line.lyrics)
        let offset = line.lyricOffset(atUTF16: utf16)
        #expect(line.utf16Offset(ofLyricOffset: offset) == utf16)
        let inserted = try snapshot.applying(DocumentEditor.change(
            for: .insertChord("Am", at: LyricPosition(line: line.path, offset: offset)),
            in: snapshot,
        ))
        #expect(inserted.text.contains("[Am]" + target), "\(inserted.text)")
        #expect(inserted.document.plainLyrics == snapshot.document.plainLyrics)
    }
}
