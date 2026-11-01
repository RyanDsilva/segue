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
    /// The small concert chord beside a bass note (P8-4): medium, `ChordUnit.detailScale` x
    /// `chordSize`, muted, on the chord's baseline.
    case chordDetail
    /// A walk-up run after the chord unit (P8-4b section 8.8): medium,
    /// `ChordUnit.detailScale` x `chordSize`, muted, on the chord's baseline.
    case approach
    /// Section label in the gutter: bold, `LayoutStyle.labelSize` (fixed, never below
    /// `minLabelSize`).
    case sectionLabel
    /// The small second gutter line under a label: "(cont.)" on a section split between
    /// columns. Medium, `LayoutStyle.labelDetailSize`, muted.
    case labelDetail
    /// The gutter's pass badge, "2 of 3" (P8-2): semibold, `LayoutStyle.passBadgeSize`,
    /// `ink`, drawn in a hairline box.
    case passBadge
    /// The gutter's show mode tag, "CHORDS" / "1ST LINE" (P8-2): bold, uppercase,
    /// `LayoutStyle.modeTagSize`, tracked, muted.
    case modeTag
    /// The `|` between and around the chords of a Chords only row (P8-2): regular, chord
    /// size, `indicatorOff`.
    case chordSeparator
    /// "+ 3 more lines (first line only)" under a First line pass (P8-2): medium, lyric size
    /// x `LayoutStyle.moreLinesScale`, muted.
    case moreLines
    /// `{comment}` lines: medium italic-free, lyric size x `LayoutStyle.commentScale`, muted.
    case comment
    /// Tab/grid lines: monospaced, lyric size x `LayoutStyle.verbatimScale`.
    case verbatim
    /// Cue callouts: bold, `LayoutStyle.cueSize` (fixed).
    case cue
    /// Song notes above the first section: medium, `LayoutStyle.noteSize` (fixed).
    case note
}

/// Vertical extents of a face, as multiples of the point size.
public struct FontExtents: Sendable, Hashable {
    /// Baseline to the top of the tallest glyphs.
    public var ascent: Double
    /// Baseline to the bottom of the descenders (positive).
    public var descent: Double
    /// Baseline to the top of capitals and ascenders (the ink, below `ascent`). Chords sit
    /// tight above the lyric by ink, not by the font box.
    public var inkTop: Double

    public init(ascent: Double, descent: Double, inkTop: Double) {
        self.ascent = ascent
        self.descent = descent
        self.inkTop = inkTop
    }
}

/// The ink of one set line, as multiples of the point size: how far its glyphs reach above
/// and below the baseline (both positive when they do).
public struct InkExtents: Sendable, Hashable {
    public var top: Double
    public var bottom: Double

    public init(top: Double, bottom: Double) {
        self.top = top
        self.bottom = bottom
    }
}

/// Text measurement, injected so the engine stays pure: tests use `FixedAdvanceMetrics`,
/// the stage uses Core Text with the bundled Schibsted Grotesk faces (SegueUI, unit B).
///
/// Widths must scale linearly with `size` (true for the static, unhinted faces Core Text
/// uses on macOS): the engine measures each string once at a reference size and scales.
public protocol TextMeasuring: Sendable {
    /// Advance width in points of `text` set in `role` at point size `size`.
    func width(of text: String, role: TextRole, size: Double) -> Double

    /// Advance widths of `text` set as one line, from its start to each UTF-16 offset in
    /// `utf16Offsets` (ascending, each `0 ... text.utf16.count`). One call per line lets
    /// Core Text shape the line once, kerning included.
    func prefixWidths(
        of text: String,
        utf16Offsets: [Int],
        role: TextRole,
        size: Double,
    ) -> [Double]

    /// Ascent and descent of the face `role` uses, as multiples of the point size.
    func extents(of role: TextRole) -> FontExtents

    /// The ink of `text` set as one line in `role`, glyph fallback included (Devanagari
    /// matras reach well above Latin capitals), as multiples of the point size.
    func inkExtents(of text: String, role: TextRole) -> InkExtents
}

public extension TextMeasuring {
    /// Measures each prefix separately.
    func prefixWidths(
        of text: String,
        utf16Offsets: [Int],
        role: TextRole,
        size: Double,
    ) -> [Double] {
        let units = Array(text.utf16)
        return utf16Offsets.map { offset in
            let prefix = String(
                decoding: units[0 ..< min(max(offset, 0), units.count)],
                as: UTF16.self,
            )
            return width(of: prefix, role: role, size: size)
        }
    }

    /// A generic sans face: ascent 0.8, descent 0.2, ink top 0.7.
    func extents(of _: TextRole) -> FontExtents {
        FontExtents(ascent: 0.8, descent: 0.2, inkTop: 0.7)
    }

    /// The face's ink (`inkTop`, `descent`) for any text.
    func inkExtents(of _: String, role: TextRole) -> InkExtents {
        let face = extents(of: role)
        return InkExtents(top: face.inkTop, bottom: face.descent)
    }
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

    public func prefixWidths(
        of text: String,
        utf16Offsets: [Int],
        role _: TextRole,
        size: Double,
    ) -> [Double] {
        // Characters up to each offset, in one pass.
        var counts = [0: 0]
        var units = 0
        var characters = 0
        for character in text {
            units += character.utf16.count
            characters += 1
            counts[units] = characters
        }
        return utf16Offsets.map { Double(counts[$0] ?? 0) * size * factor }
    }
}

/// Fixed geometry of the stage body (brand.md section 7). All values in points.
public struct LayoutStyle: Sendable, Hashable {
    /// Section label gutter: the narrowest it gets. A song whose labels are wider widens
    /// its gutter (up to `maxGutterWidth`) rather than breaking a label mid-name.
    public var gutterWidth: Double
    public var maxGutterWidth: Double
    /// Gap between the gutter and the lyrics (18 pt, R163: wide enough for the rehearsal
    /// loop bracket to sit clear of the section tint).
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
    /// Chord band height as a multiple of the chord size (never less than the chord ink:
    /// `inkTop + descent`). Chord descenders end at the band's bottom, just above the
    /// lyric's ink.
    public var chordLineHeight: Double
    /// Vertical padding inside a section's tinted block, as a multiple of the lyric size.
    public var blockInset: Double
    /// A stanza break (blank line in a section), as a multiple of the lyric line height.
    public var stanzaBreakScale: Double
    /// Line height of labels, cues and notes, as a multiple of their size.
    public var smallLineHeight: Double
    /// Gutter labels shrink (down to this size, never smaller: 12pt) before they wrap.
    public var minLabelSize: Double
    /// Size of the gutter's second line (`TextRole.labelDetail`).
    public var labelDetailSize: Double
    /// The gutter's pass badge ("2 of 3") and mode tag ("CHORDS") sizes, and the gap above
    /// each (P8-2).
    public var passBadgeSize: Double
    public var modeTagSize: Double
    public var gutterLineGap: Double
    /// The pass badge's box padding: horizontal, vertical (points).
    public var passBadgePadding: LayoutSize
    /// A Chords only row: height as a multiple of the chord size, the gap around each `|`
    /// and the narrowest chord run, as multiples of the chord size (P8-2).
    public var chordRowHeight: Double
    public var chordRowGap: Double
    public var chordRunMinimum: Double
    /// "+ N more lines" as a multiple of the lyric size, and the space above it (points).
    public var moreLinesScale: Double
    public var moreLinesSpacing: Double
    /// How much larger a layout with fewer columns must be to win over `preferredColumns`
    /// (decisions.md, "Columns").
    public var wrapTolerance: Double
    /// Auto-fit never wraps a lyric line when a layout without wrapping reaches a
    /// comfortable size: the larger of this and `comfortableMinimumFactor` x the user's
    /// minimum (decisions.md, "Auto-fit wrapping (revised)").
    public var comfortableLyricSize: Double
    public var comfortableMinimumFactor: Double
    /// The column count auto-fit leans toward (decisions.md, "Columns"): fewer columns only
    /// when their size is more than `wrapTolerance` larger, more only when this count does
    /// not fit at the minimum without wrapping.
    public var preferredColumns: Int
    /// Padding inside a cue callout: horizontal, vertical (points).
    public var cuePadding: LayoutSize
    /// Space below each cue callout and between note paragraphs (points).
    public var calloutSpacing: Double

    public init(
        gutterWidth: Double = 64,
        maxGutterWidth: Double = 104,
        gutterGap: Double = 18,
        columnGap: Double = 48,
        minColumnWidth: Double = 360,
        maxColumns: Int = 3,
        maxLyricSize: Double = 44,
        lineHeight: Double = 1.25,
        chordRatio: Double = 0.82,
        chordSpacing: Double = 0.5,
        sectionSpacing: Double = 0.6,
        labelSize: Double = 13,
        cueSize: Double = 15,
        noteSize: Double = 17,
        commentScale: Double = 0.8,
        verbatimScale: Double = 0.75,
        sizeStep: Double = 0.5,
        chordLineHeight: Double = 1.0,
        blockInset: Double = 0.25,
        stanzaBreakScale: Double = 0.5,
        smallLineHeight: Double = 1.3,
        minLabelSize: Double = 12,
        labelDetailSize: Double = 12,
        passBadgeSize: Double = 12,
        modeTagSize: Double = 10.5,
        gutterLineGap: Double = 4,
        passBadgePadding: LayoutSize = LayoutSize(width: 6, height: 1),
        chordRowHeight: Double = 1.5,
        chordRowGap: Double = 0.55,
        chordRunMinimum: Double = 1.6,
        moreLinesScale: Double = 0.6,
        moreLinesSpacing: Double = 2,
        wrapTolerance: Double = 0.15,
        comfortableLyricSize: Double = 28,
        comfortableMinimumFactor: Double = 1.25,
        preferredColumns: Int = 2,
        cuePadding: LayoutSize = LayoutSize(width: 8, height: 4),
        calloutSpacing: Double = 6,
    ) {
        self.gutterWidth = gutterWidth
        self.maxGutterWidth = maxGutterWidth
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
        self.chordLineHeight = chordLineHeight
        self.blockInset = blockInset
        self.stanzaBreakScale = stanzaBreakScale
        self.smallLineHeight = smallLineHeight
        self.minLabelSize = minLabelSize
        self.labelDetailSize = labelDetailSize
        self.passBadgeSize = passBadgeSize
        self.modeTagSize = modeTagSize
        self.gutterLineGap = gutterLineGap
        self.passBadgePadding = passBadgePadding
        self.chordRowHeight = chordRowHeight
        self.chordRowGap = chordRowGap
        self.chordRunMinimum = chordRunMinimum
        self.moreLinesScale = moreLinesScale
        self.moreLinesSpacing = moreLinesSpacing
        self.wrapTolerance = wrapTolerance
        self.comfortableLyricSize = comfortableLyricSize
        self.comfortableMinimumFactor = comfortableMinimumFactor
        self.preferredColumns = preferredColumns
        self.cuePadding = cuePadding
        self.calloutSpacing = calloutSpacing
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
    /// Forces the column count; nil = auto-fit. The caller resolves the precedence
    /// (`LiveSettings.columns(for:)`: the song's `LivePrefs.columns`, else the global
    /// default, else auto).
    public var columns: Int?
    /// Sidecar cues, placed at their sections' edges.
    public var cues: [SongCue]
    /// Sidecar notes and the setlist item note, shown above the first section.
    public var notes: [String]
    /// The shown passes, in order (R147, R149): a slot's arrangement resolved against
    /// `model.sections` (`ArrangementResolver`); nil = the full song as written. Every pass
    /// is laid out in full (no repeat is ever collapsed).
    public var passes: [PlayedPass]?
    public var style: LayoutStyle
    /// Walk-ups and saved fills for the played passes (P8-4b section 8.6, P8-7 14): the
    /// bass-note view with walk-ups on or a fill that applies (R175); nil otherwise.
    public var walkUps: BassLineContext?

    public init(
        model: RenderModel,
        viewport: LayoutSize,
        minLyricSize: Double,
        zoom: Double = 1,
        columns: Int? = nil,
        cues: [SongCue] = [],
        notes: [String] = [],
        passes: [PlayedPass]? = nil,
        style: LayoutStyle = .stage,
        walkUps: BassLineContext? = nil,
    ) {
        self.model = model
        self.viewport = viewport
        self.minLyricSize = minLyricSize
        self.zoom = zoom
        self.columns = columns
        self.cues = cues
        self.notes = notes
        self.passes = passes
        self.style = style
        self.walkUps = walkUps
    }
}
