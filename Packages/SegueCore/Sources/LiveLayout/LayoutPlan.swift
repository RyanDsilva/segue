// Phase 2 frozen interface (docs/phases/2-interfaces.md). Owner: unit B.
//
// The plan is fully positioned: the stage view draws every run at the x/y given here, with
// the face `TextRole` names, at the plan's sizes. It never re-flows text itself, so what is
// drawn is exactly what auto-fit measured.

import ChordPro
import Diagrams
import Editing
import Foundation
import Library

/// How the plan relates to the viewport.
public enum LayoutFit: Sendable, Hashable {
    /// Everything is visible at `lyricSize` (>= the minimum).
    case fits
    /// Nothing fits at the minimum: laid out at the minimum in 1-2 columns and scrolled.
    case scrollsAtMinimum
    /// The zoom pushed the content past the viewport: scrolled.
    case scrollsZoomed
}

/// The background tint family of a section (low-luminance tints by type; colours in UI).
public enum SectionTint: Sendable, Hashable {
    case verse
    case chorus
    case bridge
    case tab
    case other

    public init(_ kind: SectionKind?) {
        switch kind {
        case .verse: self = .verse
        case .chorus: self = .chorus
        case .bridge: self = .bridge
        case .tab: self = .tab
        case .custom, nil: self = .other
        }
    }
}

/// `RenderChord.Kind`, hashable.
public enum ChordKind: Sendable, Hashable {
    case chord
    case noChord
    case unknown

    public init(_ kind: RenderChord.Kind) {
        switch kind {
        case .chord: self = .chord
        case .noChord: self = .noChord
        case .unknown: self = .unknown
        }
    }
}

/// A run of text at a position. `x` is from the column's lyric origin (after the gutter);
/// rows give `y`. Gutter label lines are from the column's left edge instead, and cue lines
/// from the callout's left edge.
public struct PlacedText: Sendable, Hashable {
    public var text: String
    public var x: Double
    /// Advance width as measured (`StageTextMetrics`); the run is drawn on one line, never
    /// wrapped by the view.
    public var width: Double
    public var role: TextRole
    /// Set for chords: unknown chords are drawn flagged.
    public var chordKind: ChordKind?
    /// Point size to draw at: `StageTypography.font(role, size: size)`.
    public var size: Double
    /// A chord run's token as written and the walk-up drawn after its unit: the stage mini
    /// neck shows the chord's tones and the walk-up's path from them (R166).
    public var written: String?
    public var walkUp: ApproachRun?
    /// The saved fill's notes over this chord (P8-7 section 14): on the chord run for the
    /// neck's fill path, and on the `.approach` run that draws them (as a pick, ink at 70%).
    public var fill: FillRun?

    public init(
        text: String,
        x: Double,
        width: Double,
        role: TextRole,
        chordKind: ChordKind? = nil,
        size: Double = 0,
        written: String? = nil,
        walkUp: ApproachRun? = nil,
        fill: FillRun? = nil,
    ) {
        self.text = text
        self.x = x
        self.width = width
        self.role = role
        self.chordKind = chordKind
        self.size = size
        self.written = written
        self.walkUp = walkUp
        self.fill = fill
    }
}

/// A saved fill's mini tab placed in a row (P8-7 section 14.2): `TabLayout` at the row's full
/// width, in a face of `size` points (its metrics are for 10 pt, so they scale by size / 10).
public struct PlacedFillTab: Sendable, Hashable {
    public var block: FillTabBlock
    /// The point size of the tab's glyphs: the chord detail size (a walk-up run's).
    public var size: Double
    /// The tab's top, from the row's top.
    public var inset: Double
    /// The tab's own height (the row adds `inset` above and below).
    public var height: Double

    public init(block: FillTabBlock, size: Double, inset: Double, height: Double) {
        self.block = block
        self.size = size
        self.inset = inset
        self.height = height
    }

    /// `TabLayout.Metrics` at this size.
    public var metrics: TabLayout.Metrics {
        Self.metrics(scale: size / Self.baseSize)
    }

    /// The face size `TabLayout.Metrics()` suits.
    public static let baseSize = 10.0

    /// The default metrics scaled by `scale`.
    public static func metrics(scale: Double) -> TabLayout.Metrics {
        let base = TabLayout.Metrics()
        return TabLayout.Metrics(
            lineGap: base.lineGap * scale,
            chordRow: base.chordRow * scale,
            markRow: base.markRow * scale,
            rulerRow: base.rulerRow * scale,
            tickLength: base.tickLength * scale,
            glyphHeight: base.glyphHeight * scale,
            labelGap: base.labelGap * scale,
            onsetInset: base.onsetInset * scale,
            glyphGap: base.glyphGap * scale,
            linePad: base.linePad * scale,
        )
    }

    /// A tab's height at `TabLayout.Metrics()` for `tuning` (it does not depend on the notes
    /// or the width).
    public static func baseHeight(for tuning: Tuning) -> Double {
        TabLayout.layout(
            notes: [],
            chords: [],
            ticks: 0 ..< 1,
            pulses: [],
            bars: [],
            tuning: tuning,
            width: 0,
        ) { _ in 0 }.height
    }
}

/// A single line of text with its baseline: gutter label lines and cue callout lines.
public struct PlacedLine: Sendable, Hashable {
    public var text: PlacedText
    /// Baseline, from the top of the containing block (labels) or callout (cues).
    public var baseline: Double

    public init(text: PlacedText, baseline: Double) {
        self.text = text
        self.baseline = baseline
    }
}

/// One visual row. A lyric line wider than the column wraps into several rows; a row with
/// chords has a chord band above its text band.
public struct LayoutRow: Sendable, Hashable {
    public enum Kind: Sendable, Hashable {
        case lyric
        case comment
        case verbatim
        /// Blank stanza break: no runs, height only.
        case stanzaBreak
        case note
        /// A Chords only pass's line (P8-2): the line's chords between `|` separators, all in
        /// `text` (roles `.chord` and `.chordSeparator`), no lyrics.
        case chordRow
        /// A First line pass's "+ N more lines (first line only)" (P8-2).
        case moreLines
        /// A saved fill's mini tab (P8-7 section 14.2): no runs, `fillTab` set.
        case fillTab
    }

    public var kind: Kind
    /// Top of the row, from the block's top.
    public var y: Double
    public var height: Double
    /// Baseline of the chord band, from the row's top (nil when the row has no chords).
    public var chordBaseline: Double?
    /// Baseline of the text band, from the row's top.
    public var textBaseline: Double
    public var chords: [PlacedText]
    public var text: [PlacedText]
    /// The source line, for section highlighting and tests.
    public var source: BlockPath?
    /// The mini tab of a `.fillTab` row.
    public var fillTab: PlacedFillTab?

    public init(
        kind: Kind,
        y: Double,
        height: Double,
        chordBaseline: Double?,
        textBaseline: Double,
        chords: [PlacedText],
        text: [PlacedText],
        source: BlockPath?,
        fillTab: PlacedFillTab? = nil,
    ) {
        self.kind = kind
        self.y = y
        self.height = height
        self.chordBaseline = chordBaseline
        self.textBaseline = textBaseline
        self.chords = chords
        self.text = text
        self.source = source
        self.fillTab = fillTab
    }
}

/// A cue callout at a section's edge: a box at the top of the section's lyric area, above
/// its first line, wrapped to the column.
public struct PlacedCue: Sendable, Hashable {
    public var text: String
    /// From the block's top.
    public var y: Double
    public var height: Double
    /// Left edge of the callout box, from the column's lyric origin.
    public var x: Double
    /// Width of the callout box (padding included).
    public var width: Double
    /// The wrapped text: `x` from the box's left edge, baselines from the box's top.
    public var lines: [PlacedLine]

    public init(
        text: String,
        y: Double,
        height: Double,
        x: Double = 0,
        width: Double = 0,
        lines: [PlacedLine] = [],
    ) {
        self.text = text
        self.y = y
        self.height = height
        self.x = x
        self.width = width
        self.lines = lines
    }
}

/// One section (or the notes block) in a column.
public struct LayoutBlock: Sendable, Hashable, Identifiable {
    public enum Content: Sendable, Hashable {
        /// The pass, laid out in its show mode.
        case rows([LayoutRow])
        /// Song and item notes above the first section.
        case notes([LayoutRow])
    }

    /// The shown pass's index (0-based among shown passes, unique even when a part plays
    /// twice); -1 for the notes block. Not a section index: see `source`.
    public var id: Int
    /// The part: index into `RenderModel.sections`; -1 for the notes block.
    public var source: Int
    /// Index into `LayoutPlan.passes`; nil for the notes block.
    public var pass: Int?
    /// Gutter label ("Chorus", "Chorus (cont.)" on a split section's later parts); nil for
    /// none.
    public var label: String?
    /// Chorus labels use `text`, others `muted` (brand.md).
    public var isChorusLabel: Bool
    public var tint: SectionTint
    /// Top of the block in the column.
    public var y: Double
    public var height: Double
    public var content: Content
    public var cues: [PlacedCue]
    /// The gutter lines, top-aligned with the block's first ink: the name (bold, at least
    /// `LayoutStyle.minLabelSize`, wrapped only when the widest gutter cannot hold it), then
    /// on a first part the pass badge ("2 of 3", `.passBadge`, boxed) and the mode tag
    /// ("CHORDS", `.modeTag`), or on a continuation "(cont.)" (`.labelDetail`). `x` from
    /// the column's left edge, baselines from the block's top. Draw these rather than
    /// `label`.
    public var labelLines: [PlacedLine]
    /// 0 for a section's first (or only) part; 1, 2, ... for the continuation of a section
    /// that had to be split across columns (labelled "(cont.)", no cues; same `id`).
    public var part: Int
    /// The medley member this block belongs to (P9-3); 0 for a song.
    public var segment = 0
    /// The member header at the block's head (a segment's first pass, first part only),
    /// placed from `memberHeaderTop`; nil otherwise.
    public var memberHeader: PlacedMemberHeader?
    /// Where the header's top is from the block's top (the block inset).
    public var memberHeaderTop = 0.0

    public init(
        id: Int,
        source: Int? = nil,
        pass: Int? = nil,
        label: String?,
        isChorusLabel: Bool,
        tint: SectionTint,
        y: Double,
        height: Double,
        content: Content,
        cues: [PlacedCue],
        labelLines: [PlacedLine] = [],
        part: Int = 0,
    ) {
        self.id = id
        self.source = source ?? id
        self.pass = pass
        self.label = label
        self.isChorusLabel = isChorusLabel
        self.tint = tint
        self.y = y
        self.height = height
        self.content = content
        self.cues = cues
        self.labelLines = labelLines
        self.part = part
    }
}

/// One column. Columns break at section boundaries, never mid-section.
public struct LayoutColumn: Sendable, Hashable {
    /// Left edge of the column (gutter included) in the viewport.
    public var x: Double
    /// Full width, gutter included.
    public var width: Double
    public var blocks: [LayoutBlock]

    public init(x: Double, width: Double, blocks: [LayoutBlock]) {
        self.x = x
        self.width = width
        self.blocks = blocks
    }
}

/// One shown pass as placed (P8-2): what the map strip, the jump and the current-pass
/// tracking read.
public struct PlanPass: Sendable, Hashable {
    /// 0-based among shown passes; the jump key is `index + 1`.
    public var index: Int
    /// Index into `SlotArrangement.passes`; nil for the full song.
    public var position: Int?
    /// The part: index into `RenderModel.sections`.
    public var source: Int
    public var name: PassName
    /// Never `.skip`.
    public var mode: PassMode
    public var tint: SectionTint
    /// The part's kind, for the map's kind stripe.
    public var kind: SectionKind?
    /// Column of the pass's first block.
    public var column: Int
    /// Top of its first block in that column.
    public var top: Double
    /// Bottom of its last block (its last part).
    public var bottom: Double
    /// Sum of its blocks' heights (the map chip's width).
    public var weight: Double
    /// The medley member it belongs to (P9-3); 0 for a song.
    public var segment = 0

    public init(
        index: Int,
        position: Int?,
        source: Int,
        name: PassName,
        mode: PassMode,
        tint: SectionTint,
        kind: SectionKind?,
        column: Int,
        top: Double,
        bottom: Double,
        weight: Double,
    ) {
        self.index = index
        self.position = position
        self.source = source
        self.name = name
        self.mode = mode
        self.tint = tint
        self.kind = kind
        self.column = column
        self.top = top
        self.bottom = bottom
        self.weight = weight
    }
}

/// The auto-fit result for one song on one viewport.
public struct LayoutPlan: Sendable, Hashable {
    public var lyricSize: Double
    public var chordSize: Double
    public var fit: LayoutFit
    public var columns: [LayoutColumn]
    /// Height of the tallest column.
    public var contentHeight: Double
    public var viewport: LayoutSize
    /// Scroll offsets PgDn/PgUp step through (first is 0; each page keeps a line of
    /// overlap). A single `[0]` when the plan fits.
    public var pageStops: [Double]
    /// Lyric lines (not rows) in the song: input to the tempo-based scroll estimate.
    public var lineCount: Int
    /// This song's label gutter: `LayoutStyle.gutterWidth`, wider (up to `maxGutterWidth`)
    /// when a label needs it. Lyrics start at `gutterWidth + LayoutStyle.gutterGap` from
    /// each column's left edge.
    public var gutterWidth: Double
    /// The shown passes in played order, with where each landed (P8-2).
    public var passes: [PlanPass]

    public init(
        lyricSize: Double,
        chordSize: Double,
        fit: LayoutFit,
        columns: [LayoutColumn],
        contentHeight: Double,
        viewport: LayoutSize,
        pageStops: [Double],
        lineCount: Int,
        gutterWidth: Double = LayoutStyle.stage.gutterWidth,
        passes: [PlanPass] = [],
    ) {
        self.lyricSize = lyricSize
        self.chordSize = chordSize
        self.fit = fit
        self.columns = columns
        self.contentHeight = contentHeight
        self.viewport = viewport
        self.pageStops = pageStops
        self.lineCount = lineCount
        self.gutterWidth = gutterWidth
        self.passes = passes
    }

    /// How far the content scrolls (0 when it fits).
    public var overflow: Double {
        max(0, contentHeight - viewport.height)
    }

    public var needsScroll: Bool {
        overflow > 0
    }
}
