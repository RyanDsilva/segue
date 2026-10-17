// Phase 2 frozen interface (docs/phases/2-interfaces.md). Owner: unit B.
//
// The plan is fully positioned: the stage view draws every run at the x/y given here, with
// the face `TextRole` names, at the plan's sizes. It never re-flows text itself, so what is
// drawn is exactly what auto-fit measured.

import ChordPro
import Editing
import Foundation

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

    public init(
        text: String,
        x: Double,
        width: Double,
        role: TextRole,
        chordKind: ChordKind? = nil,
        size: Double = 0,
    ) {
        self.text = text
        self.x = x
        self.width = width
        self.role = role
        self.chordKind = chordKind
        self.size = size
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

    public init(
        kind: Kind,
        y: Double,
        height: Double,
        chordBaseline: Double?,
        textBaseline: Double,
        chords: [PlacedText],
        text: [PlacedText],
        source: BlockPath?,
    ) {
        self.kind = kind
        self.y = y
        self.height = height
        self.chordBaseline = chordBaseline
        self.textBaseline = textBaseline
        self.chords = chords
        self.text = text
        self.source = source
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
        /// The section in full.
        case rows([LayoutRow])
        /// A collapsed repeat: one muted line ("Repeat chorus") plus the lines that differ
        /// from the first occurrence.
        case collapsed(line: PlacedText, differing: [LayoutRow])
        /// Song and item notes above the first section.
        case notes([LayoutRow])
    }

    /// Index into `RenderModel.sections`; -1 for the notes block.
    public var id: Int
    /// Gutter label ("Chorus", "Chorus x2"); nil for none.
    public var label: String?
    /// Chorus labels use `text`, others `muted` (brand.md).
    public var isChorusLabel: Bool
    public var tint: SectionTint
    /// Top of the block in the column.
    public var y: Double
    public var height: Double
    public var content: Content
    public var cues: [PlacedCue]
    /// `label` broken to fit the gutter (it may also be set smaller than
    /// `LayoutStyle.labelSize`): `x` from the column's left edge, baselines from the block's
    /// top. Draw these rather than `label`.
    public var labelLines: [PlacedLine]
    /// For `.collapsed` content: the baseline of the collapsed line, from the block's top.
    public var collapsedBaseline: Double?
    /// 0 for a section's first (or only) part; 1, 2, ... for the continuation of a section
    /// that had to be split across columns (no label or cues; same `id`).
    public var part: Int

    public init(
        id: Int,
        label: String?,
        isChorusLabel: Bool,
        tint: SectionTint,
        y: Double,
        height: Double,
        content: Content,
        cues: [PlacedCue],
        labelLines: [PlacedLine] = [],
        collapsedBaseline: Double? = nil,
        part: Int = 0,
    ) {
        self.id = id
        self.label = label
        self.isChorusLabel = isChorusLabel
        self.tint = tint
        self.y = y
        self.height = height
        self.content = content
        self.cues = cues
        self.labelLines = labelLines
        self.collapsedBaseline = collapsedBaseline
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

    public init(
        lyricSize: Double,
        chordSize: Double,
        fit: LayoutFit,
        columns: [LayoutColumn],
        contentHeight: Double,
        viewport: LayoutSize,
        pageStops: [Double],
        lineCount: Int,
    ) {
        self.lyricSize = lyricSize
        self.chordSize = chordSize
        self.fit = fit
        self.columns = columns
        self.contentHeight = contentHeight
        self.viewport = viewport
        self.pageStops = pageStops
        self.lineCount = lineCount
    }

    /// How far the content scrolls (0 when it fits).
    public var overflow: Double {
        max(0, contentHeight - viewport.height)
    }

    public var needsScroll: Bool {
        overflow > 0
    }
}
