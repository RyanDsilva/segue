import ChordPro
import Editing
import Foundation
import Library
import LiveLayout
import PDFKit
import Printing
@testable import SegueUI
import Setlists
import Support
import Testing

/// Medley slots in PDFs (P9-1 spec 9, 14.3; R178, R193), read back with PDFKit: the set list's
/// "5" row with "5a", "5b" under it, the outline nesting, "Medley 2 · 2 of 3", members flowing
/// on with no page break, each later member opening with the stage's member header and its
/// transition, member links landing on that header, and a single medley or member export.
@MainActor
@Suite(.serialized, .timeLimit(.minutes(1)))
struct PrintMedleyTests {
    typealias Support = PDFTestSupport

    static let kettle = Support.record(
        "{title: Kettle On}\n{artist: Segue Originals}\n{key: D}\n{tempo: 90}\n"
            + "{start_of_verse}\n[D]Put the [G]kettle on\n[A]Pour another [D]cup\n"
            + "{end_of_verse}\n",
        index: 20,
    )
    static let ferry = Support.record(
        "{title: Ferry Lights}\n{key: A}\n{tempo: 120}\n{start_of_verse}\n"
            + "[A]Ferry lights [E]over the bay\n[D]Carry me [A]home today\n{end_of_verse}\n"
            + "{start_of_chorus}\n[D]Ferry [E]lights\n[A]Home tonight\n{end_of_chorus}\n",
        index: 21,
    )
    static let lantern = Support.record(
        "{title: Lantern Song}\n{artist: The Quay Band}\n{key: G}\n{capo: 2}\n{tempo: 96}\n"
            + "{start_of_verse}\n[G]Light the [C]lantern\n[D]Hold it [G]high\n{end_of_verse}\n",
        index: 22,
    )
    static let harbour = Support.record(Support.harbour, index: 23)
    static let kitaabon = Support.record(
        StageWindowSuites.SingerViewSnapshotTests.kitaabon,
        index: 24,
    )

    static func member(_ index: Int, _ record: SongRecord, transition: String? = nil)
        -> MedleyMember
    {
        MedleyMember(itemId: Support.item(40 + index), songId: record.id, transition: transition)
    }

    /// Kettle On, then medley 2: Ferry Lights, Lantern Song (into it: "Hold the D"), Kettle
    /// On's reprise is not needed; a short three-member medley fits one page.
    static func set(_ members: [SongRecord], title: String? = nil) -> (
        Setlist, [SongID: SongRecord],
    ) {
        let medley = SetlistMedley(title: title, members: members.enumerated().map { index, song in
            member(index, song, transition: index == 1 ? "Hold the D, drums fill" : nil)
        })
        let setlist = Setlist(id: Support.setlistID(), name: "Friday Set", entries: [
            SetlistEntry(itemId: Support.item(30), songId: kettle.id),
            SetlistEntry(itemId: Support.item(31), medley: medley),
        ])
        var records = [kettle.id: kettle]
        for song in members {
            records[song.id] = song
        }
        return (setlist, records)
    }

    static func songPages(_ document: PrintDocument) -> [SongPage] {
        document.pages.compactMap { page in
            if case let .song(song) = page {
                return song
            }
            return nil
        }
    }

    @Test
    func `a medley prints as one row with lettered members, flowing on one page`() async throws {
        let (setlist, records) = Self.set([Self.ferry, Self.lantern, Self.kitaabon])
        let output = try await Support.make(
            Support.snapshot(.setlist(setlist, records)),
            Support.options(),
        )
        let pdf = output.pdf
        let list = Support.text(pdf, page: 0)
        for text in [
            "Medley: Ferry Lights / Lantern Song / Kitaabon Wali Gali", "2a", "2b", "2c",
            "Ferry Lights", "Lantern Song", "4 songs",
        ] {
            #expect(list.contains(text), "the set list lacks \(text)")
        }
        // Kettle On on page 2; the medley from page 3, its members flowing on.
        let pages = Self.songPages(output.document)
        let medley = pages.filter { $0.song == 1 }
        #expect(medley.first?.header.title == "Ferry Lights")
        #expect(medley.first?.header.slotLabel == "Medley 2 \u{00B7} 1 of 3")
        let first = Support.text(pdf, page: 2)
        #expect(first.contains("Medley 2 \u{00B7} 1 of 3"))
        #expect(first.contains("Lantern Song"))
        #expect(first.contains("2 of 3"))
        #expect(first.contains("Hold the D, drums fill"))
        // Members flow on: the second member's header shares the first member's page.
        let headers = medley.flatMap { page in
            page.plan.columns.flatMap(\.blocks).compactMap(\.memberHeader)
        }
        #expect(headers.map(\.header.title) == ["Lantern Song", "Kitaabon Wali Gali"])
        #expect(headers.first?.header.transition == "Hold the D, drums fill")
        let firstMemberPages = Set(medley.enumerated().compactMap { offset, page in
            page.plan.columns.flatMap(\.blocks).contains { $0.segment == 0 } ? offset : nil
        })
        let secondHeaderPage = medley.firstIndex { page in
            page.plan.columns.flatMap(\.blocks).contains { $0.memberHeader != nil }
        }
        #expect(secondHeaderPage.map { firstMemberPages.contains($0) } == true)
        // The page header's map line names the first member's passes only (R193).
        #expect(medley.first?.header.mapLines.joined().contains("Br") == false)
        try Support.writePages(pdf, name: "medley-songbook", folder: PrintLyricsTests.folder)
    }

    @Test
    func `the outline nests members and their links land on each member header`() async throws {
        let (setlist, records) = Self.set([Self.harbour, Self.lantern, Self.ferry])
        let output = try await Support.make(
            Support.snapshot(.setlist(setlist, records)),
            Support.options(.chords, paper: .letter) { $0.size = .large },
        )
        let pdf = output.pdf
        let root = try #require(pdf.outlineRoot)
        let titles = (0 ..< root.numberOfChildren).compactMap { root.child(at: $0)?.label }
        #expect(titles == ["Set list", "1. Kettle On", "2. Medley"])
        let medley = try #require(root.child(at: 2))
        let members = (0 ..< medley.numberOfChildren).compactMap { medley.child(at: $0) }
        #expect(members.compactMap(\.label)
            == ["2a. Harbour Lights", "2b. Lantern Song", "2c. Ferry Lights"])
        // 2b lands on its header's point, below the page top, on the page that draws it.
        let lantern = try #require(members.dropFirst().first?.destination)
        let lanternPage = try #require(lantern.page)
        let height = lanternPage.bounds(for: .mediaBox).height
        #expect(lantern.point.y < height - PrintPageMetrics.top)
        #expect(lanternPage.string?.contains("Lantern Song") == true)
        // The set list row's link goes to the same point.
        let links = try #require(pdf.page(at: 0)).annotations.filter { $0.type == "Link" }
        let rowLink = links.first { link in
            link.destination?.page == lanternPage && link.destination?.point == lantern.point
        }
        #expect(rowLink != nil, "no set list link to 2b's header")
        // A continuation page names the member at its top (spec 9).
        let pages = Self.songPages(output.document).filter { $0.song == 1 }
        #expect(pages.count > 1)
        for page in pages.dropFirst() {
            let top = page.plan.columns.first?.blocks.first?.segment ?? 0
            let expected = ["Harbour Lights", "Lantern Song", "Ferry Lights"][top]
            #expect(page.header.title == expected)
            #expect(page.header.slotLabel == "Medley 2 \u{00B7} \(top + 1) of 3")
        }
        #expect(Support.text(pdf, page: 3).contains("(cont.)"))
        // A member header never ends a column: it keeps at least two lines with it.
        for page in pages {
            for block in page.plan.columns.flatMap(\.blocks) where block.memberHeader != nil {
                guard case let .rows(rows) = block.content else { continue }
                #expect(rows.count >= 2, "a member header orphaned at a column foot")
            }
        }
        try Support.writePages(pdf, name: "medley-long", folder: PrintLyricsTests.folder)
    }

    @Test
    func `a medley or one member exports alone`() async throws {
        let (setlist, records) = Self.set([Self.ferry, Self.lantern], title: "Harbour Medley")
        let entry = try #require(setlist.entries.last)
        let alone = try await Support.make(
            Support.snapshot(.slot(PDFSlotSnapshot(
                setlist: setlist,
                entry: entry,
                record: nil,
                number: 2,
                total: 2,
                records: records,
            ))),
            Support.options(),
        )
        #expect(alone.document.fileName == "Harbour Medley.pdf")
        let text = Support.allText(alone.pdf)
        #expect(text.contains("Ferry Lights"))
        #expect(text.contains("Lantern Song"))
        #expect(text.contains("Medley 2 \u{00B7} 1 of 2"))
        #expect(!text.contains("Set list"))
        try Support.writePages(alone.pdf, name: "medley-slot", folder: PrintLyricsTests.folder)

        let member = try #require(entry.medley?.members.last)
        let one = try await Support.make(
            Support.snapshot(.slot(PDFSlotSnapshot(
                setlist: setlist,
                entry: member.asSlot,
                record: Self.lantern,
                number: 2,
                total: 2,
                label: "Medley 2 \u{00B7} 2 of 2",
            ))),
            Support.options(),
        )
        let memberText = Support.allText(one.pdf)
        #expect(memberText.contains("Lantern Song"))
        #expect(memberText.contains("Medley 2 \u{00B7} 2 of 2"))
        #expect(!memberText.contains("Ferry Lights"))
    }

    @Test
    func `a medley's lyric sheet shows sounding keys and no chords`() async throws {
        let (setlist, records) = Self.set([Self.ferry, Self.lantern])
        let output = try await Support.make(
            Support.snapshot(.setlist(setlist, records)),
            Support.options(.lyrics),
        )
        let text = Support.allText(output.pdf)
        // Lantern Song is G with capo 2: it sounds in A, and says so without a capo.
        #expect(text.contains("Key A"))
        #expect(!text.contains("capo"))
        #expect(text.contains("Light the lantern"))
        #expect(!text.contains("[G]"))
        #expect(output.job.songs[1].request.view == .singer)
        #expect(output.job.songs[1].request.resolvedSegments.allSatisfy { $0.walkUps == nil })
    }
}
