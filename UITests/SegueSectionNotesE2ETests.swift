import XCTest

/// Section notes through the real UI (P3-13, R87, R106), on a fresh Welcome library: add a
/// stage-only note on Kettle On's chorus from the library's Section Notes sheet, rehearse
/// the Welcome Set and see it as a callout on stage; then in the editor open the chorus
/// band's Section Notes, turn "Show on stage only" off, and see the `{comment}` in Text mode.
final class SegueSectionNotesE2ETests: XCTestCase {
    private var app: XCUIApplication?
    private var library: WelcomeLibrary?
    private static let note = "Lights down, brushes"
    private static let song = "kettle-on-lights-low"

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
    func testStageNoteShowsOnStageThenBecomesAChartNote() throws {
        let library = try XCTUnwrap(library)
        let app = XCUIApplication()
        self.app = app
        E2E.launch(app, arguments: library.arguments(["-SegueSeedWelcome", "YES"]))
        try addStageNote(app, library)
        rehearseAndSeeCallout(app)
        chartItInTheEditor(app, library)
    }

    // MARK: - Steps

    /// Library: a stage-only note on the chorus; only the sidecar changes.
    @MainActor
    private func addStageNote(_ app: XCUIApplication, _ library: WelcomeLibrary) throws {
        // The row appears once the Welcome songs are seeded: read the file only after it.
        selectKettle(app)
        let source = try String(contentsOf: choURL(library), encoding: .utf8)
        element(app, NotesAXID.open).click(in: app)
        element(app, NotesAXID.add("chorus")).click(in: app)
        let field = app.textFields[NotesAXID.text].firstMatch
        XCTAssertTrue(field.appears(timeout: 5), "no new note field")
        field.click(in: app)
        field.typeText(Self.note, in: app)
        app.checkBoxes[NotesAXID.stageOnly].firstMatch.click(in: app)
        attach(app, "section-notes-sheet")
        element(app, NotesAXID.done).click(in: app)
        XCTAssertTrue(
            E2E.waitUntil { (try? self.cues(library)) == [["Chorus", Self.note]] },
            "the stage note never reached the sidecar",
        )
        XCTAssertEqual(try String(contentsOf: choURL(library), encoding: .utf8), source)
    }

    /// Rehearse the Welcome Set: Kettle On is the third song, the note is its callout.
    @MainActor
    private func rehearseAndSeeCallout(_ app: XCUIApplication) {
        element(app, NotesAXID.sidebarSetlists).click(in: app)
        let row = element(app, NotesAXID.setlistRow)
        XCTAssertTrue(row.appears(timeout: 10))
        row.click(in: app)
        element(app, NotesAXID.rehearse).click(in: app)
        let start = element(app, NotesAXID.checklistStart)
        XCTAssertTrue(start.appears(timeout: 10))
        start.click(in: app)
        let title = app.staticTexts[NotesAXID.liveTitle]
        XCTAssertTrue(title.appears(timeout: 10))
        for _ in 0 ..< 2 {
            app.typeKey(.rightArrow, modifierFlags: [], in: app)
        }
        XCTAssertTrue(E2E.waitUntil { (title.value as? String) == "Kettle On, Lights Low" })
        let callout = app.descendants(matching: .any).matching(identifier: NotesAXID.liveCue)
            .matching(NSPredicate(format: "label == %@", Self.note)).firstMatch
        XCTAssertTrue(callout.appears(timeout: 5), "no stage callout")
        attach(app, "section-notes-stage-callout")
        app.typeKey(".", modifierFlags: .command, in: app)
        XCTAssertTrue(element(app, NotesAXID.liveEndDialog).appears(timeout: 5))
        app.typeKey(.return, modifierFlags: [], in: app)
        XCTAssertTrue(title.disappears(timeout: 10))
    }

    /// Editor: the chorus band's Section Notes, stage only off; Text mode shows the
    /// `{comment}` and both files follow.
    @MainActor
    private func chartItInTheEditor(_ app: XCUIApplication, _ library: WelcomeLibrary) {
        element(app, NotesAXID.sidebarLibrary).click(in: app)
        selectKettle(app)
        element(app, NotesAXID.editSong).click(in: app)
        element(app, NotesAXID.editorModeVisual).click(in: app)
        let canvas = app.textViews[NotesAXID.editorVisual]
        XCTAssertTrue(canvas.appears(timeout: 5))
        let band = app.descendants(matching: .any).matching(identifier: NotesAXID.band)
            .matching(NSPredicate(format: "label == %@", "Chorus")).firstMatch
        XCTAssertTrue(reveal(band, in: canvas), "no Chorus band on screen")
        band.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0))
            .withOffset(CGVector(dx: 0, dy: 10)).rightClick()
        let item = app.menuItems["Section Notes..."]
        XCTAssertTrue(item.appears(timeout: 5), "no Section Notes in the band menu")
        item.click()
        let stageOnly = app.checkBoxes[NotesAXID.stageOnly].firstMatch
        XCTAssertTrue(stageOnly.appears(timeout: 5))
        stageOnly.click(in: app)
        XCTAssertTrue(E2E.waitUntil { stageOnly.value as? Int == 0 }, "still stage only")
        element(app, NotesAXID.done).click(in: app)

        element(app, NotesAXID.editorModeText).click(in: app)
        let editor = app.textViews[NotesAXID.editorText]
        XCTAssertTrue(editor.appears(timeout: 5))
        let charted = "{start_of_chorus}\n{comment: \(Self.note)}\n[Cadd9]Turn"
        XCTAssertTrue((editor.value as? String ?? "").contains(charted), "\(editor.value ?? "")")
        attach(app, "section-notes-text-mode")
        XCTAssertTrue(E2E.waitUntil {
            let file = (try? String(contentsOf: self.choURL(library), encoding: .utf8)) ?? ""
            return file.contains(charted) && (try? self.cues(library))?.isEmpty == true
        }, "the chart note never reached the files")
    }

    // MARK: - Helpers

    private func choURL(_ library: WelcomeLibrary) -> URL {
        library.songs.appending(path: "\(Self.song).cho")
    }

    /// The sidecar's cues as [section, text] pairs.
    private func cues(_ library: WelcomeLibrary) throws -> [[String]] {
        let data = try Data(contentsOf: library.songs.appending(path: "\(Self.song).segue.json"))
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let cues = json?["cues"] as? [[String: Any]] ?? []
        return cues.map { [$0["section"] as? String ?? "", $0["text"] as? String ?? ""] }
    }

    @MainActor
    private func selectKettle(_ app: XCUIApplication) {
        let row = app.descendants(matching: .any).matching(identifier: NotesAXID.songRow)
            .matching(NSPredicate(format: "label BEGINSWITH %@", "Kettle On")).firstMatch
        XCTAssertTrue(row.appears(timeout: 15), "no Kettle On row")
        row.click(in: app)
    }

    @MainActor
    private func element(_ app: XCUIApplication, _ identifier: String) -> XCUIElement {
        let element = app.descendants(matching: .any).matching(identifier: identifier).firstMatch
        XCTAssertTrue(element.appears(timeout: 10), "no \(identifier)")
        return element
    }

    /// Scrolls the canvas until `element` is on screen.
    @MainActor
    private func reveal(_ element: XCUIElement, in canvas: XCUIElement) -> Bool {
        func shown() -> Bool {
            element.exists && canvas.frame.intersects(element.frame)
        }
        for delta in [-80.0, 80.0] {
            for _ in 0 ..< 15 where !shown() {
                canvas.scroll(byDeltaX: 0, deltaY: delta)
            }
        }
        return shown()
    }

    @MainActor
    private func attach(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}

/// Identifiers the section notes E2E uses (mirrors `AccessibilityID` in SegueUI).
enum NotesAXID {
    static let songRow = "segue.library.row"
    static let open = "segue.sectionNotes.open"
    static let done = "segue.sectionNotes.done"
    static let text = "segue.sectionNotes.note.text"
    static let stageOnly = "segue.sectionNotes.note.stageOnly"
    static func add(_ group: String) -> String {
        "segue.sectionNotes.add.\(group)"
    }

    static let sidebarLibrary = "segue.sidebar.library"
    static let sidebarSetlists = "segue.sidebar.setlists"
    static let setlistRow = "segue.setlists.row"
    static let rehearse = "segue.setlist.rehearse"
    static let checklistStart = "segue.live.checklist.start"
    static let liveTitle = "segue.live.title"
    static let liveCue = "segue.live.cue"
    static let liveEndDialog = "segue.live.endDialog"
    static let editSong = "segue.song.edit"
    static let editorModeText = "segue.editor.mode.text"
    static let editorModeVisual = "segue.editor.mode.visual"
    static let editorText = "segue.editor.text"
    static let editorVisual = "segue.editor.visual"
    static let band = "segue.editor.sectionBand"
}
