// Owner: P9-2 (Singer view). The singer view's layout input: which drawing a request asks
// for, and the larger type singer view lays out with (P9-2 sections 6.2 and 6.5).

/// Which drawing of a song a layout request asks for (P9-2 section 6.2).
public enum StageView: String, Sendable, Hashable, CaseIterable {
    /// Chords over lyrics, as the song shows them.
    case chart
    /// Lyrics only (`SingerView`): no chord rows, walk-ups, fills, tab or notes block; a
    /// Chords only pass shows as First line and keeps its "CHORDS" tag.
    case singer
}

public extension LayoutStyle {
    /// Singer view's sizes (P9-2 section 6.5, R178; tuned in step 0 over the Welcome songs,
    /// the Hindi fixtures and a 40-line song at 1280 x 800, 1440 x 900 and 1920 x 1080):
    /// lyrics up to 60 pt; the stage's line rhythm with a little more air between parts; a
    /// narrower column gap, so a long romanized line keeps more width (the gutter gap stays
    /// the stage's 18 pt, which the loop bracket sits in, R163). A
    /// layout without wrapped lines wins from the 28 pt floor unless wrapping makes the
    /// lyrics more than 15% larger: a phrase broken across two rows is harder to sing from
    /// than slightly smaller type. Chord fields are unused.
    static let singer: Self = {
        var style = Self.stage
        style.maxLyricSize = 60
        style.comfortableLyricSize = 36
        style.comfortableMinimumFactor = 1
        style.lineHeight = 1.25
        style.sectionSpacing = 0.7
        style.columnGap = 32
        style.wrapPenalty = 0.15
        return style
    }()

    /// The smallest lyric size singer view lays out on stage (R178): the stage's request uses
    /// the larger of this and the user's minimum. Print sets its own size.
    static let singerMinimumLyricSize = 28.0
}
