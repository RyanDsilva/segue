import PDFKit
import XCTest

/// PDF export end to end (P9-1 spec 14.5): a fresh library with a seeded 3-song setlist with
/// a break; the builder's Setlist menu > Export PDF...; the sheet reads "Songbook PDF · 3
/// songs" with its pages; Chart > Bass notes updates the label; Save PDF... writes the file at
/// `-SegueExportPath`, which opens as a PDF with the page count shown; Print... brings up
/// the system print panel, which is cancelled; Done closes the sheet. The sheet's Help button
/// opens the guide's Print and PDF page.
final class SeguePDFExportE2ETests: SetlistE2ETestCase {
    private static let setlistID = "01JC0000000000000000000P91"
    private static let titles = ["Harbor Lights", "Paper Boats", "Northbound"]

    @MainActor
    func testSongbookPreviewSaveAndPrint() throws {
        let root = try XCTUnwrap(libraryRoot)
        try seedSetlist(root)
        let output = root.appending(path: ".e2e-out/Friday Set.pdf")
        try FileManager.default.createDirectory(
            at: output.deletingLastPathComponent(),
            withIntermediateDirectories: true,
        )
        let app = try launch(arguments: ["-SegueExportPath", output.path(percentEncoded: false)])

        // The builder's Setlist menu > Export PDF...
        SetlistE2E.element(app, PDFAXID.sidebarSetlists).click(in: app)
        let row = SetlistE2E.element(app, SetlistAXID.setlistRow)
        XCTAssertTrue(row.appears(timeout: 10), "the setlist is not listed")
        row.click(in: app)
        E2E.bringToFront(app)
        let menu = SetlistE2E.element(app, SetlistAXID.setlistMenu)
        XCTAssertTrue(menu.appears(timeout: 10), "no Setlist menu in the builder")
        menu.click(in: app)
        let export = app.menuItems[PDFAXID.exportSetlist].firstMatch
        XCTAssertTrue(export.appears(timeout: 5), "no Export PDF... in the Setlist menu")
        export.click(in: app)

        // The sheet: "Songbook PDF · 3 songs", then its pages.
        let sheet = SetlistE2E.element(app, PDFAXID.sheet)
        XCTAssertTrue(sheet.appears(timeout: 10), "the PDF preview never opened")
        let subtitle = SetlistE2E.element(app, PDFAXID.subtitle)
        SetlistE2E.waitUntil("the sheet never counted its pages", timeout: 20) {
            let text = SetlistE2E.text(subtitle)
            return text.hasPrefix("Songbook PDF \u{00B7} 3 songs") && text.hasSuffix("pages")
        }
        let chordsLabel = SetlistE2E.text(subtitle)
        screenshot(app, "pdf-songbook")

        // The Help button opens the guide's Print and PDF page (recorded, never opened).
        let help = SetlistE2E.element(app, PDFAXID.help)
        XCTAssertTrue(help.appears(timeout: 5), "no Help button in the sheet")
        help.click(in: app)
        SetlistE2E.waitForDisk("Help never opened the Print and PDF page") {
            try String(contentsOf: Self.workspaceLog(root), encoding: .utf8)
                .contains("guide/print-and-pdf")
        }

        // Chart > Bass notes: the label updates.
        let part = SetlistE2E.element(app, PDFAXID.option("part"))
        let bass = part.radioButtons["Bass notes"].exists
            ? part.radioButtons["Bass notes"] : part.buttons["Bass notes"]
        XCTAssertTrue(bass.appears(timeout: 5), "no Bass notes in the Chart picker")
        bass.click(in: app)
        SetlistE2E.waitUntil("the label never showed the Bass notes part", timeout: 20) {
            let text = SetlistE2E.text(subtitle)
            return text != chordsLabel && text.contains("Bass notes") && text.hasSuffix("pages")
        }
        let save = app.buttons[PDFAXID.save].firstMatch
        SetlistE2E.waitUntil("Save PDF... never enabled", timeout: 20) { save.isEnabled }
        let indicator = SetlistE2E.element(app, PDFAXID.pageIndicator)
        let pages = try XCTUnwrap(
            SetlistE2E.text(indicator).split(separator: " ").last.flatMap { Int($0) },
            "no page count in \(SetlistE2E.text(indicator))",
        )

        // Save PDF... writes the test path; the file opens with the pages shown.
        save.click(in: app)
        SetlistE2E.waitForDisk("Save PDF... never wrote \(output.lastPathComponent)") {
            PDFDocument(url: output)?.pageCount == pages
        }

        // Print... shows the system print panel; Cancel; Done.
        let print = app.buttons[PDFAXID.print].firstMatch
        print.click(in: app)
        let cancel = app.sheets.buttons["Cancel"].firstMatch
        XCTAssertTrue(cancel.appears(timeout: 15), "the print panel never opened")
        screenshot(app, "pdf-print-panel")
        cancel.click(in: app)
        XCTAssertTrue(cancel.disappears(timeout: 10), "the print panel stayed open")
        app.buttons[PDFAXID.done].firstMatch.click(in: app)
        XCTAssertTrue(sheet.disappears(timeout: 10), "Done never closed the sheet")
    }

    // MARK: - Seed

    /// "Friday Set": Harbor Lights, a break "Set 2", Paper Boats, Northbound.
    private func seedSetlist(_ root: URL) throws {
        func slot(_ index: Int, _ title: String) -> String {
            #"{"itemId": "01JC0000000000000000000P0\#(index)", "#
                + #""songId": "\#(SetlistFixture.song(title).id)"}"#
        }
        let rows = [
            slot(1, Self.titles[0]),
            #"{"itemId": "01JC0000000000000000000P02", "break": {"label": "Set 2"}}"#,
            slot(3, Self.titles[1]),
            slot(4, Self.titles[2]),
        ]
        try SetlistFixture.write(
            #"{"schemaVersion": 6, "id": "\#(Self.setlistID)", "name": "Friday Set", "#
                + #""entries": [\#(rows.joined(separator: ", "))]}"#,
            to: root.appending(path: "setlists/friday-set.setlist.json"),
        )
    }
}

/// Mirrors `AccessibilityID` (SegueUI) for the PDF flow.
private enum PDFAXID {
    static let sidebarSetlists = "segue.sidebar.setlists"
    static let sheet = "segue.pdf.sheet"
    static let subtitle = "segue.pdf.subtitle"
    static let pageIndicator = "segue.pdf.pageIndicator"
    static let save = "segue.pdf.save"
    static let print = "segue.pdf.print"
    static let done = "segue.pdf.done"
    static let exportSetlist = "segue.pdf.export.setlist"
    static let help = "segue.guideHelp.pdf"

    static func option(_ name: String) -> String {
        "segue.pdf.option.\(name)"
    }
}
