import CoreGraphics
import SwiftUI

/// Breaks one lyric line's pieces into rows, the way the stage engine's `LineBreaker` does:
/// a chord sits at the start of its piece and pushes the lyric right only when it would
/// otherwise collide with the chord before it (chords stacked at one offset line up after
/// the first without moving the lyric); the line wraps between words (never between
/// the pieces of one word, so a chord inside a word keeps the word whole), and a word only
/// breaks at its chords when it is wider than a row on its own. Pure, so it is tested with
/// plain widths.
struct LyricRowBreaker {
    struct Piece: Equatable {
        /// Width of the chord drawn above the piece's start; nil without a chord.
        var chordWidth: CGFloat?
        /// Advance of the lyric text, trailing whitespace included.
        var advance: CGFloat
        /// Width of the trailing whitespace inside `advance` (never ink at a row end).
        var trailingWhitespace: CGFloat = 0
        /// The text draws something besides whitespace.
        var hasInk: Bool
        /// The line may wrap after this piece.
        var endsWord: Bool
    }

    struct Placement: Equatable {
        var index: Int
        /// Leading edge of the chord, from the row's leading edge; nil without a chord.
        var chordX: CGFloat?
        /// Leading edge of the lyric text.
        var textX: CGFloat
    }

    struct Row: Equatable {
        var placements: [Placement] = []
        /// Rightmost ink: chords and lyric text, trailing whitespace excluded.
        var width: CGFloat = 0
        var hasChords = false
        var hasText = false
        fileprivate var cursor: CGFloat = 0
        fileprivate var chordEnd: CGFloat?
        fileprivate var stacking = false

        var isEmpty: Bool {
            placements.isEmpty
        }

        fileprivate mutating func add(_ piece: Piece, index: Int, chordGap: CGFloat) {
            var chordX: CGFloat?
            if let chordWidth = piece.chordWidth {
                let clear = chordEnd.map { $0 + chordGap } ?? cursor
                if stacking {
                    // Same lyric offset as the chord before (no text between): stack after
                    // it without moving the lyric, as the stage does.
                    chordX = max(cursor, clear)
                } else {
                    cursor = max(cursor, clear)
                    chordX = cursor
                }
                let x = max(cursor, clear)
                chordEnd = x + chordWidth
                width = max(width, x + chordWidth)
                hasChords = true
            }
            placements.append(Placement(index: index, chordX: chordX, textX: cursor))
            if piece.hasInk {
                width = max(width, cursor + piece.advance - piece.trailingWhitespace)
                hasText = true
            }
            cursor += piece.advance
            // The next chord sits at the same lyric offset when this piece is a chord with
            // no text.
            stacking = piece.chordWidth != nil && piece.advance == 0
        }
    }

    var chordGap: CGFloat

    func rows(_ pieces: [Piece], width maxWidth: CGFloat) -> [Row] {
        var rows: [Row] = []
        var current = Row()
        var word: [Int] = []
        for index in pieces.indices {
            word.append(index)
            if pieces[index].endsWord || index == pieces.count - 1 {
                add(word, of: pieces, width: maxWidth, to: &current, rows: &rows)
                word = []
            }
        }
        if !current.isEmpty {
            rows.append(current)
        }
        return rows
    }

    /// Adds a word to the current row; when it does not fit, starts a new row, and when it
    /// does not fit an empty row either, breaks it between its pieces.
    private func add(
        _ word: [Int],
        of pieces: [Piece],
        width maxWidth: CGFloat,
        to current: inout Row,
        rows: inout [Row],
    ) {
        var trial = current
        for index in word {
            trial.add(pieces[index], index: index, chordGap: chordGap)
        }
        if trial.width <= maxWidth {
            current = trial
            return
        }
        if !current.isEmpty {
            rows.append(current)
            current = Row()
            add(word, of: pieces, width: maxWidth, to: &current, rows: &rows)
            return
        }
        guard word.count > 1 else {
            // One piece wider than the row: it overflows rather than splitting a chord.
            current = trial
            return
        }
        for index in word {
            var next = current
            next.add(pieces[index], index: index, chordGap: chordGap)
            if next.width > maxWidth, !current.isEmpty {
                rows.append(current)
                current = Row()
                current.add(pieces[index], index: index, chordGap: chordGap)
            } else {
                current = next
            }
        }
    }
}

/// Lays out one lyric line from `LyricToken`s. Subviews, in order: for each token its chord
/// `Text` (only when it has a chord) then its lyric `Text`; last, a hidden `Text(verbatim: " ")` in
/// the
/// lyric face that measures the space width and the lyric line height. Every row's chords
/// share one chord band above the lyric, so a chord never drops to the lyric line, and the
/// layout's first text baseline is the first row's lyric baseline.
struct LyricLineLayout: Layout {
    let tokens: [LyricToken]
    /// Minimum space between two chords.
    var chordGap: CGFloat
    /// Space between the chord band and the lyric below it.
    var chordLyricGap: CGFloat
    /// Space between wrapped rows.
    var rowSpacing: CGFloat

    struct Cache {
        var pieces: [LyricRowBreaker.Piece]
        /// Subview index of each token's chord (nil without one) and lyric.
        var chordViews: [Int?]
        var lyricViews: [Int]
        var chordHeight: CGFloat
        var chordBaseline: CGFloat
        var lyricHeight: CGFloat
        var lyricBaseline: CGFloat

        static let empty = Self(
            pieces: [],
            chordViews: [],
            lyricViews: [],
            chordHeight: 0,
            chordBaseline: 0,
            lyricHeight: 0,
            lyricBaseline: 0,
        )
    }

    func makeCache(subviews: Subviews) -> Cache {
        let sizes = subviews.map { $0.sizeThatFits(.unspecified) }
        var chordViews: [Int?] = []
        var lyricViews: [Int] = []
        var next = 0
        for token in tokens {
            if token.chord != nil {
                chordViews.append(next)
                next += 1
            } else {
                chordViews.append(nil)
            }
            lyricViews.append(next)
            next += 1
        }
        // The view builds exactly these subviews plus the probe; anything else lays out
        // nothing rather than reading past the end.
        guard subviews.count == next + 1 else {
            return .empty
        }
        let probe = next
        let probeSize = sizes[probe]
        let space = probeSize.width
        let firstChord = chordViews.compactMap(\.self).first
        let pieces = tokens.indices.map { index in
            let token = tokens[index]
            return LyricRowBreaker.Piece(
                chordWidth: chordViews[index].map { sizes[$0].width },
                advance: sizes[lyricViews[index]].width,
                trailingWhitespace: CGFloat(token.trailingSpaces) * space,
                hasInk: token.hasInk,
                endsWord: token.endsWord,
            )
        }
        return Cache(
            pieces: pieces,
            chordViews: chordViews,
            lyricViews: lyricViews,
            chordHeight: firstChord.map { sizes[$0].height } ?? 0,
            chordBaseline: firstChord.map {
                subviews[$0].dimensions(in: .unspecified)[.firstTextBaseline]
            } ?? 0,
            lyricHeight: probeSize.height,
            lyricBaseline: subviews[probe].dimensions(in: .unspecified)[.firstTextBaseline],
        )
    }

    func updateCache(_ cache: inout Cache, subviews: Subviews) {
        cache = makeCache(subviews: subviews)
    }

    private func rows(_ cache: Cache, width: CGFloat) -> [LyricRowBreaker.Row] {
        LyricRowBreaker(chordGap: chordGap).rows(cache.pieces, width: width)
    }

    /// The chord band (chords plus the gap under them) of a row that has chords.
    private func chordBand(_ cache: Cache) -> CGFloat {
        cache.chordHeight + chordLyricGap
    }

    private func height(of row: LyricRowBreaker.Row, _ cache: Cache) -> CGFloat {
        let chords = row.hasChords ? chordBand(cache) : 0
        // A row of chords alone (an instrumental line) has no lyric line under it.
        let lyric = row.hasText || !row.hasChords ? cache.lyricHeight : 0
        return chords + lyric
    }

    func sizeThatFits(
        proposal: ProposedViewSize,
        subviews _: Subviews,
        cache: inout Cache,
    ) -> CGSize {
        let rows = rows(cache, width: proposal.width ?? .infinity)
        let width = rows.map(\.width).max() ?? 0
        let height = rows.map { height(of: $0, cache) }.reduce(0, +)
            + rowSpacing * CGFloat(max(rows.count - 1, 0))
        return CGSize(width: proposal.width.map { min($0, width) } ?? width, height: height)
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal _: ProposedViewSize,
        subviews: Subviews,
        cache: inout Cache,
    ) {
        var placed = Set<Int>()
        var y = bounds.minY
        for row in rows(cache, width: bounds.width) {
            let lyricTop = y + (row.hasChords ? chordBand(cache) : 0)
            for placement in row.placements {
                if let chordX = placement.chordX, let view = cache.chordViews[placement.index] {
                    place(subviews[view], at: CGPoint(x: bounds.minX + chordX, y: y))
                    placed.insert(view)
                }
                let view = cache.lyricViews[placement.index]
                place(
                    subviews[view],
                    at: CGPoint(x: bounds.minX + placement.textX, y: lyricTop),
                )
                placed.insert(view)
            }
            y += height(of: row, cache) + rowSpacing
        }
        // The hidden probe (and anything not in a row) still needs a place.
        for index in subviews.indices where !placed.contains(index) {
            subviews[index].place(at: bounds.origin, proposal: .zero)
        }
    }

    private func place(_ subview: LayoutSubview, at point: CGPoint) {
        subview.place(at: point, anchor: .topLeading, proposal: .unspecified)
    }

    func explicitAlignment(
        of guide: VerticalAlignment,
        in bounds: CGRect,
        proposal _: ProposedViewSize,
        subviews _: Subviews,
        cache: inout Cache,
    ) -> CGFloat? {
        guard guide == .firstTextBaseline, let row = rows(cache, width: bounds.width).first
        else { return nil }
        if row.hasText || !row.hasChords {
            return bounds.minY + (row.hasChords ? chordBand(cache) : 0) + cache.lyricBaseline
        }
        return bounds.minY + cache.chordBaseline
    }
}
