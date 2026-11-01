import ChordPro
import Editing
import Library
import LiveLayout
import PDFKit
import Printing
@testable import SegueUI
import Setlists
import Shows
import Testing

/// Print requests match the stage (P9-1 spec decision 2, 14.1): the same model, passes, modes,
/// overrides, walk-ups and fills; only style, zoom, notes and diagrams differ.
@MainActor
struct PrintRequestParityTests {
    typealias Support = PDFTestSupport

    @Test
    func `a slot's print request lays out like the stage's`() throws {
        var record = Support.record(StageWindowSuites.StageFillTests.song)
        record.sidecar.parts = try StageWindowSuites.StageFillTests.parts(record)
        let units = SongSections.units(of: record.document)
        let arrangement = SlotArrangement(passes: [
            ArrangementPass(anchor: units[0].anchor),
            ArrangementPass(anchor: units[1].anchor),
            ArrangementPass(anchor: units[0].anchor, mode: .chordsOnly),
            ArrangementPass(anchor: units[1].anchor, mode: .firstLine),
        ])
        let entry = SetlistEntry(
            itemId: Support.item(0),
            songId: record.id,
            overrides: SetlistOverrides(transpose: 2),
            arrangement: arrangement,
        )
        var profile = InstrumentProfile()
        profile.bassNotes = true
        let slot = StageSlot(entry)
        let stage = StageRequest.make(
            song: record,
            slot: slot,
            prefs: LivePrefs(),
            settings: LiveSettings(),
            minLyricSize: 22,
            viewport: LayoutSize(width: 1200, height: 800),
            bass: profile.bassView,
        ).request
        let options = Support.options(.bass) { $0.fillsAsTab = profile.fillsAsTab }
        let print = PrintRequests.song(
            record,
            slot: slot,
            snapshot: Support.snapshot(.song(record), profile: profile),
            options: options,
        ).request
        #expect(print.model == stage.model)
        #expect(print.passes == stage.passes)
        #expect(print.passes?.map(\.mode) == [.full, .full, .chordsOnly, .firstLine])
        #expect((print.walkUps != nil) == (stage.walkUps != nil))
        #expect(print.walkUps != nil, "the saved fills draw in the bass part")
        #expect(print.notes.isEmpty && print.cues.isEmpty)
        // Laid out with one style, the two requests give the same rows.
        #expect(Self.rows(print) == Self.rows(stage))
    }

    /// The rows of `request` laid out at one fixed print style.
    static func rows(_ request: LayoutRequest) -> [[String]] {
        var request = request
        request.style = .print(lyricSize: 12)
        request.viewport = LayoutSize(width: 540, height: 2000)
        request.minLyricSize = 12
        request.zoom = 1
        request.columns = 1
        return LayoutEngine.plan(request, metrics: StageTextMetrics()).columns
            .flatMap(\.blocks).map { block in
                block.labelLines.map(\.text.text) + block.allRows.map { row in
                    (row.chords + row.text).map(\.text).joined(separator: " ")
                }
            }
    }

    @Test
    func `stage notes and cues print only when the export includes them`() {
        var record = Support.record(Support.harbour)
        record.sidecar.notes = "Count in four"
        let entry = SetlistEntry(itemId: Support.item(0), songId: record.id, note: "Capo on 2")
        let snapshot = Support.snapshot(.song(record))
        let off = PrintRequests.song(
            record,
            slot: StageSlot(entry),
            snapshot: snapshot,
            options: Support.options(),
        )
        #expect(off.request.notes.isEmpty)
        let on = PrintRequests.song(
            record,
            slot: StageSlot(entry),
            snapshot: snapshot,
            options: Support.options { $0.stageNotes = true },
        )
        #expect(on.request.notes == ["Count in four", "Capo on 2"])
    }
}

/// Single charts through the whole path, read back with PDFKit (spec 14.2).
@MainActor
@Suite(.serialized)
struct PDFExportTests {
    typealias Support = PDFTestSupport

    @Test
    func `a single chart has its header, footer, chords and pages`() async throws {
        let record = Support.record(Support.harbour)
        let output = try await Support.make(Support.snapshot(.song(record)), Support.options())
        let pdf = output.pdf
        #expect(pdf.pageCount == output.document.pages.count)
        let box = try #require(pdf.page(at: 0)).bounds(for: .mediaBox)
        #expect(box.size == CGSize(width: 612, height: 792))
        let first = Support.text(pdf, page: 0)
        #expect(first.contains("Harbour Lights"))
        #expect(first.contains("Mira Sol, The Quay Band \u{00B7} Low Tide"))
        #expect(first.contains("G, capo 2, 96"))
        #expect(first
            .contains("Intro \u{00B7} V1 \u{00B7} Ch \u{00B7} V2 \u{00B7} Ch 2/3 \u{00B7} Br"))
        #expect(first.contains("Page 1 of \(pdf.pageCount)"))
        #expect(first.contains("Lanterns on the"))
        #expect(first.contains("D/F#"))
        // Chart comments always print; there is no branding.
        #expect(Support.allText(pdf).contains("Hold the last chord"))
        #expect(!Support.allText(pdf).contains("Segue"))
        #expect(output.document.fileName == "Harbour Lights.pdf")
        let attributes = pdf.documentAttributes ?? [:]
        #expect(attributes[PDFDocumentAttribute.titleAttribute] as? String == "Harbour Lights")
        #expect(attributes[PDFDocumentAttribute.authorAttribute] as? String ==
            "Mira Sol, The Quay Band")
        #expect(attributes[PDFDocumentAttribute.creatorAttribute] as? String == "Segue")
        try Support.writePages(pdf, name: "chart-letter")
    }

    @Test
    func `a long song splits with a continuation header and never splits a line pair`(
    ) async throws {
        var lines = ["{title: Long Road}", "{start_of_verse: Verse 1}"]
        lines += (1 ... 70).map { "[G]Line number \($0) of the [C]long road [D]home" }
        lines.append("{end_of_verse}")
        let record = Support.record(lines.joined(separator: "\n"))
        let output = try await Support.make(
            Support.snapshot(.song(record)),
            Support.options(paper: .a4) { $0.columns = .one },
        )
        let pdf = output.pdf
        #expect(pdf.pageCount >= 2)
        #expect(try #require(pdf.page(at: 0)).bounds(for: .mediaBox).size == CGSize(
            width: 595,
            height: 842,
        ))
        let second = Support.text(pdf, page: 1)
        #expect(second.contains("Long Road (cont.)"))
        #expect(second.contains("(cont.)"))
        #expect(second.contains("Page 2 of \(pdf.pageCount)"))
        // Each lyric's chords sit on the lyric's page: every page's lines are whole.
        for line in 1 ... 70 {
            let pages = (0 ..< pdf.pageCount).filter {
                Support.text(pdf, page: $0).contains("Line number \(line) of the")
            }
            #expect(pages.count == 1, "line \(line) on \(pages)")
        }
        try Support.writePages(pdf, name: "long-a4")
    }

    @Test
    func `transposed and Nashville songs print their display chords`() async throws {
        var record = Support.record("{title: T}\n{key: G}\n[G]One [C]two [D]three\n")
        record.sidecar.displayPrefs.transpose = 2
        let transposed = try await Support.make(Support.snapshot(.song(record)), Support.options())
        let text = Support.allText(transposed.pdf)
        #expect(text.contains("A") && text.contains("D") && text.contains("E"))
        #expect(!text.contains("G "))
        var nashville = Support.record("{title: N}\n{key: G}\n[G]One [C]two [D]three\n")
        nashville.sidecar.displayPrefs.nashville = true
        let numbers = try await Support.make(Support.snapshot(.song(nashville)), Support.options())
        #expect(Support.allText(numbers.pdf).contains("4"))
        #expect(Support.allText(numbers.pdf).contains("5"))
    }

    @Test
    func `devanagari lyrics print as selectable text`() async throws {
        let record = Support.record("{title: Gali}\n[Am]किताबों वाली [G]गली में\n")
        let output = try await Support.make(Support.snapshot(.song(record)), Support.options())
        #expect(Support.allText(output.pdf).contains("गली"))
    }

    @Test
    func `diagrams print per the option and stage notes stay off by default`() async throws {
        var record = Support.record(Support.harbour)
        record.sidecar.notes = "Count in four"
        let off = try await Support.make(
            Support.snapshot(.song(record)),
            Support.options { $0.diagrams = .off },
        )
        #expect(off.document.pages.allSatisfy { page in
            if case let .song(song) = page {
                return song.extras.isEmpty
            }
            return true
        })
        #expect(!Support.allText(off.pdf).contains("Count in four"))
        let all = try await Support.make(
            Support.snapshot(.song(record)),
            Support.options {
                $0.diagrams = .all
                $0.stageNotes = true
            },
        )
        let extras = all.document.pages.flatMap { page -> [PlacedExtra] in
            if case let .song(song) = page {
                return song.extras
            }
            return []
        }
        #expect(extras.count == 1)
        #expect(all.diagrams[0]?.diagrams.isEmpty == false)
        #expect(Support.allText(all.pdf).contains("Count in four"))
        try Support.writePages(all.pdf, name: "chart-diagrams-notes")
    }

    @Test
    func `a page stays light paper with red chords while the app is dark`() async throws {
        let previous = NSApp?.appearance
        NSApp?.appearance = NSAppearance(named: .darkAqua)
        defer { NSApp?.appearance = previous }
        let record = Support.record("{title: Light}\n[G]Lanterns on the water\n")
        let output = try await Support.make(Support.snapshot(.song(record)), Support.options())
        let image = try Support.image(output.pdf, page: 0)
        let paper = try Support.pixel(image, at: CGPoint(x: 300, y: 600))
        #expect(paper.red > 245 && paper.green > 245 && paper.blue > 245, "\(paper)")
        // The chords are the page's only red: find the reddest pixel of the body.
        var reddest = Support.RGB(red: 0, green: 255, blue: 255)
        let bitmap = try Support.bitmap(image)
        for y in stride(from: 40.0, to: 200, by: 1) {
            for x in stride(from: 36.0, to: 300, by: 1) {
                let sample = try Support.pixel(bitmap, at: CGPoint(x: x, y: y))
                if sample.red - sample.green > reddest.red - reddest.green {
                    reddest = sample
                }
            }
        }
        #expect(reddest.red > 150 && reddest.green < 90, "\(reddest)")
    }
}
