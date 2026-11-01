import ChordPro
import Diagrams
import Editing
import Foundation
import Library
import LiveLayout
import Testing

/// The print paginator (P9-1 spec 5.3) with `FixedAdvanceMetrics` at 10 pt: every character
/// 5 pt wide, a chord+lyric line pair 20.7 pt tall (8.2 chord band + 12.5 text band).
struct PageLayoutTests {
    typealias Support = LiveLayoutSupport

    static let size = 10.0
    static let metrics = FixedAdvanceMetrics()

    static func request(_ source: String, passes: [PlayedPass]? = nil) -> LayoutRequest {
        LayoutRequest(
            model: Support.model(source: source),
            viewport: LayoutSize(width: 540, height: 600),
            minLyricSize: size,
            passes: passes,
            style: .print(lyricSize: size),
        )
    }

    static func pages(
        _ source: String,
        first: Double = 600,
        later: Double = 700,
        columns: Int? = 1,
        extras: [Double] = [],
    ) -> PagedSong {
        PageLayout.paginate(
            request(source),
            page: PageGeometry(
                firstBody: LayoutSize(width: 540, height: first),
                laterBody: LayoutSize(width: 540, height: later),
                columns: columns,
            ),
            extras: extras,
            metrics: metrics,
        )
    }

    /// Sections of `lines` lines each, named Verse 1...n.
    static func song(sections: Int, lines: Int, breakAfter: Int? = nil) -> String {
        var text = ["{title: Generated}"]
        for section in 1 ... sections {
            text.append("{start_of_verse: Verse \(section)}")
            for line in 1 ... lines {
                text.append("[G]Line \(line) of [C]verse \(section)")
                if line == breakAfter {
                    text.append("")
                }
            }
            text.append("{end_of_verse}")
        }
        return text.joined(separator: "\n")
    }

    /// A block as the rules see it: its pass id, its part and its lyric rows.
    struct Piece: CustomStringConvertible {
        var id: Int
        var part: Int
        var lines: Int

        var description: String {
            "\(id).\(part):\(lines)"
        }
    }

    static let tab = FillTabBlock(
        part: "fill",
        notes: [TabNote(
            tick: 0,
            length: 480,
            position: FretPosition(string: 1, fret: 5),
            name: "D",
        )],
        chords: [FillTabChord(tick: 0, name: "G")],
        ticks: 0 ..< 960,
        pulses: [0, 480],
        bars: [0],
        tuning: .bassStandard4,
        accessibility: "Tab",
    )

    static func blocks(_ plan: LayoutPlan) -> [Piece] {
        plan.columns.flatMap(\.blocks).map { block in
            Piece(id: block.id, part: block.part, lines: block.allRows.count { $0.kind == .lyric })
        }
    }

    @Test
    func `a short song fits one page in one block per section`() {
        let paged = Self.pages(Self.song(sections: 2, lines: 2))
        #expect(paged.pages.count == 1)
        #expect(paged.pages[0].fit == .fits)
        #expect(paged.pages[0].pageStops.isEmpty)
        #expect(Self.blocks(paged.pages[0]).map(\.part) == [0, 0])
        #expect(paged.pages[0].lyricSize == Self.size)
        #expect(paged.passes.map(\.index) == [0, 1])
    }

    @Test
    func `a long song breaks between sections and moves a section whole`() {
        // Each 6-line verse is about 136 pt; 4 fit a 600 pt page, the 5th moves whole.
        let paged = Self.pages(Self.song(sections: 7, lines: 6))
        #expect(paged.pages.count == 2)
        for page in paged.pages {
            #expect(Self.blocks(page).allSatisfy { $0.part == 0 && $0.lines == 6 })
        }
        // Played order across pages, each pass listed on the page where it starts.
        #expect(paged.passes.map(\.index) == Array(0 ..< 7))
        #expect(paged.pages.allSatisfy { $0.contentHeight <= $0.viewport.height })
    }

    @Test
    func `the first page body is shorter than the later ones`() {
        let paged = Self.pages(Self.song(sections: 8, lines: 6), first: 300, later: 700)
        #expect(paged.pages[0].viewport.height == 300)
        #expect(paged.pages[1].viewport.height == 700)
        #expect(paged.pages[0].contentHeight <= 300)
        #expect(Self.blocks(paged.pages[0]).count == 2)
        #expect(Self.blocks(paged.pages[1]).count == 5)
    }

    @Test
    func `an over-long section splits at a stanza break and the rest is labelled cont`() throws {
        // One 40-line verse with a stanza break after line 30, on 400 pt pages.
        let paged = Self.pages(
            Self.song(sections: 1, lines: 40, breakAfter: 15),
            first: 400,
            later: 400,
        )
        #expect(paged.pages.count > 1)
        let first = try #require(paged.pages[0].columns.first?.blocks.first)
        #expect(first.part == 0)
        // The split lands on the stanza break: 15 lines on the first page.
        #expect(first.allRows.count { $0.kind == .lyric } == 15)
        let second = try #require(paged.pages[1].columns.first?.blocks.first)
        #expect(second.part == 1)
        #expect(second.label == "Verse 1 (cont.)")
        #expect(second.labelLines.map(\.text.text).contains("(cont.)"))
        // Every line printed exactly once.
        let lines = paged.pages.flatMap(Self.blocks).map(\.lines).reduce(0, +)
        #expect(lines == 40)
    }

    @Test(arguments: [80.0, 100.0, 125.0, 150.0, 175.0])
    func `a split never leaves or carries fewer than two lines`(room: Double) {
        // A short verse first, then a verse taller than a page: the room left after the
        // first verse varies with `room`.
        let source = Self.song(sections: 1, lines: 2) + "\n"
            + Self.song(sections: 1, lines: 30).replacingOccurrences(
                of: "{title: Generated}",
                with: "",
            )
            .replacingOccurrences(of: "Verse 1", with: "Verse 2")
        let paged = Self.pages(source, first: 60 + room, later: 500)
        let parts = paged.pages.flatMap(Self.blocks).filter { $0.id == 1 }
        #expect(parts.count >= 2)
        #expect(parts.allSatisfy { $0.lines >= 2 }, "\(parts)")
        #expect(parts.map(\.lines).reduce(0, +) == 30)
    }

    @Test
    func `two columns read down the first column then the second`() {
        let short = (1 ... 8)
            .map { "{start_of_verse: Verse \($0)}\n[G]La la [C]la\n[D]Da da\n{end_of_verse}" }
            .joined(separator: "\n")
        let paged = Self.pages("{title: T}\n" + short, first: 200, later: 200, columns: 2)
        #expect(paged.columns == 2)
        let page = paged.pages[0]
        #expect(page.columns.count == 2)
        let first = page.columns[0].blocks.map(\.id)
        let second = page.columns[1].blocks.map(\.id)
        #expect(!first.isEmpty && !second.isEmpty)
        #expect((first + second) == Array(0 ..< first.count + second.count))
        #expect(page.columns[1].x > page.columns[0].x + page.columns[0].width)
    }

    @Test
    func `auto uses two columns only when they save a page and no line wraps`() {
        // A short song fits one page in one column: two would only leave the right one empty.
        let short = Self.pages("{title: T}\n[G]Short line\n[C]Another", columns: nil)
        #expect(short.columns == 1)
        // Eight short verses (about 128 pt each) need two 600 pt pages in one column and
        // one page in two.
        let verses = (1 ... 8).map { verse in
            "{start_of_verse: Verse \(verse)}\n"
                + (1 ... 5).map { "[G]Short line \($0) [C]here" }.joined(separator: "\n")
                + "\n{end_of_verse}"
        }
        let saving = Self.pages("{title: T}\n" + verses.joined(separator: "\n"), columns: nil)
        #expect(saving.columns == 2)
        #expect(saving.pages.count == 1)
        #expect(Self.pages("{title: T}\n" + verses.joined(separator: "\n")).pages.count == 2)
        // About 70 characters (350 pt) is wider than a two-column lyric area (204 pt): one
        // column even when two would save a page.
        let long = Self.pages(
            "{title: T}\n" + (1 ... 40).map { _ in "[G]" + String(repeating: "word ", count: 14) }
                .joined(separator: "\n"),
            columns: nil,
        )
        #expect(long.columns == 1)
        #expect(long.pages[0].columns.count == 1)
    }

    @Test
    func `a fill tab is never separated from the line above it`() {
        var model = Support.model(source: Self.song(sections: 1, lines: 24))
        let tab = Self.tab
        // A tab after every second line, so any cut point lands next to one.
        var items: [RenderItem] = []
        for (index, item) in model.sections[0].items.enumerated() {
            items.append(item)
            if index.isMultiple(of: 2) {
                items.append(.fillTab(tab))
            }
        }
        model.sections[0].items = items
        for height in stride(from: 200.0, through: 320, by: 15) {
            let request = LayoutRequest(
                model: model,
                viewport: LayoutSize(width: 540, height: height),
                minLyricSize: Self.size,
                style: .print(lyricSize: Self.size),
            )
            let paged = PageLayout.paginate(
                request,
                page: PageGeometry(
                    firstBody: LayoutSize(width: 540, height: height),
                    laterBody: LayoutSize(width: 540, height: height),
                    columns: 1,
                ),
                metrics: Self.metrics,
            )
            #expect(paged.pages.count > 1)
            for page in paged.pages {
                for block in page.columns.flatMap(\.blocks) {
                    let rows = block.allRows.filter { $0.kind != .stanzaBreak }
                    #expect(
                        rows.first?.kind != .fillTab,
                        "a page starts with a fill tab at \(height)",
                    )
                }
            }
        }
    }

    @Test
    func `extras follow the last section whole and move to a new page when they do not fit`() {
        let fits = Self.pages(Self.song(sections: 1, lines: 2), extras: [80])
        #expect(fits.pages.count == 1)
        #expect(fits.extras.first?.page == 0)
        #expect((fits.extras.first?.y ?? 0) > fits.pages[0].contentHeight)
        let moves = Self.pages(Self.song(sections: 1, lines: 2), first: 120, extras: [100])
        #expect(moves.pages.count == 2)
        #expect(moves.extras.first?.page == 1)
        #expect(moves.extras.first?.y == 0)
        #expect(moves.pages[1].columns.isEmpty)
    }

    @Test
    func `notes come first as their own block`() throws {
        var request = Self.request(Self.song(sections: 1, lines: 2))
        request.notes = ["Count in four"]
        let paged = PageLayout.paginate(
            request,
            page: PageGeometry(
                firstBody: LayoutSize(width: 540, height: 600),
                laterBody: LayoutSize(width: 540, height: 600),
                columns: 1,
            ),
            metrics: Self.metrics,
        )
        let first = try #require(paged.pages[0].columns.first?.blocks.first)
        #expect(first.id == -1)
        #expect(first.allRows.first?.text.first?.text == "Count in four")
    }

    @Test
    func `the stage packing is unchanged by the print policy`() {
        // The default packer neither moves whole first nor keeps two lines: a section that
        // does not fit splits in the remaining room, as before.
        let model = Support.model(source: Self.song(sections: 2, lines: 12))
        let request = LayoutRequest(
            model: model,
            viewport: LayoutSize(width: 1374, height: 400),
            minLyricSize: 22,
        )
        let plan = LayoutEngine.plan(request, metrics: Self.metrics)
        #expect(plan.columns.flatMap(\.blocks).contains { $0.part > 0 })
    }
}
