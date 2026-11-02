import AppKit
import XCTest

/// The guide's 1.0 captures: medleys, the bass profile (stage, walk-up picker, fill editor)
/// and PDF export. An extension of `GuideShots` so `make docs-shots` runs them with the rest
/// (`-only-testing:SegueAppStoreUITests/GuideShots`).
@MainActor
extension GuideShots {
    /// Medleys: medley-builder (the first three songs of the Welcome Set made a medley, a
    /// transition into the second) and medley-stage (on stage, the second song's header and
    /// transition, the map grouped by song).
    func testMedleys() {
        let app = launch()
        let window = mainWindow(app)
        openSetlist(app, "Welcome Set")
        app.typeKey("2", modifierFlags: .command, in: app)
        let entries = app.descendants(matching: .any).matching(identifier: Phase9AXID.setlistEntry)
        XCTAssertTrue(
            E2E.waitUntil(timeout: 10) { entries.count == 4 },
            "the Welcome Set never listed its four slots",
        )
        entries.element(boundBy: 0).click(in: app)
        // Close the slot popover the plain click opened, then Shift-click the third row.
        app.typeKey(.escape, modifierFlags: [], in: app)
        XCUIElement.perform(withKeyModifiers: .shift) {
            entries.element(boundBy: 2).click()
        }
        app.typeKey("m", modifierFlags: [.command, .shift], in: app)
        _ = element(app, Phase9AXID.medley)
        let count = element(app, Phase9AXID.medleySongCount)
        XCTAssertTrue(
            E2E.waitUntil(timeout: 10) { Self.text(count) == "3 songs" },
            "the medley reads \(Self.text(count)), not 3 songs",
        )
        element(app, Phase9AXID.medleyTransition).click(in: app)
        let field = app.textFields[Phase9AXID.medleyTransition].firstMatch
        XCTAssertTrue(field.appears(timeout: 5), "the transition field never opened")
        field.typeText("Hold the G, drums fill\n", in: app)
        XCTAssertTrue(field.disappears(timeout: 5), "the transition field stayed open")
        // Return hands the focus to the set assistant's field: a click on the empty list
        // below the set takes it (and its focus ring) away.
        window.coordinate(withNormalizedOffset: CGVector(dx: 0.6, dy: 0.95)).click()
        shoot("medley-builder", window, callouts: ["medley": element(app, Phase9AXID.medley)])

        element(app, GuideAXID.setlistStartShow).click(in: app)
        element(app, GuideAXID.checklistStart).click(in: app)
        XCTAssertTrue(app.staticTexts[GuideAXID.liveTitle].appears(timeout: 10))
        let chip = element(app, Phase9AXID.liveMedley)
        app.typeKey(.rightArrow, modifierFlags: [], in: app)
        XCTAssertTrue(
            E2E.waitUntil(timeout: 10) { Self.text(chip).contains("2 of 3") },
            "the stage never reached the medley's second song (\(Self.text(chip)))",
        )
        _ = element(app, Phase9AXID.liveMemberTransition)
        shoot("medley-stage", stageWindow(app), stage: true)
        endShow(app)
    }

    /// The bass profile: bass-stage (the stage in the bass-note view, scale line and mini
    /// neck), walk-up-popover (the picker for G to C in Kitaabon Wali Gali) and fill-editor
    /// (a fill from the verse's last line into the chorus).
    func testBass() {
        let app = launch()
        turnOnBass(app)

        openSetlist(app, "Welcome Set")
        element(app, GuideAXID.setlistStartShow).click(in: app)
        element(app, GuideAXID.checklistStart).click(in: app)
        XCTAssertTrue(app.staticTexts[GuideAXID.liveTitle].appears(timeout: 10))
        _ = element(app, Phase9AXID.liveBassScale)
        _ = element(app, Phase9AXID.liveBassNeck)
        shoot("bass-stage", stageWindow(app), stage: true)
        endShow(app)

        app.descendants(matching: .any)[Phase9AXID.sidebarLibrary].firstMatch.click(in: app)
        song(app, titled: "Kitaabon Wali Gali").click(in: app)
        element(app, GuideAXID.editSong).click(in: app)
        _ = element(app, GuideAXID.editorVisual)
        walkUpPicker(app)

        // The fill, from the library's preview (the editor's is a short pane under the
        // text): F (the verse's last line) to F (the chorus's first).
        element(app, Phase9AXID.editorDone).click(in: app)
        song(app, titled: "Kitaabon Wali Gali").click(in: app)
        chordAtLineStart(app, lyric: "kadam.").click()
        let landing = chordAtLineStart(app, lyric: "rahi,")
        XCUIElement.perform(withKeyModifiers: .shift) { landing.click() }
        _ = element(app, Phase9AXID.fillCreate)
        app.typeKey("f", modifierFlags: [.command, .option], in: app)
        let editor = element(app, Phase9AXID.fillEditor)
        for letter in ["a", "b", "c", "d"] {
            _ = element(app, Phase9AXID.fillCandidate(letter))
        }
        _ = element(app, Phase9AXID.fillMiniTab)
        // The sheet opens with the Tempo field focused: a click on the suggested option (it
        // is already the highlighted one) takes the focus ring off it.
        element(app, Phase9AXID.fillCandidate("a")).click(in: app)
        shoot("fill-editor", app.sheets.firstMatch.exists ? app.sheets.firstMatch : editor)
        app.typeKey(.escape, modifierFlags: [], in: app)
    }

    /// PDF export: pdf-preview (one song's preview sheet) and pdf-songbook (the Welcome Set
    /// songbook's set list page, with a break).
    func testPDF() {
        let app = launch()
        song(app, titled: "Kettle On, Lights Low").click(in: app)
        app.typeKey("e", modifierFlags: [.command, .shift], in: app)
        let sheet = element(app, Phase9AXID.pdfSheet)
        waitForPages(app, prefix: "Song PDF")
        shoot("pdf-preview", app.sheets.firstMatch.exists ? app.sheets.firstMatch : sheet)
        element(app, Phase9AXID.pdfDone).click(in: app)
        XCTAssertTrue(sheet.disappears(timeout: 10), "the PDF preview stayed open")

        openSetlist(app, "Welcome Set")
        app.typeKey("2", modifierFlags: .command, in: app)
        let kitaabon = app.staticTexts.matching(identifier: GuideAXID.entryTitle)
            .matching(NSPredicate(
                format: "label CONTAINS %@ OR value CONTAINS %@",
                "Kitaabon",
                "Kitaabon",
            )).firstMatch
        XCTAssertTrue(kitaabon.appears(timeout: 10))
        XCUIElement.perform(withKeyModifiers: .command) { kitaabon.click() }
        app.typeKey("b", modifierFlags: [.command, .shift], in: app)
        _ = element(app, GuideAXID.setlistBreak)
        element(app, Phase9AXID.setlistMenu).click(in: app)
        let export = app.menuItems[Phase9AXID.pdfExportSetlist].firstMatch
        XCTAssertTrue(export.appears(timeout: 5), "no Export PDF... in the Setlist menu")
        export.click(in: app)
        _ = element(app, Phase9AXID.pdfSheet)
        waitForPages(app, prefix: "Songbook PDF")
        // The pages pane right of the options column, title bar and footer excluded (the
        // PDF view itself has no accessibility element to capture).
        let preview = app.sheets.firstMatch.exists ? app.sheets.firstMatch
            : element(app, Phase9AXID.pdfSheet)
        let frame = preview.frame
        shoot("pdf-songbook", preview, clip: CGRect(
            x: frame.minX + frame.width * 0.292,
            y: frame.minY + frame.height * 0.093,
            width: frame.width * 0.69,
            height: frame.height * 0.828,
        ))
        element(app, Phase9AXID.pdfDone).click(in: app)
    }

    // MARK: - Steps

    /// Settings > Instrument: I play bass (bass notes on) and walk-ups on every change.
    private func turnOnBass(_ app: XCUIApplication) {
        _ = element(app, GuideAXID.songRow)
        app.typeKey(",", modifierFlags: .command, in: app)
        let tab = app.toolbars.buttons["Instrument"].firstMatch
        XCTAssertTrue(tab.appears(timeout: 10), "no Instrument pane")
        tab.click(in: app)
        element(app, Phase9AXID.playsBass).click(in: app)
        let walkUps = element(app, Phase9AXID.walkUps)
        walkUps.click(in: app)
        let every = app.menuItems["Every change"].firstMatch
        XCTAssertTrue(every.appears(timeout: 5), "no Every change in Walk-ups on charts")
        every.click(in: app)
        XCTAssertTrue(
            E2E.waitUntil(timeout: 5) { Self.text(walkUps).contains("Every change") },
            "Walk-ups on charts reads \(Self.text(walkUps))",
        )
        app.typeKey("w", modifierFlags: .command, in: app)
        XCTAssertTrue(tab.disappears(timeout: 10), "Settings stayed open")
    }

    /// The editor's Walk-ups list, the G to C change's picker shot, then the list closed.
    private func walkUpPicker(_ app: XCUIApplication) {
        element(app, Phase9AXID.editorWalkUps).click(in: app)
        _ = element(app, Phase9AXID.walkUpsSheet)
        let change = app.descendants(matching: .any)
            .matching(NSPredicate(
                format: "identifier BEGINSWITH %@ AND label CONTAINS %@",
                Phase9AXID.walkUpsRowPrefix,
                "G to C,",
            )).firstMatch
        XCTAssertTrue(change.appears(timeout: 10), "no G to C change in the Walk-ups list")
        change.click(in: app)
        let popover = app.popovers.firstMatch
        XCTAssertTrue(popover.appears(timeout: 10), "the walk-up picker never opened")
        // SwiftUI hands the popover content's identifier to its rows, so the popover is found
        // by type and the "Nothing here" row by its label.
        let nothing = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label BEGINSWITH %@", "Nothing here")).firstMatch
        XCTAssertTrue(nothing.appears(timeout: 10), "the walk-up picker shows no Nothing here")
        _ = popover.settles(timeout: 3)
        shoot("walk-up-popover", popover)
        app.typeKey(.escape, modifierFlags: [], in: app)
        XCTAssertTrue(popover.disappears(timeout: 5), "the walk-up picker stayed open")
        // Return is the list's Done (its own identifier is shadowed by the sheet's).
        app.typeKey(.return, modifierFlags: [], in: app)
        XCTAssertTrue(
            E2E.waitUntil(timeout: 10) { !app.sheets.firstMatch.exists },
            "the Walk-ups list stayed open",
        )
    }

    /// Waits until the PDF preview has counted its pages ("... pages" under the title).
    private func waitForPages(_ app: XCUIApplication, prefix: String) {
        let subtitle = element(app, Phase9AXID.pdfSubtitle)
        XCTAssertTrue(
            E2E.waitUntil(timeout: 20) {
                let text = Self.text(subtitle)
                return text.hasPrefix(prefix) && (text.hasSuffix("pages") || text.hasSuffix("page"))
            },
            "the PDF preview never counted its pages (\(Self.text(subtitle)))",
        )
        // The pages draw just after the count: let the sheet settle.
        _ = element(app, Phase9AXID.pdfSheet).settles(timeout: 3)
    }

    /// The chord over the first lyric of the preview line ending in `lyric` (the line's top
    /// left: each of these lines starts with a chord).
    private func chordAtLineStart(_ app: XCUIApplication, lyric: String) -> XCUICoordinate {
        let line = app.descendants(matching: .any).matching(identifier: Phase9AXID.sheetLine)
            .matching(NSPredicate(format: "label ENDSWITH %@ OR value ENDSWITH %@", lyric, lyric))
            .firstMatch
        XCTAssertTrue(line.appears(timeout: 10), "no preview line ending in \(lyric)")
        return line.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: 6, dy: 8))
    }

    private static func text(_ element: XCUIElement) -> String {
        (element.value as? String ?? "") + element.label
    }
}

/// Identifiers the 1.0 captures use (mirrors `AccessibilityID` in SegueUI).
enum Phase9AXID {
    static let sidebarLibrary = "segue.sidebar.library"
    static let setlistEntry = "segue.setlist.entry"
    static let setlistMenu = "segue.setlist.menu"
    static let medley = "segue.setlist.medley"
    static let medleySongCount = "segue.setlist.medley.songs"
    static let medleyTransition = "segue.setlist.medley.transition"
    static let liveMedley = "segue.live.medley"
    static let liveMemberTransition = "segue.live.medley.transition"
    static let playsBass = "segue.settings.instrument.playsBass"
    static let walkUps = "segue.settings.instrument.walkUps"
    static let liveBassScale = "segue.live.bassScale"
    static let liveBassNeck = "segue.live.bassNeck"
    static let editorWalkUps = "segue.editor.walkUps"
    static let editorDone = "segue.editor.done"
    static let walkUpsSheet = "segue.walkUps.sheet"
    static let walkUpsRowPrefix = "segue.walkUps.row."
    static let sheetLine = "segue.sheet.line"
    static let fillCreate = "segue.fill.create"
    static let fillEditor = "segue.fill.editor"
    static let fillMiniTab = "segue.fill.miniTab"
    static let pdfSheet = "segue.pdf.sheet"
    static let pdfSubtitle = "segue.pdf.subtitle"
    static let pdfDone = "segue.pdf.done"
    static let pdfExportSetlist = "segue.pdf.export.setlist"

    static func fillCandidate(_ letter: String) -> String {
        "segue.fill.candidate.\(letter)"
    }
}
