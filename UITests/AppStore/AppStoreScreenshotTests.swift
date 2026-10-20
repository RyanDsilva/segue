import AppKit
import XCTest

/// The App Store screenshots (docs/release/specs/WS5-store-listing.md 8.3-8.4), one test per
/// shot, run by `make screenshots` in dark and then light (`TEST_RUNNER_SEGUE_SHOT_APPEARANCE`).
/// Each attaches the 1440x900 pt window as `appstore-<NN>-<slug>-<appearance>` (2880x1800 px,
/// asserted); scripts/compose-screenshots.swift captions and frames them. Stage shots exist
/// only in the dark run (the stage is always dark). Never run by `make e2e` or the gate.
class StoreShotCase: GuideShotCase {
    override class var windowSize: CGSize {
        CGSize(width: 1440, height: 900)
    }

    /// Attaches `window` as store shot `number`-`slug`, failing unless it is 2880x1800 px.
    @MainActor
    func storeShot(
        _ number: String,
        _ slug: String,
        _ window: XCUIElement,
        stage: Bool = false,
        file: StaticString = #filePath,
        line: UInt = #line,
    ) {
        if stage, !isDarkRun {
            return
        }
        if let app {
            mainWindow(app).coordinate(withNormalizedOffset: .zero)
                .withOffset(CGVector(dx: -12, dy: -12)).hover()
            if stage {
                let status = app.descendants(matching: .any)[GuideAXID.liveStatus]
                XCTAssertTrue(status.disappears(timeout: 6), "the stage status line stayed up")
            }
        }
        _ = window.settles(timeout: 3)
        let png = window.screenshot().pngRepresentation
        let size = NSBitmapImageRep(data: png).map { ($0.pixelsWide, $0.pixelsHigh) } ?? (0, 0)
        XCTAssertTrue(
            size == (2880, 1800),
            "store shot \(slug) is \(size.0)x\(size.1) px, not 2880x1800",
            file: file,
            line: line,
        )
        let attachment = XCTAttachment(data: png, uniformTypeIdentifier: "public.png")
        attachment.name = "appstore-\(number)-\(slug)-\(appearance)"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    /// Start Show on `setlist`, past the checklist, onto the stage.
    @MainActor
    func startShow(_ app: XCUIApplication, _ setlist: String) -> XCUIElement {
        openSetlist(app, setlist)
        element(app, GuideAXID.setlistStartShow).click(in: app)
        element(app, GuideAXID.checklistStart).click(in: app)
        XCTAssertTrue(app.staticTexts[GuideAXID.liveTitle].appears(timeout: 10))
        return stageWindow(app)
    }

    /// Steps the stage forward until the song `title` is up.
    @MainActor
    func advance(_ app: XCUIApplication, to title: String) {
        let current = app.staticTexts[GuideAXID.liveTitle]
        func showing() -> Bool {
            ((current.value as? String ?? "") + current.label).contains(title)
        }
        for _ in 0 ..< 10 where !showing() {
            app.typeKey(.rightArrow, modifierFlags: [], in: app)
            _ = E2E.waitUntil(timeout: 2) { showing() }
        }
        XCTAssertTrue(showing(), "the stage never reached \(title)")
    }
}

final class AppStoreScreenshotTests: StoreShotCase {
    /// 1 stage: "JamFest Opener" on Ferry Lights (position 3), with an Up next song.
    @MainActor
    func test01Stage() {
        let app = launch()
        let stage = startShow(app, "JamFest Opener")
        advance(app, to: "Ferry Lights Over Calder Bay")
        _ = element(app, GuideAXID.liveUpNext)
        storeShot("01", "stage", stage, stage: true)
        endShow(app)
    }

    /// 2 builder: the set builder on "JamFest Opener", library left, the set and its running
    /// total right.
    @MainActor
    func test02Builder() {
        let app = launch()
        openSetlist(app, "JamFest Opener")
        app.typeKey("1", modifierFlags: .command, in: app)
        _ = element(app, GuideAXID.setlistTotal)
        storeShot("02", "builder", mainWindow(app))
    }

    /// 3 search: `kitabon` finds Kitaabon Wali Gali by a lyric line.
    @MainActor
    func test03Search() {
        let app = launch()
        let search = element(app, GuideAXID.librarySearch)
        search.click(in: app)
        search.typeText("kitabon", in: app)
        song(app, titled: "Kitaabon Wali Gali").click(in: app)
        storeShot("03", "search", mainWindow(app))
    }

    /// 4 editor: Visual mode, chord pills over the syllables, one chord selected.
    @MainActor
    func test04Editor() {
        let app = launch()
        song(app, titled: "Kettle On, Lights Low").click(in: app)
        element(app, GuideAXID.editSong).click(in: app)
        _ = element(app, GuideAXID.editorVisual)
        let pill = app.descendants(matching: .any).matching(identifier: GuideAXID.editorPill)
            .element(boundBy: 2)
        XCTAssertTrue(pill.appears(timeout: 10), "no chord pills")
        pill.click(in: app)
        storeShot("04", "editor", mainWindow(app))
    }

    /// 5 theory: transposed, capo on, Nashville numbers, guitar diagrams.
    @MainActor
    func test05Theory() {
        let app = launch()
        song(app, titled: "Kettle On, Lights Low").click(in: app)
        element(app, GuideAXID.editSong).click(in: app)
        _ = element(app, GuideAXID.editorVisual)
        let up = element(app, GuideAXID.editorTransposeUp)
        up.click(in: app)
        up.click(in: app)
        element(app, GuideAXID.editorNashville).click(in: app)
        element(app, GuideAXID.editorDiagramsToggle).click(in: app)
        _ = element(app, GuideAXID.diagramStrip)
        storeShot("05", "theory", mainWindow(app))
    }

    /// 6 request: mid-set on Ferry Lights, quick search finds Kitaabon Wali Gali (not in the
    /// set) from `kitabon`, ready to queue.
    @MainActor
    func test06Request() {
        let app = launch()
        let stage = startShow(app, "JamFest Opener")
        advance(app, to: "Ferry Lights Over Calder Bay")
        app.typeKey("k", modifierFlags: .command, in: app)
        let field = app.textFields[GuideAXID.liveSearchField]
        XCTAssertTrue(field.appears(timeout: 10))
        field.typeText("kitabon", in: app)
        _ = element(app, GuideAXID.liveSearchResult)
        storeShot("06", "request", stage, stage: true)
        app.typeKey(.escape, modifierFlags: [], in: app)
        endShow(app)
    }

    /// 7 minsize: a large minimum lyric size; the song scrolls instead of shrinking.
    @MainActor
    func test07MinSize() {
        let app = launch()
        _ = element(app, GuideAXID.songRow)
        app.typeKey(",", modifierFlags: .command, in: app)
        let tab = app.toolbars.buttons["Live"].firstMatch
        XCTAssertTrue(tab.appears(timeout: 10))
        tab.click(in: app)
        let stepper = app.steppers[GuideAXID.settingsMinLyricSize].firstMatch
        XCTAssertTrue(stepper.appears(timeout: 10))
        for _ in 0 ..< 12 {
            stepper.incrementArrows.firstMatch.click(in: app)
        }
        XCTAssertTrue(app.staticTexts["34 pt"].appears(timeout: 5))
        app.typeKey("w", modifierFlags: .command, in: app)
        XCTAssertTrue(stepper.disappears(timeout: 10))
        let stage = startShow(app, "Welcome Set")
        advance(app, to: "Ferry Lights Over Calder Bay")
        app.typeKey(.downArrow, modifierFlags: [], in: app)
        storeShot("07", "minsize", stage, stage: true)
        endShow(app)
    }

    /// 8 checklist: the pre-show checklist over the setlist.
    @MainActor
    func test08Checklist() {
        let app = launch()
        openSetlist(app, "JamFest Opener")
        element(app, GuideAXID.setlistStartShow).click(in: app)
        XCTAssertTrue(app.sheets.firstMatch.appears(timeout: 10), "no pre-show checklist")
        _ = element(app, GuideAXID.checklistStart)
        storeShot("08", "checklist", mainWindow(app))
        app.typeKey(.escape, modifierFlags: [], in: app)
    }

    /// 9 paste: the review sheet for the guide's chord-site paste, with the AI marks.
    @MainActor
    func test09Paste() {
        let app = launch()
        _ = pasteFixture(app)
        _ = aiSectionLabel(app)
        storeShot("09", "paste", mainWindow(app))
        element(app, GuideAXID.pasteCancel).click(in: app)
    }
}
