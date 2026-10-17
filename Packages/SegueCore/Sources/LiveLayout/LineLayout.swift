// Owner: unit B. Places one lyric line's pieces and chords into rows of a given width.

import ChordPro
import Editing

/// Scale factors and bands for one lyric size.
struct SizeContext {
    let style: LayoutStyle
    let lyricSize: Double
    let chordSize: Double
    let lyricExtents: FontExtents
    let chordExtents: FontExtents

    init(style: LayoutStyle, lyricSize: Double, metrics: any TextMeasuring) {
        self.style = style
        self.lyricSize = lyricSize
        chordSize = lyricSize * style.chordRatio
        lyricExtents = metrics.extents(of: .lyric)
        chordExtents = metrics.extents(of: .chord)
    }

    var lyricScale: Double {
        lyricSize / referenceSize
    }

    var chordScale: Double {
        chordSize / referenceSize
    }

    var textBand: Double {
        lyricSize * style.lineHeight
    }

    var chordBand: Double {
        max(style.chordLineHeight, chordExtents.inkTop + chordExtents.descent) * chordSize
    }

    /// Chord baseline from the row's top: descenders end at the chord band's bottom.
    var chordBaseline: Double {
        chordBand - chordExtents.descent * chordSize
    }

    var chordGap: Double {
        chordSize * style.chordSpacing
    }

    /// Baseline from the top of a band of `height` holding glyphs of `size`, centred.
    static func baseline(band height: Double, size: Double, extents: FontExtents) -> Double {
        (height - (extents.ascent + extents.descent) * size) / 2 + extents.ascent * size
    }
}

/// One row being filled: the lyric cursor and the right edge of the last chord.
struct RowDraft {
    var pieces: [(piece: LyricPiece, x: Double)] = []
    var chords: [PlacedText] = []
    var cursor = 0.0
    var chordEnd = -Double.infinity
    var inkRight = 0.0

    var isEmpty: Bool {
        pieces.isEmpty && chords.isEmpty
    }

    /// Visible width: the ink of the text and the chords.
    var width: Double {
        max(inkRight, chordEnd.isFinite ? chordEnd : 0)
    }

    /// Places `chords` (all at the same lyric offset) at the cursor. The first one pushes
    /// the lyric right when it would collide with the previous chord; later ones stack
    /// after it.
    mutating func place(_ chords: [MeasuredChord], context: SizeContext) {
        for (index, chord) in chords.enumerated() {
            let width = chord.width * context.chordScale
            var x = cursor
            if index == 0 {
                if chordEnd.isFinite, cursor < chordEnd + context.chordGap {
                    cursor = chordEnd + context.chordGap
                }
                x = cursor
            } else {
                x = chordEnd + context.chordGap
            }
            self.chords.append(PlacedText(
                text: chord.text,
                x: x,
                width: width,
                role: .chord,
                chordKind: chord.kind,
                size: context.chordSize,
            ))
            chordEnd = x + width
        }
    }

    mutating func append(_ piece: LyricPiece, scale: Double) {
        if piece.inkWidth > 0 {
            inkRight = cursor + piece.inkWidth * scale
        }
        pieces.append((piece, cursor))
        cursor += piece.width * scale
    }
}

/// Breaks a measured lyric line into rows no wider than `width` (where possible): words stay
/// whole, each chord stays above its character, and a wrapped row takes its chords with it.
struct LineBreaker {
    let line: MeasuredLine
    let context: SizeContext
    let width: Double
    let measurer: Measurer

    func rows() -> [RowDraft] {
        let byOffset = Dictionary(grouping: line.chords, by: \.offset)
        var rows: [RowDraft] = []
        var current = RowDraft()
        var word: [LyricPiece] = []
        for piece in line.pieces {
            word.append(piece)
            if piece.endsWord {
                add(word, chords: byOffset, to: &current, rows: &rows)
                word = []
            }
        }
        if !word.isEmpty {
            add(word, chords: byOffset, to: &current, rows: &rows)
        }
        if let trailing = byOffset[line.lyricCount] {
            var trial = current
            trial.place(trailing, context: context)
            if trial.width > width, !current.isEmpty {
                rows.append(current)
                current = RowDraft()
                current.place(trailing, context: context)
            } else {
                current = trial
            }
        }
        if !current.isEmpty || rows.isEmpty {
            rows.append(current)
        }
        return rows
    }

    /// Adds a word; when it does not fit, starts a new row, and when it does not fit an empty
    /// row either, breaks it at its chords and then between characters.
    private func add(
        _ word: [LyricPiece],
        chords: [Int: [MeasuredChord]],
        to current: inout RowDraft,
        rows: inout [RowDraft],
    ) {
        var trial = current
        for piece in word {
            trial.place(chords[piece.start] ?? [], context: context)
            trial.append(piece, scale: context.lyricScale)
        }
        if trial.width <= width {
            current = trial
            return
        }
        if !current.isEmpty {
            rows.append(current)
            current = RowDraft()
            add(word, chords: chords, to: &current, rows: &rows)
            return
        }
        if word.count > 1 {
            for piece in word {
                add([piece], chords: chords, to: &current, rows: &rows)
            }
            return
        }
        // One piece wider than the row: break between characters.
        guard let piece = word.first else { return }
        let characters = measurer.characters(of: piece, role: .lyric)
        guard characters.count > 1 else {
            current = trial
            return
        }
        var first = true
        for character in characters {
            var unit = character
            unit.start = piece.start
            let chordsHere = first ? chords : [:]
            first = false
            addUnbreakable(unit, chords: chordsHere, to: &current, rows: &rows)
        }
    }

    private func addUnbreakable(
        _ piece: LyricPiece,
        chords: [Int: [MeasuredChord]],
        to current: inout RowDraft,
        rows: inout [RowDraft],
    ) {
        var trial = current
        trial.place(chords[piece.start] ?? [], context: context)
        trial.append(piece, scale: context.lyricScale)
        if trial.width > width, !current.isEmpty {
            rows.append(current)
            current = RowDraft()
            addUnbreakable(piece, chords: chords, to: &current, rows: &rows)
        } else {
            current = trial
        }
    }
}

extension RowDraft {
    /// The row as drawn: adjacent pieces merged into runs, trailing whitespace dropped.
    func layoutRow(
        kind: LayoutRow.Kind,
        y: Double,
        context: SizeContext,
        role: TextRole,
        source: BlockPath?,
    ) -> LayoutRow {
        let scale = context.lyricScale
        // (run, advance so far): merged while pieces are contiguous; the width kept is the
        // ink width, so trailing whitespace never counts.
        var merged: [(run: PlacedText, advance: Double)] = []
        for (piece, x) in pieces {
            if let last = merged.last, abs(last.run.x + last.advance - x) < 0.001 {
                var run = last.run
                run.text += piece.text
                if piece.inkWidth > 0 {
                    run.width = last.advance + piece.inkWidth * scale
                }
                merged[merged.count - 1] = (run, last.advance + piece.width * scale)
            } else {
                let run = PlacedText(
                    text: piece.text,
                    x: x,
                    width: piece.inkWidth * scale,
                    role: role,
                    size: context.lyricSize,
                )
                merged.append((run, piece.width * scale))
            }
        }
        let runs = merged.compactMap { Self.trimmed($0.run) }
        let hasText = !runs.isEmpty
        let hasChords = !chords.isEmpty
        let chordBand = hasChords ? context.chordBand : 0
        let chordBaseline = hasChords ? context.chordBaseline : nil
        let textBaseline = hasText || !hasChords
            ? chordBand + SizeContext.baseline(
                band: context.textBand, size: context.lyricSize, extents: context.lyricExtents,
            )
            : chordBaseline ?? 0
        return LayoutRow(
            kind: kind,
            y: y,
            height: chordBand + (hasText || !hasChords ? context.textBand : 0),
            chordBaseline: chordBaseline,
            textBaseline: textBaseline,
            chords: chords,
            text: runs,
            source: source,
        )
    }

    /// Drops trailing whitespace from a run (its width is already the ink width); nil for a
    /// blank run.
    private static func trimmed(_ run: PlacedText) -> PlacedText? {
        var run = run
        while let last = run.text.last, last.isWhitespace {
            run.text.removeLast()
        }
        guard !run.text.isEmpty else { return nil }
        return run
    }
}
