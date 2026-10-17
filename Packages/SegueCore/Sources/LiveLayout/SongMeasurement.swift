// Owner: unit B. Measures a song once at a reference size; every auto-fit trial then only
// scales and adds these widths (TextMeasuring widths are linear in the size).

import ChordPro
import Editing
import Foundation

/// The size all measurements are taken at.
let referenceSize = 100.0

/// A run of lyric text between break opportunities (chord positions and word ends).
struct LyricPiece {
    var text: String
    /// Lyric offset of the first character.
    var start: Int
    /// Width at `referenceSize`.
    var width: Double
    /// Width without trailing whitespace.
    var inkWidth: Double
    /// Ends with whitespace (or the line): a row may break after it.
    var endsWord: Bool
}

struct MeasuredChord {
    var text: String
    var offset: Int
    var width: Double
    var kind: ChordKind
}

/// A lyric line split into pieces, chords attached to lyric offsets.
struct MeasuredLine {
    var pieces: [LyricPiece]
    /// In source order; offsets clamped to `0 ... lyricCount`.
    var chords: [MeasuredChord]
    var lyricCount: Int
    var path: BlockPath
    /// The lyric's own ink (nil for a blank lyric): rows make room for glyphs that reach
    /// past the face's capitals or descenders, so they never meet the chord band.
    var ink: InkExtents?
}

/// Plain text broken into words (each keeps its trailing whitespace).
struct MeasuredParagraph {
    var words: [LyricPiece]
    var role: TextRole
}

enum MeasuredItem {
    case lyric(MeasuredLine)
    case comment(MeasuredParagraph, BlockPath)
    case verbatim(text: String, width: Double, path: BlockPath)
    case stanzaBreak(BlockPath)
}

/// One section as auto-fit sees it, after repeat collapsing.
struct MeasuredSection {
    enum Body {
        case full([MeasuredItem])
        case collapsed(line: MeasuredParagraph, differing: [MeasuredItem])
    }

    var id: Int
    /// The block label ("Chorus x2"), for `LayoutBlock.label`.
    var label: String?
    /// The section's name without the repeat count ("Chorus").
    var name: String?
    /// The gutter's first line: `name`, measured as a label.
    var labelText: MeasuredParagraph?
    /// The gutter's second line for a collapsed repeat ("x2").
    var labelDetail: MeasuredParagraph?
    /// "(cont.)", measured as a label detail, for the parts after a split.
    var continuation: MeasuredParagraph?
    var isChorus: Bool
    var tint: SectionTint
    var body: Body
    var cues: [MeasuredCue]
}

struct MeasuredCue {
    var text: String
    var paragraph: MeasuredParagraph
}

/// The whole song, measured.
struct MeasuredSong {
    var notes: [MeasuredParagraph]
    var sections: [MeasuredSection]
    var lineCount: Int
}

/// A piece or word as a range of character (lyric) offsets.
struct PieceBound {
    var start: Int
    var end: Int
    /// For pieces: ends a word. For words: the end of the ink (trailing space excluded).
    var endsWord = true
    var ink = 0
}

/// Measures with one `prefixWidths` call per line or paragraph.
struct Measurer {
    let metrics: any TextMeasuring

    func line(_ line: RenderLine) -> MeasuredLine {
        let count = line.lyricCount
        let chordOffsets = Set(line.chords.map { min(max($0.offset, 0), count) })
        let characters = Self.characters(of: line)
        let spaces = characters.map { Self.isSpace($0) }
        let bounds = Self.pieceBounds(spaces: spaces, chordOffsets: chordOffsets)
        let offsets = Array(Set(bounds.flatMap { [$0.start, $0.end, $0.ink] })).sorted()
        let utf16 = offsets.map { line.utf16Offset(ofLyricOffset: $0) }
        let widths = metrics.prefixWidths(
            of: Self.untabbed(line.lyrics),
            utf16Offsets: utf16,
            role: .lyric,
            size: referenceSize,
        )
        var at: [Int: Double] = [:]
        for (offset, width) in zip(offsets, widths) {
            at[offset] = width
        }
        let pieces = bounds.map { bound in
            LyricPiece(
                text: characters[bound.start ..< bound.end].joined(),
                start: bound.start,
                width: (at[bound.end] ?? 0) - (at[bound.start] ?? 0),
                inkWidth: max(0, (at[bound.ink] ?? 0) - (at[bound.start] ?? 0)),
                endsWord: bound.endsWord,
            )
        }
        let chords = line.chords.map { chord in
            MeasuredChord(
                text: chord.text,
                offset: min(max(chord.offset, 0), count),
                width: metrics.width(of: chord.text, role: .chord, size: referenceSize),
                kind: ChordKind(chord.kind),
            )
        }
        let text = Self.untabbed(line.lyrics)
        let ink = text.allSatisfy(\.isWhitespace) ? nil : metrics.inkExtents(of: text, role: .lyric)
        return MeasuredLine(
            pieces: pieces,
            chords: chords,
            lyricCount: count,
            path: line.path,
            ink: ink,
        )
    }

    /// Piece boundaries in lyric offsets: chord positions and ends of whitespace runs, each
    /// with the end of its ink.
    private static func pieceBounds(spaces: [Bool], chordOffsets: Set<Int>) -> [PieceBound] {
        let count = spaces.count
        var bounds: [PieceBound] = []
        var start = 0
        func close(_ end: Int, endsWord: Bool) {
            var ink = end
            while ink > start, spaces[ink - 1] {
                ink -= 1
            }
            bounds.append(PieceBound(start: start, end: end, endsWord: endsWord, ink: ink))
            start = end
        }
        for offset in 0 ..< count {
            if offset > start, chordOffsets.contains(offset) {
                close(offset, endsWord: false)
            }
            if spaces[offset], offset + 1 == count || !spaces[offset + 1] {
                close(offset + 1, endsWord: true)
            }
        }
        if start < count {
            close(count, endsWord: true)
        }
        return bounds
    }

    /// Splits `text` into words (whitespace kept at each word's end) and measures them.
    func paragraph(_ text: String, role: TextRole) -> MeasuredParagraph {
        let text = Self.untabbed(text)
        let characters = Array(text)
        var utf16 = [0]
        for character in characters {
            utf16.append((utf16.last ?? 0) + character.utf16.count)
        }
        let spaces = characters.map(\.isWhitespace)
        // Word ranges in character indices, plus the end of each word's ink.
        var words: [PieceBound] = []
        var start = 0
        for index in characters.indices {
            let wordEnds = spaces[index] && index + 1 < characters.count && !spaces[index + 1]
            if wordEnds || index + 1 == characters.count {
                var ink = index + 1
                while ink > start, spaces[ink - 1] {
                    ink -= 1
                }
                words.append(PieceBound(start: start, end: index + 1, ink: ink))
                start = index + 1
            }
        }
        let offsets = Array(Set(words.flatMap { [$0.start, $0.end, $0.ink] })).sorted()
        let widths = metrics.prefixWidths(
            of: text,
            utf16Offsets: offsets.map { utf16[$0] },
            role: role,
            size: referenceSize,
        )
        var at: [Int: Double] = [:]
        for (offset, width) in zip(offsets, widths) {
            at[offset] = width
        }
        let pieces = words.map { word in
            let lower = at[word.start] ?? 0
            return LyricPiece(
                text: String(characters[word.start ..< word.end]),
                start: word.start,
                width: (at[word.end] ?? 0) - lower,
                inkWidth: max(0, (at[word.ink] ?? 0) - lower),
                endsWord: true,
            )
        }
        return MeasuredParagraph(words: pieces, role: role)
    }

    /// Splits one over-wide piece into single characters, measured as one line.
    func characters(of piece: LyricPiece, role: TextRole) -> [LyricPiece] {
        let characters = Array(piece.text)
        var offsets = [0]
        for character in characters {
            offsets.append((offsets.last ?? 0) + character.utf16.count)
        }
        let widths = metrics.prefixWidths(
            of: piece.text,
            utf16Offsets: offsets,
            role: role,
            size: referenceSize,
        )
        return characters.indices.map { index in
            let width = widths[index + 1] - widths[index]
            let text = String(characters[index])
            return LyricPiece(
                text: text,
                start: piece.start + index,
                width: width,
                inkWidth: Self.isSpace(Substring(text)) ? 0 : width,
                endsWord: false,
            )
        }
    }

    // MARK: - Helpers

    /// The text of each lyric offset, in one pass over the line.
    private static func characters(of line: RenderLine) -> [Substring] {
        let units = line.lyrics.utf16
        let starts = line.characterStarts
        var index = units.startIndex
        var result: [Substring] = []
        result.reserveCapacity(line.lyricCount)
        for offset in 0 ..< line.lyricCount {
            let next = units.index(index, offsetBy: starts[offset + 1] - starts[offset])
            let character = line.lyrics[index ..< next]
            result.append(character == "\t" ? " " : character)
            index = next
        }
        return result
    }

    /// Tabs drawn alone would jump to tab stops that depend on where a run starts, so runs
    /// show them as spaces (same UTF-16 length, so every offset still holds).
    static func untabbed(_ text: String) -> String {
        text.contains("\t") ? text.replacingOccurrences(of: "\t", with: " ") : text
    }

    /// Tab/grid lines keep their columns: tabs expand to the next multiple of 8.
    static func expandedTabs(_ text: String) -> String {
        guard text.contains("\t") else { return text }
        var result = ""
        for character in text {
            if character == "\t" {
                result += String(repeating: " ", count: 8 - result.count % 8)
            } else {
                result.append(character)
            }
        }
        return result
    }

    static func isSpace(_ text: Substring) -> Bool {
        !text.isEmpty && text.allSatisfy(\.isWhitespace)
    }
}
