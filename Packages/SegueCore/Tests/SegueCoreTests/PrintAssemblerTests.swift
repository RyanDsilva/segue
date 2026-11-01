import ChordPro
import Editing
import Foundation
import Library
import LiveLayout
import Printing
import Setlists
import Support
import Testing

/// The print document (P9-1 spec 5.10, 5.11, 5.13, 14.1): set list rows from the timing,
/// page numbers after one or two set list pages, links, outline, metadata and slot labels.
struct PrintAssemblerTests {
    static let metrics = FixedAdvanceMetrics()
    static let date = Date(timeIntervalSince1970: 1_800_000_000)

    static func id(_ index: Int) -> SetlistItemID {
        SetlistItemID(ULID(milliseconds: 2, randomness: Array(repeating: UInt8(index), count: 10)))
    }

    static func songID(_ index: Int) -> SongID {
        SongID(ULID(milliseconds: 1, randomness: Array(repeating: UInt8(index), count: 10)))
    }

    /// A song of `sections` four-line verses.
    static func song(_ title: String, sections: Int = 1, slot: String? = nil) -> PrintSong {
        var lines = ["{title: \(title)}"]
        for section in 1 ... sections {
            lines.append("{start_of_verse: Verse \(section)}")
            lines += (1 ... 4).map { "[G]Line \($0) of [C]verse \(section)" }
            lines.append("{end_of_verse}")
        }
        let model = RenderModel(
            document: ChordProParser.parse(lines.joined(separator: "\n")).0,
            options: DisplayOptions(),
        )
        let request = LayoutRequest(
            model: model,
            viewport: LayoutSize(width: 540, height: 700),
            minLyricSize: 11.5,
        )
        return PrintSong(
            request: request,
            header: PrintHeader(title: title, credits: "A, B \u{00B7} Kalank", slotLabel: slot),
            outlineTitle: slot.map { "\($0.split(separator: " ")[0]). \(title)" },
        )
    }

    static func job(
        _ target: PrintJob.Target,
        songs: [PrintSong],
        contents: PrintJob.Contents? = nil,
        options: PrintOptions = PrintOptions(paper: .letter),
        title: String = "Friday Set",
    ) -> PrintJob {
        PrintJob(
            target: target,
            title: title,
            songs: songs,
            contents: contents,
            options: options,
            author: "A, B",
            subject: "The Anchor \u{00B7} Fri 23 Oct 2026",
            tags: ["ballad"],
            footerName: target == .setlist ? title : target == .selection ? "Songbook" : nil,
            date: date,
        )
    }

    /// Song, break "Set 2" with a 20 minute interval, unknown-time song, estimated song,
    /// missing song.
    static func friday() -> (entries: [SetlistEntry], timing: SetlistTiming) {
        let entries = [
            SetlistEntry(itemId: id(0), songId: songID(0)),
            SetlistEntry(itemId: id(1), break: SetlistBreak(label: "Set 2", length: 1200)),
            SetlistEntry(itemId: id(2), songId: songID(1)),
            SetlistEntry(itemId: id(3), songId: songID(2)),
            SetlistEntry(itemId: id(4), songId: songID(3)),
        ]
        let timing = SetlistTiming(
            entries: entries,
            times: [
                id(0): .known(seconds: 220, bars: 88, tempo: 96, estimated: false),
                id(2): .unknown(.noTempo),
                id(3): .known(seconds: 245, bars: 98, tempo: 96, estimated: true),
            ],
            target: nil,
        )
        return (entries, timing)
    }

    static func slots() -> [SetlistItemID: PrintSlot] {
        [
            id(0): PrintSlot(
                title: "Harbour Lights",
                credits: "Mira Sol",
                key: "G, capo 2",
                song: 0,
            ),
            id(2): PrintSlot(title: "Soundcheck", credits: nil, key: "G", song: 1),
            id(3): PrintSlot(title: "Kitaabon Wali Gali", credits: "Segue", key: "Am", song: 2),
        ]
    }

    @Test
    func `set list rows carry times, part totals, breaks and missing songs`() {
        let (entries, timing) = Self.friday()
        let rows = PrintSetList.rows(entries: entries, timing: timing, slots: Self.slots())
        #expect(rows == [
            .breakHeading(title: "Set 1", total: "3:40", interval: nil),
            .song(SetListSong(
                number: "1",
                title: "Harbour Lights",
                credits: "Mira Sol",
                key: "G, capo 2",
                time: "3:40",
                song: 0,
            )),
            .breakHeading(
                title: "Set 2",
                total: "~\u{2265}4:05 + 2 unknown",
                interval: "Interval 20:00",
            ),
            .song(SetListSong(number: "2", title: "Soundcheck", key: "G", time: "--:--", song: 1)),
            .song(SetListSong(
                number: "3",
                title: "Kitaabon Wali Gali",
                credits: "Segue",
                key: "Am",
                time: "~4:05",
                song: 2,
            )),
            .missing(number: "4"),
        ])
    }

    @Test
    func `a songbook numbers song pages after the set list page and links each row`() {
        let (entries, timing) = Self.friday()
        let rows = PrintSetList.rows(entries: entries, timing: timing, slots: Self.slots())
        let songs = [
            Self.song("Harbour Lights", sections: 12, slot: "1 of 4"),
            Self.song("Soundcheck", slot: "2 of 4"),
            Self.song("Kitaabon Wali Gali", slot: "3 of 4"),
        ]
        let document = PrintAssembler.document(
            Self.job(
                .setlist,
                songs: songs,
                contents: .init(title: "Friday Set", line: "x", rows: rows),
            ),
            metrics: Self.metrics,
        )
        guard case let .setList(list) = document.pages[0] else {
            Issue.record("the set list comes first")
            return
        }
        let counts = document.songPageCounts
        #expect(counts[0] == 2)
        #expect(document.pages.count == 1 + 2 + 1 + 1)
        let targets = list.rows.compactMap(\.target)
        #expect(targets == [1, 3, 4])
        #expect(list.footer == PrintFooter(left: "Friday Set", right: "Page 1 of 5"))
        guard case let .song(second) = document.pages[2] else {
            Issue.record("page 3 is a song page")
            return
        }
        #expect(!second.isFirst)
        #expect(second.footer.right == "Page 3 of 5")
        #expect(second.header.slotLabel == "1 of 4")
        // Outline: the list, then the songs under their parts.
        #expect(document.outline.map(\.title) == ["Set list", "Set 1", "Set 2"])
        #expect(document.outline[1].children.map(\.title) == ["1. Harbour Lights"])
        #expect(document.outline[2].children.map(\.page) == [3, 4])
        #expect(document.outline[2].page == 3)
        #expect(document.fileName == "Friday Set.pdf")
        #expect(document.metadata.keywords == ["songbook"])
        #expect(document.metadata.author == nil)
        #expect(document.metadata.subject == "The Anchor \u{00B7} Fri 23 Oct 2026")
    }

    @Test
    func `a long set list continues on a second page and song pages follow it`() {
        let songs = (0 ..< 30).map { Self.song("Song \($0)") }
        let rows = (0 ..< 30).map { index in
            SetListRow.song(SetListSong(
                number: "\(index + 1)",
                title: "Song \(index)",
                credits: "Artist",
                key: "G",
                time: "3:00",
                song: index,
            ))
        }
        let document = PrintAssembler.document(
            Self.job(
                .setlist,
                songs: songs,
                contents: .init(title: "Long Set", line: "x", rows: rows),
            ),
            metrics: Self.metrics,
        )
        let lists = document.pages.compactMap { page -> SetListPage? in
            if case let .setList(list) = page {
                return list
            }
            return nil
        }
        #expect(lists.count == 2)
        #expect(lists[1].head.title == "Long Set (cont.)")
        #expect(lists[1].head.line == nil)
        #expect(lists.flatMap(\.rows).count == 30)
        #expect(lists.flatMap(\.rows).compactMap(\.target) == Array(2 ..< 32))
        // Rows never overflow the body under their head.
        for list in lists {
            let capacity = 792 - PrintPageMetrics.top - PrintPageMetrics.bottom
                - SetListMetrics.headHeight(continuation: list.head.isContinuation)
            #expect(list.rows.last.map { $0.y + $0.height } ?? 0 <= capacity)
        }
    }

    @Test
    func `a selection songbook has a contents page in the given order with no times`() {
        let slots = ["Kettle On", "Harbour Lights", "Ferry Lights"].enumerated()
            .map { index, title in
                PrintSlot(title: title, credits: "Segue", key: "G", song: index)
            }
        let rows = PrintSetList.selectionRows(slots)
        let songs = slots.map { Self.song($0.title) }
        let document = PrintAssembler.document(
            Self.job(
                .selection,
                songs: songs,
                contents: .init(title: "Songbook", line: "3 songs", rows: rows),
                title: "Songbook",
            ),
            metrics: Self.metrics,
        )
        guard case let .setList(list) = document.pages[0] else {
            Issue.record("contents first")
            return
        }
        #expect(!list.showsTimes)
        #expect(list.head.title == "Songbook")
        #expect(list.rows.map(\.row) == rows)
        #expect(list.rows.compactMap(\.target) == [1, 2, 3])
        #expect(document.outline.map(\.title) == [
            "Contents",
            "Kettle On",
            "Harbour Lights",
            "Ferry Lights",
        ])
        for case let .song(page) in document.pages {
            #expect(page.header.slotLabel == nil)
            #expect(page.footer.left == "Songbook")
        }
        #expect(PrintFileName.name(title: PrintFileName.selectionTitle(songs: 3), part: .chords)
            == "Songbook (3 songs).pdf")
    }

    @Test
    func `a single chart has its title as outline, the artists and tags as metadata`() {
        var options = PrintOptions(part: .bass, paper: .a4)
        options.sectionMap = false
        let document = PrintAssembler.document(
            Self.job(
                .song,
                songs: [Self.song("Harbour Lights")],
                options: options,
                title: "Harbour Lights",
            ),
            metrics: Self.metrics,
        )
        #expect(document.pages.count == 1)
        #expect(document.outline == [PrintOutlineEntry(title: "Harbour Lights", page: 0)])
        #expect(document.metadata.author == "A, B")
        #expect(document.metadata.subject == nil)
        #expect(document.metadata.keywords == ["ballad", "bass chart"])
        #expect(document.metadata.creator == "Segue")
        #expect(document.metadata.date == Self.date)
        #expect(document.fileName == "Harbour Lights (Bass).pdf")
        guard case let .song(page) = document.pages[0] else { return }
        #expect(page.footer == PrintFooter(left: nil, right: "Page 1 of 1"))
        #expect(page.plan.viewport.width == 595 - 72)
    }
}

/// A song on its pages: the map line, Fit on one page and the remembered options.
struct PrintSongLayoutTests {
    typealias Support = PrintAssemblerTests

    @Test
    func `the section map line names each pass, its number past the first and its mode`() {
        var song = Support.song("Harbour Lights", sections: 2)
        let units = SongSections.units(of: song.request.model.sections)
        song.request.passes = [
            PlayedPass(index: units[0].index, position: 0),
            PlayedPass(index: units[1].index, position: 1),
            PlayedPass(index: units[0].index, mode: .chordsOnly, position: 2),
            PlayedPass(index: units[1].index, mode: .firstLine, position: 3),
        ]
        let laid = PrintAssembler.layout(
            song,
            job: Support.job(.song, songs: [song]),
            metrics: Support.metrics,
        )
        #expect(laid.header.mapLines == [
            "V1 \u{00B7} V2 \u{00B7} V1 2/2 (chords) \u{00B7} V2 2/2 (1st line)",
        ])
        let one = PrintAssembler.layout(
            Support.song("Short"),
            job: Support.job(.song, songs: []),
            metrics: Support.metrics,
        )
        #expect(one.header.mapLines.isEmpty)
    }

    @Test
    func `fit on one page fits a two page song at a smaller size, or reports it cannot`() {
        var options = PrintOptions(paper: .letter, columns: .one)
        let medium = Support.song("Medium", sections: 6)
        let plain = PrintAssembler.layout(
            medium,
            job: Support.job(.song, songs: [medium], options: options),
            metrics: Support.metrics,
        )
        options.fitOnePage = true
        #expect(plain.paged.pages.count == 2)
        let fitted = PrintAssembler.layout(
            medium,
            job: Support.job(.song, songs: [medium], options: options),
            metrics: Support.metrics,
        )
        #expect(fitted.paged.pages.count == 1)
        #expect(!fitted.fitFailed)
        #expect(fitted.paged.pages[0].lyricSize < 11.5)
        let huge = Support.song("Huge", sections: 60)
        let failed = PrintAssembler.layout(
            huge,
            job: Support.job(.song, songs: [huge], options: options),
            metrics: Support.metrics,
        )
        #expect(failed.fitFailed)
        #expect(failed.paged.pages.count > 1)
    }

    @Test
    func `remembered options decode leniently`() throws {
        let json = Data(#"{"paper":"letter","size":"huge","columns":"two","sectionMap":false}"#
            .utf8)
        let decoded = try JSONDecoder().decode(RememberedPrintOptions.self, from: json)
        #expect(decoded.paper == .letter)
        #expect(decoded.size == .medium)
        #expect(decoded.columns == .two)
        #expect(!decoded.sectionMap)
        #expect(decoded.repeats == .writtenOut)
        let options = PrintOptions(remembered: decoded, part: .bass, fillsAsTab: true)
        #expect(options.part == .bass)
        #expect(options.fillsAsTab)
        #expect(!options.stageNotes)
    }
}

/// File names (spec 5.11).
struct PrintFileNameTests {
    @Test(arguments: [
        ("Harbour Lights", PrintPart.chords, "Harbour Lights.pdf"),
        ("Harbour Lights", .bass, "Harbour Lights (Bass).pdf"),
        ("Friday Set", .lyrics, "Friday Set (Lyrics).pdf"),
        ("AC/DC: Live", .chords, "AC-DC- Live.pdf"),
        ("   ", .chords, "Untitled.pdf"),
        ("", .bass, "Untitled (Bass).pdf"),
    ])
    func `names by title and part`(title: String, part: PrintPart, expected: String) {
        #expect(PrintFileName.name(title: title, part: part) == expected)
    }

    @Test
    func `long titles are trimmed to 120 characters with the suffix`() {
        let name = PrintFileName.name(title: String(repeating: "a", count: 300), part: .bass)
        #expect(name.count == 120 + ".pdf".count)
        #expect(name.hasSuffix("a (Bass).pdf"))
        #expect(PrintFileName.selectionTitle(songs: 1) == "Songbook (1 song)")
    }
}
