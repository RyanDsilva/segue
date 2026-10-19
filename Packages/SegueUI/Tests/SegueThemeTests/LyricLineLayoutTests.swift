import AppKit
import ChordPro
import Editing
@testable import SegueUI
import SwiftUI
import Testing

/// Chords over lyrics in the song sheet (editor preview, song page, Quick Look): a chord
/// inside a word keeps the word whole when the line wraps, stacked chords share one chord
/// band, and a chord only pushes the lyric when it would hit the chord before it.
@MainActor
struct LyricLineLayoutTests {
    /// The first lyric line of `source` (every source here is one lyric line).
    private static func line(_ source: String) -> RenderLine {
        let model = RenderModel(document: ChordProParser.parse(source).0, options: DisplayOptions())
        let lines = model.sections.flatMap(\.items).compactMap { item -> RenderLine? in
            if case let .lyrics(line) = item {
                line
            } else {
                nil
            }
        }
        precondition(!lines.isEmpty, "no lyric line in \(source)")
        return lines[0]
    }

    /// Fixed-width stand-ins: 10 per character, chords 10 per character.
    private static func pieces(_ tokens: [LyricToken]) -> [LyricRowBreaker.Piece] {
        tokens.map {
            LyricRowBreaker.Piece(
                chordWidth: $0.chord.map { CGFloat($0.count) * 10 },
                advance: CGFloat($0.text.count) * 10,
                trailingWhitespace: CGFloat($0.trailingSpaces) * 10,
                hasInk: $0.hasInk,
                endsWord: $0.endsWord,
            )
        }
    }

    private static func rowTexts(_ source: String, width: CGFloat) -> [String] {
        let tokens = LyricToken.tokens(for: line(source))
        return LyricRowBreaker(chordGap: 5).rows(pieces(tokens), width: width).map { row in
            row.placements.map { tokens[$0.index].text }.joined()
        }
    }

    @Test
    func `a chord inside a word never splits the word across rows`() {
        // "wonder[Fmaj7]ful" is one word: it moves to the next row whole.
        let rows = Self.rowTexts("Beau[C]tiful morning, wonder[Fmaj7]ful day", width: 260)
        #expect(rows == ["Beautiful morning, ", "wonderful day"])
        let tokens = LyricToken.tokens(for: Self.line("wonder[Fmaj7]ful day"))
        #expect(tokens.map(\.endsWord) == [false, true, true])
    }

    @Test
    func `a word wider than a row breaks only at its chords`() {
        let rows = Self.rowTexts("[Em7]Ab[A7]cd[Dm7]ef", width: 45)
        #expect(rows == ["Ab", "cd", "ef"])
    }

    @Test
    func `stacked chords share the chord band and line up after the first`() {
        let tokens = LyricToken.tokens(for: Self.line("[C][G/B][Am7][F]Stacked"))
        let rows = LyricRowBreaker(chordGap: 5).rows(Self.pieces(tokens), width: 1000)
        #expect(rows.count == 1)
        let placements = rows[0].placements
        // C 0-10, G/B 15-45, Am7 50-80, F 85-95: each after the last plus the gap.
        #expect(placements.map(\.chordX) == [0, 15, 50, 85])
        // The lyric stays under the first chord, as on stage.
        #expect(placements.map(\.textX) == [0, 0, 0, 0])
        #expect(rows[0].hasChords && rows[0].hasText)
    }

    @Test
    func `a chord overhangs the next word unless another chord follows`() {
        // "[Cmaj7/G]I love [G]you": Cmaj7/G (70) hangs over "love"; G pushes "you" right.
        let tokens = LyricToken.tokens(for: Self.line("[Cmaj7/G]I love [G]you"))
        let row = LyricRowBreaker(chordGap: 5).rows(Self.pieces(tokens), width: 1000)[0]
        #expect(row.placements.map(\.textX) == [0, 20, 75])
        #expect(row.placements.map(\.chordX) == [0, nil, 75])
    }

    @Test
    func `trailing spaces never count when a row fits`() {
        // "one two " is 80 wide with its space, 70 without: it fits a row of 70.
        #expect(Self.rowTexts("one two ", width: 70) == ["one two "])
    }

    @Test
    func `a chord inside a Devanagari conjunct stays on its character`() {
        // The chord splits प and ्: the joined lyric merges them into one Character, so
        // Character indexing would cut every later chord one character early.
        let tokens = LyricToken.tokens(for: Self.line("प[G]्यार [D]है"))
        #expect(tokens.map(\.chord) == [nil, "G", "D"])
        #expect(tokens.map(\.text) == ["प", "्यार ", "है"])
    }

    @Test
    func `stacked chords render on one chord band, as tall as a single chord`() {
        func height(_ source: String) -> CGFloat {
            let view = LyricLineView(line: Self.line(source), style: .preview)
                .frame(width: 600)
            return NSHostingView(rootView: view).fittingSize.height
        }
        let single = height("[C]Stacked chords at the start")
        #expect(abs(height("[C][G/B][Am7][F]Stacked chords at the start") - single) < 0.5)
        #expect(height("Stacked chords at the start") < single - 10)
    }
}
