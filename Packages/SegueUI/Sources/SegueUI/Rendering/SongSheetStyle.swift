import SwiftUI

/// Sizes for rendering a song body. Colours come from `Theme.color` and resolve per
/// appearance, so the same view draws the light editor preview and the dark stage.
struct SongSheetStyle: Equatable {
    /// Lyric point size; chords are `FontTokens.chordToLyricRatio` of it.
    var lyricSize: CGFloat
    /// Width of the section label column (brand.md section 7: 64).
    var gutterWidth: CGFloat = 64
    /// Vertical space between sections.
    var sectionSpacing: CGFloat

    var chordSize: CGFloat {
        FontTokens.liveChordSize(forLyricSize: lyricSize)
    }

    /// Extra space between wrapped rows (line height 1.25).
    var rowSpacing: CGFloat {
        lyricSize * 0.25
    }

    /// Gap between a chord and the lyric below it.
    var chordGap: CGFloat {
        1
    }

    /// Editor preview and song detail (mockup E2 a: 18pt lyrics, 15pt chords).
    static let preview = Self(lyricSize: 18, gutterWidth: 76, sectionSpacing: 22)
    /// Live view (brand.md section 6: default 24).
    static let stage = Self(lyricSize: 24, sectionSpacing: 32)
}
