// Owner: unit B. Lays out each measured section at one lyric size and column width.

import ChordPro
import Editing
import Library

/// One item's rows (lyric line, comment, verbatim line or stanza break). `rows[].y` is from
/// the unit's top.
struct LaidUnit {
    var rows: [LayoutRow]
    var height: Double
    var isBreak: Bool
    /// The top of the unit's first ink (chord capitals, else its text), from the unit's top;
    /// nil for a blank unit. Gutter labels top-align to the first ink of their block.
    var inkTop: Double?
    /// A lyric line that needed more than one row.
    var wrapped = false
    /// A fill's tab: never split from the line above it.
    var keepsWithPrevious = false
}

/// A section laid out at one size, ready to be packed into columns (whole or split between
/// units).
struct LaidSection {
    /// The shown pass's index; -1 for the notes.
    var id: Int
    /// The part (`RenderModel.sections` index); -1 for the notes.
    var source: Int
    var position: Int?
    var label: String?
    /// The gutter name, for "(cont.)" labels.
    var name: String?
    var isChorus: Bool
    var tint: SectionTint
    var kind: SectionKind?
    var mode: PassMode
    var passName: PassName?
    var isNotes: Bool
    /// The gutter of the first part ("Chorus" / "2 of 3" / "CHORDS") and of later parts of a
    /// split section ("Chorus" / "(cont.)").
    var gutter: LabelLayout
    var continuationGutter: LabelLayout
    /// Cues (y from the head's top) above the units.
    var cues: [PlacedCue]
    var headHeight: Double
    /// The first ink in the head (a cue's box), from the head's top.
    var headInkTop: Double?
    var units: [LaidUnit]
    /// A verbatim line had to be broken to fit the column.
    var brokeVerbatim: Bool
    /// A lyric line wraps.
    var wrapped: Bool
}

/// A gutter label, top-aligned: line baselines measured from the first line's ink top (0),
/// and how far the last line reaches below it.
struct LabelLayout {
    var lines: [PlacedLine]
    var height: Double

    static let empty = Self(lines: [], height: 0)
}

/// A section's gutter on its first part and on its continuations.
struct SectionGutters {
    var first: LabelLayout
    var continuation: LabelLayout
}

/// Lays out sections for one (lyric size, column width).
struct SectionLayout {
    let context: SizeContext
    /// Width of the lyric area of a column (gutter excluded).
    let width: Double
    /// Gutter labels per section index (`gutters(for:gutter:style:measurer:)`): they do not
    /// depend on the lyric size, so they are laid out once per plan.
    let gutters: [Int: SectionGutters]
    let measurer: Measurer

    var style: LayoutStyle {
        context.style
    }

    func lay(_ section: MeasuredSection) -> LaidSection {
        var cues: [PlacedCue] = []
        var head = 0.0
        let headInkTop: Double? = section.cues.isEmpty ? nil : 0
        for cue in section.cues {
            let placed = callout(cue, y: head)
            cues.append(placed)
            head += placed.height + style.calloutSpacing
        }
        var broke = false
        let units = section.items.map { unit($0, broke: &broke) }
        return LaidSection(
            id: section.id,
            source: section.source,
            position: section.position,
            label: section.label,
            name: section.name,
            isChorus: section.isChorus,
            tint: section.tint,
            kind: section.kind,
            mode: section.mode,
            passName: section.passName,
            isNotes: false,
            gutter: gutters[section.id]?.first ?? .empty,
            continuationGutter: gutters[section.id]?.continuation ?? .empty,
            cues: cues,
            headHeight: head,
            headInkTop: headInkTop,
            units: units,
            brokeVerbatim: broke,
            wrapped: units.contains(where: \.wrapped),
        )
    }

    /// The notes block: each paragraph wrapped at the fixed note size.
    func notes(_ paragraphs: [MeasuredParagraph]) -> LaidSection {
        let size = style.noteSize
        let band = size * style.smallLineHeight
        let units = paragraphs.enumerated().map { index, paragraph in
            var rows: [LayoutRow] = []
            var y = 0.0
            for line in wrap(paragraph, size: size, width: width) {
                rows.append(LayoutRow(
                    kind: .note,
                    y: y,
                    height: band,
                    chordBaseline: nil,
                    textBaseline: SizeContext.baseline(
                        band: band, size: size, extents: context.lyricExtents,
                    ),
                    chords: [],
                    text: [line],
                    source: nil,
                ))
                y += band
            }
            let spacing = index + 1 < paragraphs.count ? style.calloutSpacing : 0
            return LaidUnit(rows: rows, height: y + spacing, isBreak: false)
        }
        return LaidSection(
            id: -1,
            source: -1,
            position: nil,
            label: nil,
            name: nil,
            isChorus: false,
            tint: .other,
            kind: nil,
            mode: .full,
            passName: nil,
            isNotes: true,
            gutter: .empty,
            continuationGutter: .empty,
            cues: [],
            headHeight: 0,
            headInkTop: nil,
            units: units,
            brokeVerbatim: false,
            wrapped: false,
        )
    }

    // MARK: - Items

    private func unit(_ item: MeasuredItem, broke: inout Bool) -> LaidUnit {
        switch item {
        case let .lyric(line):
            let drafts = LineBreaker(line: line, context: context, width: width, measurer: measurer)
                .rows()
            var laid = stack(drafts.map { draft in
                draft.layoutRow(
                    kind: .lyric,
                    y: 0,
                    context: context,
                    role: .lyric,
                    source: line.path,
                    ink: line.ink,
                    metrics: measurer.metrics,
                )
            })
            laid.wrapped = drafts.count > 1
            return laid
        case let .comment(paragraph, path):
            let size = context.lyricSize * style.commentScale
            return stack(textRows(paragraph, size: size, kind: .comment, path: path))
        case let .verbatim(text, measured, path):
            return verbatim(text, measured: measured, path: path, broke: &broke)
        case let .stanzaBreak(path):
            let height = context.textBand * style.stanzaBreakScale
            let row = LayoutRow(
                kind: .stanzaBreak,
                y: 0,
                height: height,
                chordBaseline: nil,
                textBaseline: height,
                chords: [],
                text: [],
                source: path,
            )
            return LaidUnit(rows: [row], height: height, isBreak: true, inkTop: nil)
        case let .chordRow(chords, path):
            return stack(chordRows(chords, path: path))
        case let .moreLines(paragraph):
            return moreLines(paragraph)
        case let .fillTab(block, height):
            return fillTab(block, baseHeight: height)
        }
    }

    /// A fill's mini tab (P8-7 14.2): full width, its glyphs at the chord detail size (a
    /// walk-up run's), a quarter of that size clear above and below.
    private func fillTab(_ block: FillTabBlock, baseHeight: Double) -> LaidUnit {
        let size = context.chordSize * ChordUnit.detailScale
        let inset = size * 0.25
        let height = baseHeight * size / PlacedFillTab.baseSize
        let row = LayoutRow(
            kind: .fillTab,
            y: 0,
            height: height + 2 * inset,
            chordBaseline: nil,
            textBaseline: height + inset,
            chords: [],
            text: [],
            source: nil,
            fillTab: PlacedFillTab(block: block, size: size, inset: inset, height: height),
        )
        var unit = LaidUnit(rows: [row], height: row.height, isBreak: false, inkTop: nil)
        unit.keepsWithPrevious = true
        return unit
    }

    /// A tab/grid line at the verbatim size; `broke` when it is wider than the column.
    private func verbatim(
        _ text: String,
        measured: Double,
        path: BlockPath,
        broke: inout Bool,
    ) -> LaidUnit {
        let size = context.lyricSize * style.verbatimScale
        let paragraph = MeasuredParagraph(
            words: [LyricPiece(
                text: text, start: 0, width: measured, inkWidth: measured, endsWord: true,
            )],
            role: .verbatim,
        )
        if measured * size / referenceSize > width {
            broke = true
        }
        return stack(textRows(paragraph, size: size, kind: .verbatim, path: path))
    }

    func textRows(
        _ paragraph: MeasuredParagraph,
        size: Double,
        kind: LayoutRow.Kind,
        path: BlockPath?,
    ) -> [LayoutRow] {
        let band = size * style.lineHeight
        let extents = measurer.metrics.extents(of: paragraph.role)
        let lines = wrap(paragraph, size: size, width: width)
        // A blank verbatim line still takes a row.
        return (lines.isEmpty ? [nil] : lines.map(Optional.some)).map { line in
            LayoutRow(
                kind: kind,
                y: 0,
                height: band,
                chordBaseline: nil,
                textBaseline: SizeContext.baseline(band: band, size: size, extents: extents),
                chords: [],
                text: line.map { [$0] } ?? [],
                source: path,
            )
        }
    }

    func stack(_ rows: [LayoutRow]) -> LaidUnit {
        var y = 0.0
        let placed = rows.map { row in
            var row = row
            row.y = y
            y += row.height
            return row
        }
        let inkTop = placed.lazy.compactMap(inkTop(of:)).first
        return LaidUnit(rows: placed, height: y, isBreak: false, inkTop: inkTop)
    }

    /// The top of a row's first ink (its chords, else its text), from the unit's top.
    private func inkTop(of row: LayoutRow) -> Double? {
        if let baseline = row.chordBaseline, !row.chords.isEmpty {
            return row.y + baseline - context.chordExtents.inkTop * context.chordSize
        }
        guard let run = row.text.first else { return nil }
        let extents = measurer.metrics.extents(of: run.role)
        let ink = measurer.metrics.inkExtents(of: run.text, role: run.role)
        return row.y + row.textBaseline - max(extents.inkTop, ink.top) * run.size
    }

    // MARK: - Labels and cues

    private func callout(_ cue: MeasuredCue, y: Double) -> PlacedCue {
        let size = style.cueSize
        let padding = style.cuePadding
        let band = size * style.smallLineHeight
        let extents = measurer.metrics.extents(of: .cue)
        let baseline = SizeContext.baseline(band: band, size: size, extents: extents)
        let lines = wrap(cue.paragraph, size: size, width: max(1, width - 2 * padding.width))
        let placed = lines.enumerated().map { index, text in
            var text = text
            text.x += padding.width
            return PlacedLine(
                text: text,
                baseline: padding.height + Double(index) * band + baseline,
            )
        }
        let inner = lines.map { $0.x + $0.width }.max() ?? 0
        return PlacedCue(
            text: cue.text,
            y: y,
            height: Double(lines.count) * band + 2 * padding.height,
            x: 0,
            width: inner + 2 * padding.width,
            lines: placed,
        )
    }

    // MARK: - Wrapping plain text

    /// Greedy word wrap; a word wider than `width` is broken between characters. Each line is
    /// one run starting at x 0, trailing whitespace dropped.
    func wrap(_ paragraph: MeasuredParagraph, size: Double, width: Double) -> [PlacedText] {
        Self.wrap(paragraph, size: size, width: width, measurer: measurer)
    }

    static func wrap(
        _ paragraph: MeasuredParagraph,
        size: Double,
        width: Double,
        measurer: Measurer,
    ) -> [PlacedText] {
        let scale = size / referenceSize
        var lines: [[LyricPiece]] = []
        var current: [LyricPiece] = []
        var advance = 0.0
        func push(_ piece: LyricPiece) {
            if !current.isEmpty, advance + piece.inkWidth * scale > width {
                lines.append(current)
                current = []
                advance = 0
            }
            current.append(piece)
            advance += piece.width * scale
        }
        for word in paragraph.words {
            if word.inkWidth * scale > width {
                measurer.characters(of: word, role: paragraph.role).forEach(push)
            } else {
                push(word)
            }
        }
        if !current.isEmpty {
            lines.append(current)
        }
        return lines.compactMap { pieces in
            Self.run(pieces, scale: scale, size: size, role: paragraph.role)
        }
    }

    private static func run(
        _ pieces: [LyricPiece],
        scale: Double,
        size: Double,
        role: TextRole,
    ) -> PlacedText? {
        var text = ""
        var advance = 0.0
        var ink = 0.0
        for piece in pieces {
            text += piece.text
            if piece.inkWidth > 0 {
                ink = advance + piece.inkWidth * scale
            }
            advance += piece.width * scale
        }
        while let last = text.last, last.isWhitespace {
            text.removeLast()
        }
        guard !text.isEmpty else { return nil }
        return PlacedText(text: text, x: 0, width: ink, role: role, size: size)
    }
}
