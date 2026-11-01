import ChordPro
import Editing
import Foundation
import Library
import LiveLayout
import Testing

/// Print's Compact repeats (P9-1 spec 5.6): only an exactly identical Full pass of the same
/// part prints as a reference row; everything else stays written out.
struct CompactRepeatsTests {
    typealias Support = LiveLayoutSupport

    static let song = """
    {title: Harbour}
    {start_of_verse: Verse 1}
    [G]Paper boats on the [C]water
    {end_of_verse}
    {start_of_chorus}
    [C]Harbour lights, [G]call me back
    [D]Home again to [G]me
    {end_of_chorus}
    {start_of_verse: Verse 2}
    [G]Second verse here
    {end_of_verse}
    """

    /// The parts: Verse 1, Chorus, Verse 2.
    static func units() -> [SongSectionUnit] {
        SongSections.units(of: ChordProParser.parse(song).0)
    }

    static func paged(
        _ passes: [PlayedPass],
        compact: Bool = true,
        cues: [SongCue] = [],
        model: RenderModel? = nil,
        height: Double = 600,
    ) -> PagedSong {
        let request = LayoutRequest(
            model: model ?? Support.model(source: song),
            viewport: LayoutSize(width: 540, height: height),
            minLyricSize: 10,
            cues: cues,
            passes: passes,
            style: .print(lyricSize: 10),
        )
        return PageLayout.paginate(
            request,
            page: PageGeometry(
                firstBody: LayoutSize(width: 540, height: height),
                laterBody: LayoutSize(width: 540, height: height),
                columns: 1,
            ),
            compactRepeats: compact,
            metrics: FixedAdvanceMetrics(),
        )
    }

    static func texts(_ pages: [LayoutPlan]) -> [[String]] {
        pages.flatMap(\.columns).flatMap(\.blocks).map { block in
            block.allRows.filter { !$0.text.isEmpty }
                .map { $0.text.map(\.text).joined(separator: " ") }
        }
    }

    static func passes(_ modes: [(Int, PassMode)]) -> [PlayedPass] {
        let units = units()
        return modes.enumerated().map { position, pass in
            PlayedPass(index: units[pass.0].index, mode: pass.1, position: position)
        }
    }

    @Test
    func `an identical chorus prints as a reference row with its badge`() {
        let paged = Self.paged(Self.passes([(0, .full), (1, .full), (2, .full), (1, .full)]))
        let blocks = paged.pages.flatMap(\.columns).flatMap(\.blocks)
        #expect(blocks.count == 4)
        #expect(Self.texts(paged.pages)[3] == ["Chorus 2 of 2: as Chorus 1 above"])
        #expect(blocks[3].allRows.map(\.kind) == [.moreLines])
        #expect(blocks[3].labelLines.map(\.text.text).contains("2 of 2"))
        // Written out leaves it in full.
        let full = Self.paged(
            Self.passes([(0, .full), (1, .full), (2, .full), (1, .full)]),
            compact: false,
        )
        #expect(Self.texts(full.pages)[3] == ["Harbour lights, call me back", "Home again to me"])
    }

    @Test
    func `a reference to a pass on an earlier page names its page`() {
        // A page fits about two blocks, so the second chorus lands on a later page.
        let paged = Self.paged(
            Self.passes([(1, .full), (0, .full), (2, .full), (0, .full), (2, .full), (1, .full)]),
            height: 90,
        )
        #expect(paged.pages.count > 1)
        let numbered = paged.numbered(firstPage: 5)
        let rows = Self.texts(numbered).flatMap(\.self)
        #expect(rows.contains("Chorus 2 of 2: as Chorus 1 on page 5"), "\(rows)")
    }

    @Test
    func `chords only and first line passes are never compacted`() {
        let paged = Self.paged(Self.passes([(1, .full), (1, .chordsOnly), (1, .firstLine)]))
        let texts = Self.texts(paged.pages)
        #expect(!texts.flatMap(\.self).contains { $0.contains(": as ") })
    }

    @Test
    func `a pass with a cue stays written out`() {
        let cue = SongCue(section: "Chorus", text: "Drop out")
        let paged = Self.paged(Self.passes([(1, .full), (0, .full), (1, .full)]), cues: [cue])
        #expect(!Self.texts(paged.pages).flatMap(\.self).contains { $0.contains(": as ") })
    }

    @Test
    func `a changed chord on one pass keeps it written out`() {
        // Two different choruses that share a label are not the same part.
        let source = Self.song + """

        {start_of_chorus}
        [Am]Harbour lights, [G]call me back
        [D]Home again to [G]me
        {end_of_chorus}
        """
        let units = SongSections.units(of: ChordProParser.parse(source).0)
        let passes = [
            PlayedPass(index: units[1].index, position: 0),
            PlayedPass(index: units[3].index, position: 1),
        ]
        let paged = Self.paged(passes, model: Support.model(source: source))
        #expect(!Self.texts(paged.pages).flatMap(\.self).contains { $0.contains(": as ") })
    }
}
