import XCTest

/// The visual editor's section band through the real UI (P3-11, R82), on a fresh Welcome
/// library: unwrap two sections from the band menu, select four loose lines in the lane,
/// press C, see a chorus around exactly those lines in Text mode, then drag the chorus's
/// bottom edge down one line.
final class SegueSectionBandE2ETests: XCTestCase {
    private var app: XCUIApplication?
    private var library: WelcomeLibrary?

    override func setUpWithError() throws {
        continueAfterFailure = false
        library = try WelcomeLibrary()
    }

    override func tearDownWithError() throws {
        E2E.terminate(app)
        if let root = library?.root {
            try? FileManager.default.removeItem(at: root)
        }
    }

    @MainActor
    func testSelectLinesPressCThenDragTheEdge() throws {
        let library = try XCTUnwrap(library)
        let (app, canvas) = openInVisualMode(library)
        // Unwrap Verse 1 and the chorus from the band menu: their lines become loose.
        for label in ["Verse 1", "Chorus"] {
            unwrap(label, app: app, canvas: canvas)
        }
        XCTAssertTrue(waitForFile(library) { !$0.contains("{start_of_verse: Verse 1}") })

        // Select Verse 1's four lines (the first four-line slot) and press C.
        let firstLine = app.descendants(matching: .any).matching(identifier: BandAXID.lane)
            .matching(NSPredicate(format: "label == %@", "Purani")).firstMatch
        XCTAssertTrue(reveal(firstLine, in: canvas), "Verse 1's first line is not on screen")
        let slot = try XCTUnwrap(
            slots(app).first { $0.value as? String == "4 lines" },
            "no four-line slot",
        )
        XCTAssertTrue(reveal(slot, in: canvas))
        slot.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0))
            .withOffset(CGVector(dx: 0, dy: 10)).click()
        XCTAssertTrue(element(app, BandAXID.chipBar).appears(timeout: 5), "no chip bar")
        app.typeKey("c", modifierFlags: [])
        let chorus = """
        {start_of_chorus}
        [Am]Purani si gali mein [G]kitaabon ki dukaan,
        [F]Panne palatte haathon mein [E]chhupi thi muskaan,
        [Am]Chai ka cup thanda tha, [G]baatein thi garam,
        [F]Shaam ne dheere dheere [E]badle apne kadam.
        {end_of_chorus}
        """
        XCTAssertTrue(waitForFile(library) { $0.contains(chorus) }, "no chorus in the file")

        // Text mode shows the chorus around exactly those lines.
        element(app, BandAXID.editorModeText).click(in: app)
        let editor = app.textViews[BandAXID.editorText]
        XCTAssertTrue(editor.appears(timeout: 5))
        XCTAssertTrue((editor.value as? String ?? "").contains(chorus), "\(editor.value ?? "")")

        // Drag the chorus's bottom edge down one line: it takes the next lyric line.
        element(app, BandAXID.editorModeVisual).click(in: app)
        let band = band(app, "Chorus")
        XCTAssertTrue(reveal(band, in: canvas, whole: true), "no Chorus band on screen")
        let edge = band.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 1))
            .withOffset(CGVector(dx: 0, dy: -2))
        edge.press(forDuration: 0.4, thenDragTo: edge.withOffset(CGVector(dx: 0, dy: 60)))
        XCTAssertTrue(waitForFile(library) {
            $0.contains("[Am]rahi,\n{end_of_chorus}") && !$0.contains("kadam.\n{end_of_chorus}")
        }, "the edge did not move one line down")
    }

    // MARK: - Helpers

    /// Launches on the Welcome library and opens Kitaabon Wali Gali in the visual editor,
    /// with the window zoomed to the screen so whole sections fit.
    @MainActor
    private func openInVisualMode(_ library: WelcomeLibrary) -> (XCUIApplication, XCUIElement) {
        let app = XCUIApplication()
        self.app = app
        E2E.launch(app, arguments: library.arguments(["-SegueSeedWelcome", "YES"]))
        let row = app.descendants(matching: .any).matching(identifier: BandAXID.songRow)
            .matching(NSPredicate(format: "label BEGINSWITH %@", "Kitaabon")).firstMatch
        XCTAssertTrue(row.appears(timeout: 15), "no Welcome song row")
        row.click(in: app)
        element(app, BandAXID.editSong).click(in: app)
        element(app, BandAXID.editorModeVisual).click(in: app)
        let canvas = app.textViews[BandAXID.editorVisual]
        XCTAssertTrue(canvas.appears(timeout: 5))
        let zoom = app.menuBars.menuBarItems["Window"].menuItems["Zoom"]
        app.menuBars.menuBarItems["Window"].click()
        if zoom.waitForExistence(timeout: 2) {
            zoom.click()
        } else {
            app.typeKey(.escape, modifierFlags: [])
        }
        return (app, canvas)
    }

    /// Right-clicks the band labelled `label` and picks Unwrap.
    @MainActor
    private func unwrap(_ label: String, app: XCUIApplication, canvas: XCUIElement) {
        let band = band(app, label)
        XCTAssertTrue(reveal(band, in: canvas), "no \(label) band")
        // On the cap: the top of a band is on screen even when its bottom is not.
        band.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0))
            .withOffset(CGVector(dx: 0, dy: 10)).rightClick()
        let unwrap = app.menuItems["Unwrap"]
        XCTAssertTrue(unwrap.appears(timeout: 5), "no Unwrap in the band menu")
        unwrap.click()
        XCTAssertTrue(E2E.waitUntil { !band.exists }, "\(label) still a section")
    }

    @MainActor
    private func element(_ app: XCUIApplication, _ identifier: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    @MainActor
    private func band(_ app: XCUIApplication, _ label: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: BandAXID.band)
            .matching(NSPredicate(format: "label == %@", label)).firstMatch
    }

    /// Scrolls the canvas until `element` is on screen (all of it with `whole`), trying
    /// both scroll directions.
    @MainActor
    private func reveal(
        _ element: XCUIElement,
        in canvas: XCUIElement,
        whole: Bool = false,
    ) -> Bool {
        func shown() -> Bool {
            guard element.exists else { return false }
            let frame = element.frame
            let view = canvas.frame
            return whole ? view.contains(frame.insetBy(dx: 1, dy: 1)) : view.intersects(frame)
        }
        for delta in [-80.0, 80.0] {
            for _ in 0 ..< 15 {
                if shown() {
                    return true
                }
                canvas.scroll(byDeltaX: 0, deltaY: delta)
            }
        }
        return shown()
    }

    /// The empty slots, top to bottom.
    @MainActor
    private func slots(_ app: XCUIApplication) -> [XCUIElement] {
        let query = app.descendants(matching: .any).matching(identifier: BandAXID.slot)
        return (0 ..< query.count).map { query.element(boundBy: $0) }
            .sorted { $0.frame.minY < $1.frame.minY }
    }

    private func waitForFile(
        _ library: WelcomeLibrary,
        _ check: @escaping (String) -> Bool,
    ) -> Bool {
        E2E.waitUntil {
            let file = library.songs.appending(path: "kitaabon-wali-gali.cho")
            return check((try? String(contentsOf: file, encoding: .utf8)) ?? "")
        }
    }
}

/// Identifiers the section band E2E uses (mirrors `AccessibilityID` in SegueUI).
enum BandAXID {
    static let songRow = "segue.library.row"
    static let editSong = "segue.song.edit"
    static let editorModeText = "segue.editor.mode.text"
    static let editorModeVisual = "segue.editor.mode.visual"
    static let editorText = "segue.editor.text"
    static let editorVisual = "segue.editor.visual"
    static let band = "segue.editor.sectionBand"
    static let slot = "segue.editor.sectionBand.slot"
    static let chipBar = "segue.editor.sectionBand.chipBar"
    static let lane = "segue.editor.lane"
}
