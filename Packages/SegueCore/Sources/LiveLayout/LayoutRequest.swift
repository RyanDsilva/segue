// Phase 2 frozen interface (docs/phases/2-interfaces.md). Owner: unit B.

import Editing
import Foundation
import Library

/// A size in points.
public struct LayoutSize: Sendable, Hashable {
    public var width: Double
    public var height: Double

    public init(width: Double, height: Double) {
        self.width = width
        self.height = height
    }
}

/// What a run of text is, so measurement and drawing use the same face and size.
public enum TextRole: Sendable, Hashable {
    /// Lyric text: regular, the plan's `lyricSize`.
    case lyric
    /// Chord symbol: bold, `chordSize` (0.82 x lyric), `cueText`.
    case chord
    /// Section label in the gutter: bold, `LayoutStyle.labelSize` (fixed).
    case sectionLabel
    /// "Repeat chorus" line: regular, lyric size, muted.
    case collapsedRepeat
    /// `{comment}` lines: medium italic-free, lyric size x `LayoutStyle.commentScale`, muted.
    case comment
    /// Tab/grid lines: monospaced, lyric size x `LayoutStyle.verbatimScale`.
    case verbatim
    /// Cue callouts: bold, `LayoutStyle.cueSize` (fixed).
    case cue
    /// Song notes above the first section: medium, `LayoutStyle.noteSize` (fixed).
    case note
}

/// Text measurement, injected so the engine stays pure: tests use `FixedAdvanceMetrics`,
/// the stage uses Core Text with the bundled Schibsted Grotesk faces (SegueUI, unit B).
public protocol TextMeasuring: Sendable {
    /// Advance width in points of `text` set in `role` at point size `size`.
    func width(of text: String, role: TextRole, size: Double) -> Double
}

/// Every character advances `size * factor`: deterministic metrics for golden tests.
public struct FixedAdvanceMetrics: TextMeasuring {
    public var factor: Double

    public init(factor: Double = 0.5) {
        self.factor = factor
    }

    public func width(of text: String, role _: TextRole, size: Double) -> Double {
        Double(text.count) * size * factor
    }
}

/// Fixed geometry of the stage body (brand.md section 7). All values in points.
public struct LayoutStyle: Sendable, Hashable {
    /// Section label gutter.
    public var gutterWidth: Double
    /// Gap between the gutter and the lyrics.
    public var gutterGap: Double
    /// Gap between columns.
    public var columnGap: Double
    /// Columns narrower than this are not considered (limits 1...`maxColumns`).
    public var minColumnWidth: Double
    public var maxColumns: Int
    /// Largest lyric size auto-fit tries.
    public var maxLyricSize: Double
    /// Lyric line height as a multiple of the lyric size (1.25).
    public var lineHeight: Double
    /// Chord size as a multiple of the lyric size (0.82).
    public var chordRatio: Double
    /// Minimum horizontal gap between two chords on one row (lyrics are spread apart when
    /// chords would collide), as a multiple of the chord size.
    public var chordSpacing: Double
    /// Vertical space between sections, as a multiple of the lyric size.
    public var sectionSpacing: Double
    public var labelSize: Double
    public var cueSize: Double
    public var noteSize: Double
    public var commentScale: Double
    public var verbatimScale: Double
    /// Font size steps auto-fit snaps to (binary search runs over these steps).
    public var sizeStep: Double

    public init(
        gutterWidth: Double = 64,
        gutterGap: Double = 12,
        columnGap: Double = 48,
        minColumnWidth: Double = 360,
        maxColumns: Int = 3,
        maxLyricSize: Double = 44,
        lineHeight: Double = 1.25,
        chordRatio: Double = 0.82,
        chordSpacing: Double = 0.5,
        sectionSpacing: Double = 0.9,
        labelSize: Double = 13,
        cueSize: Double = 15,
        noteSize: Double = 17,
        commentScale: Double = 0.8,
        verbatimScale: Double = 0.75,
        sizeStep: Double = 0.5,
    ) {
        self.gutterWidth = gutterWidth
        self.gutterGap = gutterGap
        self.columnGap = columnGap
        self.minColumnWidth = minColumnWidth
        self.maxColumns = maxColumns
        self.maxLyricSize = maxLyricSize
        self.lineHeight = lineHeight
        self.chordRatio = chordRatio
        self.chordSpacing = chordSpacing
        self.sectionSpacing = sectionSpacing
        self.labelSize = labelSize
        self.cueSize = cueSize
        self.noteSize = noteSize
        self.commentScale = commentScale
        self.verbatimScale = verbatimScale
        self.sizeStep = sizeStep
    }

    /// The stage defaults. Unit B tunes the values; keep them in one place.
    public static let stage = Self()
}

/// Everything auto-fit needs for one song on one viewport.
public struct LayoutRequest: Sendable {
    /// The song as rendered with its display options (and setlist overrides).
    public var model: RenderModel
    /// The body area between header and footer.
    public var viewport: LayoutSize
    /// The user's `live.minLyricFont`; the plan's lyric size is never below it.
    public var minLyricSize: Double
    /// `LivePrefs.zoom`: multiplies the fitted size (still clamped to the minimum).
    public var zoom: Double
    /// `LivePrefs.collapseRepeats`.
    public var collapseRepeats: Bool
    /// `LivePrefs.columns`: forces the column count; nil = auto.
    public var columns: Int?
    /// Sidecar cues, placed at their sections' edges.
    public var cues: [SongCue]
    /// Sidecar notes and the setlist item note, shown above the first section.
    public var notes: [String]
    public var style: LayoutStyle

    public init(
        model: RenderModel,
        viewport: LayoutSize,
        minLyricSize: Double,
        zoom: Double = 1,
        collapseRepeats: Bool = true,
        columns: Int? = nil,
        cues: [SongCue] = [],
        notes: [String] = [],
        style: LayoutStyle = .stage,
    ) {
        self.model = model
        self.viewport = viewport
        self.minLyricSize = minLyricSize
        self.zoom = zoom
        self.collapseRepeats = collapseRepeats
        self.columns = columns
        self.cues = cues
        self.notes = notes
        self.style = style
    }
}
