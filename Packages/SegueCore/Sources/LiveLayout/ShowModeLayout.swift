// Owner: P8-2. The rows only the show modes use (R149, P8-2 section 6.3): a Chords only
// pass's chord rows and a First line pass's "+ N more lines".

import Editing

extension SectionLayout {
    /// A Chords only line (P8-2 section 6.3): `| C | G |`, the chords bold at chord size,
    /// each run at least `chordRunMinimum` em wide, `chordRowGap` em around each `|`; rows
    /// of `chordRowHeight` x the chord size, wrapped (each row opening with `|`) when wider
    /// than the column.
    func chordRows(_ chords: [MeasuredChord], path: BlockPath) -> [LayoutRow] {
        let size = context.chordSize
        let scale = size / referenceSize
        let gap = style.chordRowGap * size
        let separator = measurer.metrics.width(of: "|", role: .chordSeparator, size: size)
        let height = style.chordRowHeight * size
        let baseline = SizeContext.baseline(
            band: height,
            size: size,
            extents: measurer.metrics.extents(of: .chord),
        )
        func bar(at x: Double) -> PlacedText {
            PlacedText(text: "|", x: x, width: separator, role: .chordSeparator, size: size)
        }
        var rows: [[PlacedText]] = []
        var runs = [bar(at: 0)]
        var x = separator + gap
        for chord in chords {
            let chordWidth = chord.unitWidth * scale
            let slot = max(chordWidth, style.chordRunMinimum * size)
            if x + slot + gap + separator > width, runs.count > 1 {
                rows.append(runs)
                runs = [bar(at: 0)]
                x = separator + gap
            }
            runs += chord.runs(at: x, size: size, scale: scale)
            x += slot + gap
            runs.append(bar(at: x))
            x += separator + gap
        }
        rows.append(runs)
        return rows.map { runs in
            LayoutRow(
                kind: .chordRow,
                y: 0,
                height: height,
                chordBaseline: nil,
                textBaseline: baseline,
                chords: [],
                text: runs,
                source: path,
            )
        }
    }

    /// "+ N more lines (first line only)": medium, `moreLinesScale` x the lyric size, muted,
    /// `moreLinesSpacing` below the first line.
    func moreLines(_ paragraph: MeasuredParagraph) -> LaidUnit {
        let size = context.lyricSize * style.moreLinesScale
        var laid = stack(textRows(paragraph, size: size, kind: .moreLines, path: nil))
        for index in laid.rows.indices {
            laid.rows[index].y += style.moreLinesSpacing
        }
        laid.inkTop = laid.inkTop.map { $0 + style.moreLinesSpacing }
        laid.height += style.moreLinesSpacing
        return laid
    }
}
