import ChordPro
import Editing
import Library
import LiveLayout
import PDFKit
import Printing
@testable import SegueUI
import Setlists
import Support
import Testing

/// Songbooks (P9-1 spec 5.10, 5.13, 14.2): the set list page, links, outline, slot pages,
/// arranged and out-of-date slots, and a library selection's contents page.
@MainActor
@Suite(.serialized)
struct PDFSongbookTests {
    typealias Support = PDFTestSupport

    /// Harbour Lights (arranged: Verse 1, Chorus, Verse 2 chords only, Chorus 2), a break
    /// "Set 2" with a 20 minute interval, Kettle On (no tempo), Ferry Lights (out-of-date
    /// arrangement), and a missing song.
    static func friday() -> (Setlist, [SongID: SongRecord]) {
        let harbour = Support.record(Support.harbour, index: 1)
        let kettle = Support.record(
            "{title: Kettle On}\n{artist: Segue Originals}\n{key: D}\n[D]Put the [G]kettle on\n",
            index: 2,
        )
        let ferry = Support.record(
            "{title: Ferry Lights}\n{key: A}\n{tempo: 120}\n{start_of_verse}\n"
                + "[A]Ferry lights [E]over the bay\n{end_of_verse}\n",
            index: 3,
        )
        let units = SongSections.units(of: harbour.document)
        let verse1 = units[1], chorus = units[2], verse2 = units[3]
        let arranged = SlotArrangement(passes: [
            ArrangementPass(anchor: verse1.anchor),
            ArrangementPass(anchor: chorus.anchor),
            ArrangementPass(anchor: verse2.anchor, mode: .chordsOnly),
            ArrangementPass(anchor: chorus.anchor),
        ])
        // A fingerprint the part no longer has: out of date (R122).
        let stale = SlotArrangement(passes: [
            ArrangementPass(
                anchor: SongSections.units(of: ferry.document)[0].anchor,
                fingerprint: "stale",
            ),
        ])
        let missing = SongID(ULID(milliseconds: 1, randomness: Array(repeating: 77, count: 10)))
        var setlist = Setlist(id: Support.setlistID(), name: "Friday Set", entries: [
            SetlistEntry(itemId: Support.item(0), songId: harbour.id, arrangement: arranged),
            SetlistEntry(
                itemId: Support.item(1),
                break: SetlistBreak(label: "Set 2", length: 1200),
            ),
            SetlistEntry(itemId: Support.item(2), songId: kettle.id),
            SetlistEntry(itemId: Support.item(3), songId: ferry.id, arrangement: stale),
            SetlistEntry(itemId: Support.item(4), songId: missing),
        ])
        setlist.venue = "The Anchor"
        return (setlist, [harbour.id: harbour, kettle.id: kettle, ferry.id: ferry])
    }

    @Test
    func `a setlist songbook links its set list to each slot's first page`() async throws {
        let (setlist, records) = Self.friday()
        let output = try await Support.make(
            Support.snapshot(.setlist(setlist, records)),
            Support.options(),
        )
        let pdf = output.pdf
        let list = Support.text(pdf, page: 0)
        for text in [
            "Friday Set", "The Anchor", "4 songs", "Set 1", "Set 2", "Interval 20:00",
            "Harbour Lights", "Kettle On", "Ferry Lights", "Song not in library", "--:--",
            "G, capo 2", "Page 1 of \(pdf.pageCount)",
        ] {
            #expect(list.contains(text), "set list page lacks \(text)")
        }
        #expect(list.contains("+ 2 unknown"))
        // Links on the set list page land on each slot's first page.
        let links = try #require(pdf.page(at: 0)).annotations.filter { $0.type == "Link" }
        let targets = links.compactMap { $0.destination?.page.map { pdf.index(for: $0) } }
        #expect(targets.count == 3)
        for target in targets {
            #expect(output.document.pages.indices.contains(target))
            guard case let .song(page) = output.document.pages[target] else {
                Issue.record("link \(target) is not a song page")
                continue
            }
            #expect(page.isFirst)
        }
        // Each slot starts its own page, with its slot number.
        let harbourPage = Support.text(pdf, page: targets[0])
        #expect(harbourPage.contains("1 of 4"))
        #expect(harbourPage.contains("Friday Set"))
        #expect(harbourPage.contains("CHORDS"))
        #expect(harbourPage.contains("2 of 2"))
        #expect(harbourPage.contains("V1 \u{00B7} Ch \u{00B7} V2 (chords) \u{00B7} Ch 2/2"))
        let ferry = Support.text(pdf, page: targets[2])
        #expect(ferry.contains("Arrangement out of date: printed as written"))
        #expect(ferry.contains("3 of 4"))
        // Outline: the list, then each part with its slots.
        let root = try #require(pdf.outlineRoot)
        let titles = (0 ..< root.numberOfChildren).compactMap { root.child(at: $0)?.label }
        #expect(titles == ["Set list", "Set 1", "Set 2"])
        let set2 = try #require(root.child(at: 2))
        #expect((0 ..< set2.numberOfChildren).compactMap { set2.child(at: $0)?.label }
            == ["2. Kettle On", "3. Ferry Lights"])
        #expect((pdf.documentAttributes?[PDFDocumentAttribute.keywordsAttribute] as? [String])
            == ["songbook"])
        try Support.writePages(pdf, name: "songbook")
    }

    @Test
    func `a library selection prints a contents page in the given order with no times`(
    ) async throws {
        let songs = [
            Support.record("{title: Kettle On}\n{key: D}\n[D]Put the kettle on\n", index: 2),
            Support.record(Support.harbour, index: 1),
        ]
        let output = try await Support.make(Support.snapshot(.selection(songs)), Support.options())
        let pdf = output.pdf
        let contents = Support.text(pdf, page: 0)
        #expect(contents.contains("Songbook"))
        #expect(contents.contains("2 songs"))
        #expect(!contents.contains(":"), "no times on a selection: \(contents)")
        let kettle = try #require(contents.range(of: "Kettle On"))
        let harbour = try #require(contents.range(of: "Harbour Lights"))
        #expect(kettle.lowerBound < harbour.lowerBound)
        #expect(output.document.fileName == "Songbook (2 songs).pdf")
        #expect(Support.text(pdf, page: 1).contains("Songbook"))
        #expect(!Support.text(pdf, page: 1).contains("1 of 2"))
        try Support.writePages(pdf, name: "selection")
    }
}

/// The Bass notes part (P8-4 11.5 moved here, spec 5.7, R161, R175).
@MainActor
@Suite(.serialized)
struct PDFBassChartTests {
    typealias Support = PDFTestSupport

    static let source = "{title: Hello}\n{key: G}\n{capo: 2}\n[G]Hello [G/B]there [C]friend\n"

    @Test
    func `the bass part prints sounding notes, the sounding key and the scale line`() async throws {
        let record = Support.record(Self.source)
        let output = try await Support.make(Support.snapshot(.song(record)), Support.options(.bass))
        let text = Support.allText(output.pdf)
        #expect(text.contains("A"))
        #expect(text.contains("C#"))
        #expect(text.contains("D"))
        #expect(!text.contains("G/B"))
        #expect(!text.contains("capo"))
        #expect(text.contains("Sounding A major"))
        #expect(output.document.fileName == "Hello (Bass).pdf")
        #expect(output.diagrams.isEmpty, "bass charts print no chord diagrams")
        let keywords = output.pdf
            .documentAttributes?[PDFDocumentAttribute.keywordsAttribute] as? [String]
        #expect(keywords?.contains("bass chart") == true)
        // The Chords part is untouched by the bass code.
        let chords = try await Support.make(Support.snapshot(.song(record)), Support.options())
        #expect(Support.allText(chords.pdf).contains("G/B"))
    }

    @Test
    func `a slot key override prints the overridden sounding notes`() async throws {
        let record = Support.record(Self.source)
        let entry = SetlistEntry(
            itemId: Support.item(0),
            songId: record.id,
            overrides: SetlistOverrides(transpose: 2),
        )
        let setlist = Setlist(id: Support.setlistID(), name: "Gig", entries: [entry])
        let output = try await Support.make(
            Support.snapshot(.slot(PDFSlotSnapshot(
                setlist: setlist,
                entry: entry,
                record: record,
                number: 1,
                total: 1,
            ))),
            Support.options(.bass),
        )
        let text = Support.allText(output.pdf)
        #expect(text.contains("B"))
        #expect(text.contains("D#"))
        #expect(text.contains("1 of 1"))
    }

    @Test
    func `saved fills print as names, and as a tab with Fills as tab`() async throws {
        var record = Support.record(StageWindowSuites.StageFillTests.song)
        record.sidecar.parts = try StageWindowSuites.StageFillTests.parts(record)
        let snapshot = Support.snapshot(.song(record))
        let names = try await Support.make(
            snapshot,
            Support.options(.bass) { $0.fillsAsTab = false },
        )
        let named = Support.allText(names.pdf)
        #expect(named.contains("\u{203A}"), "a fill's run ends in › into its landing")
        let tabs = try await Support.make(snapshot, Support.options(.bass) { $0.fillsAsTab = true })
        let plan = try #require({ () -> LiveLayoutPlanBox? in
            if case let .song(page) = tabs.document
                .pages[0]
            {
                return LiveLayoutPlanBox(plan: page.plan)
            }
            return nil
        }())
        #expect(plan.fillTabs >= 2, "both fills draw as tabs")
        try Support.writePages(names.pdf, name: "bass-fills-names")
        try Support.writePages(tabs.pdf, name: "bass-fills-tab")
    }

    @Test
    func `walk-ups print per the density`() async throws {
        let record = Support.record(Support.harbour)
        var profile = InstrumentProfile()
        profile.walkUps = .sections
        let output = try await Support.make(
            Support.snapshot(.song(record), profile: profile),
            Support.options(.bass),
        )
        let plan = try #require({ () -> LiveLayoutPlanBox? in
            if case let .song(page) = output.document
                .pages[0]
            {
                return LiveLayoutPlanBox(plan: page.plan)
            }
            return nil
        }())
        #expect(plan.walkUps > 0)
        let off = try await Support.make(Support.snapshot(.song(record)), Support.options(.bass))
        let none = try #require({ () -> LiveLayoutPlanBox? in
            if case let .song(page) = off.document
                .pages[0]
            {
                return LiveLayoutPlanBox(plan: page.plan)
            }
            return nil
        }())
        #expect(none.walkUps == 0)
        try Support.writePages(output.pdf, name: "bass-chart")
    }
}

/// Counts in a printed plan.
struct LiveLayoutPlanBox {
    let plan: LiveLayout.LayoutPlan

    var fillTabs: Int {
        plan.columns.flatMap(\.blocks).flatMap(\.allRows).count { $0.fillTab != nil }
    }

    var walkUps: Int {
        plan.columns.flatMap(\.blocks).flatMap(\.allRows).flatMap(\.chords)
            .count { $0.role == .approach && $0.fill == nil }
    }
}
