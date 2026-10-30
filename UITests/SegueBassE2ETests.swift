import XCTest

/// The bass profile end to end (P8-4a section 11.4, R152, R158): a song in G with capo 2,
/// Settings > Instrument > I play bass with 5 strings (BEADG), then the editor preview and
/// a single-song rehearsal show the notes to play at sounding pitch ("A", "C#", "D"), the
/// stage header says "Sounding A major", the mini neck reads "A, ...", and B brings the
/// chart's chords back with the neck gone.
final class SegueBassE2ETests: SetlistE2ETestCase {
    private static let song = """
    {title: Bass Harbour}
    {key: G}
    {capo: 2}

    [G]Hello [G/B]there [C]friend
    """

    @MainActor
    func testBassProfileShowsSoundingRoots() throws {
        let root = try XCTUnwrap(libraryRoot)
        try SetlistFixture.write(Self.song, to: root.appending(path: "songs/bass-harbour.cho"))
        let app = try launch(waitForSongs: false)
        turnOnBassProfile(app)
        let row = checkEditorPreview(app)
        rehearseAndCheckStage(app, row: row)
    }

    /// Settings > Instrument: I play bass, 5 strings (the tuning becomes BEADG).
    @MainActor
    private func turnOnBassProfile(_ app: XCUIApplication) {
        E2E.bringToFront(app)
        app.typeKey(",", modifierFlags: .command, in: app)
        let instrumentTab = app.toolbars.buttons["Instrument"].firstMatch
        XCTAssertTrue(instrumentTab.appears(timeout: 10), "no Instrument pane")
        instrumentTab.click(in: app)
        let playsBass = element(app, BassAXID.playsBass)
        XCTAssertTrue(playsBass.appears(timeout: 5))
        playsBass.click(in: app)
        let strings = element(app, BassAXID.strings)
        XCTAssertTrue(strings.appears(timeout: 5))
        let five = strings.radioButtons["5"].exists ? strings.radioButtons["5"]
            : strings.buttons["5"]
        five.click(in: app)
        SetlistE2E.waitUntil("the tuning never became BEADG") {
            SetlistE2E.text(element(app, BassAXID.tuning)).contains("BEADG")
        }
        screenshot(app, "bass-settings")
        app.typeKey("w", modifierFlags: .command, in: app)
        XCTAssertTrue(instrumentTab.disappears(timeout: 5))
    }

    /// The editor's text-mode preview: the notes to play at sounding pitch.
    @MainActor
    private func checkEditorPreview(_ app: XCUIApplication) -> XCUIElement {
        E2E.bringToFront(app)
        element(app, SetlistAXID.sidebarLibrary).click(in: app)
        let row = SetlistE2E.row(app, SetlistAXID.songRow, "Bass Harbour")
        XCTAssertTrue(row.appears(timeout: 10), "the song is not listed")
        row.click(in: app)
        let edit = element(app, BassAXID.editSong)
        XCTAssertTrue(edit.appears(timeout: 5))
        edit.click(in: app)
        let textMode = element(app, BassAXID.editorModeText)
        XCTAssertTrue(textMode.appears(timeout: 10))
        textMode.click(in: app)
        XCTAssertTrue(element(app, BassAXID.editorBass).appears(timeout: 5))
        SetlistE2E.waitUntil("the preview never showed bass notes") {
            SetlistE2E.texts(app, BassAXID.sheetLine)
                .contains("A, C#, D: Hello there friend")
        }
        screenshot(app, "bass-editor")
        return row
    }

    /// Rehearse the song (R150): the stage shows the same notes, the sounding key and the
    /// mini neck; B brings the chart's chords back with the neck gone.
    @MainActor
    private func rehearseAndCheckStage(_ app: XCUIApplication, row: XCUIElement) {
        // Done closes the editor; the song page's Rehearse button starts a single-song run.
        element(app, BassAXID.editorDone).click(in: app)
        let rehearse = element(app, BassAXID.rehearseButton)
        XCTAssertTrue(rehearse.appears(timeout: 10))
        XCTAssertTrue(row.exists)
        rehearse.click(in: app)
        let title = app.staticTexts[BassAXID.liveTitle]
        XCTAssertTrue(title.appears(timeout: 10), "the stage never opened")
        SetlistE2E.waitUntil("the stage never showed bass notes") {
            SetlistE2E.texts(app, BassAXID.sheetChord) == ["A", "C#", "D"]
        }
        let scale = element(app, BassAXID.scale)
        XCTAssertTrue(scale.appears(timeout: 5), "no scale line")
        XCTAssertTrue(SetlistE2E.text(scale).hasPrefix("Sounding key A major"))
        let neck = element(app, BassAXID.neck)
        XCTAssertTrue(neck.appears(timeout: 5), "no mini neck")
        XCTAssertTrue(SetlistE2E.text(neck).contains("A, "), SetlistE2E.text(neck))
        screenshot(app, "bass-stage")

        app.typeKey("b", modifierFlags: [], in: app)
        SetlistE2E.waitUntil("B never brought the chords back") {
            SetlistE2E.texts(app, BassAXID.sheetChord) == ["G", "G/B", "C"]
        }
        XCTAssertTrue(neck.disappears(timeout: 5), "the neck stayed up")

        app.typeKey(".", modifierFlags: .command, in: app)
        XCTAssertTrue(element(app, BassAXID.endDialog).appears(timeout: 5))
        app.typeKey(.return, modifierFlags: [], in: app)
        XCTAssertTrue(title.disappears(timeout: 10))
    }

    @MainActor
    private func element(_ app: XCUIApplication, _ identifier: String) -> XCUIElement {
        SetlistE2E.element(app, identifier)
    }
}

/// Mirrors `AccessibilityID+Bass` and the editor and live IDs this suite reads.
enum BassAXID {
    static let playsBass = "segue.settings.instrument.playsBass"
    static let strings = "segue.settings.instrument.strings"
    static let tuning = "segue.settings.instrument.tuning"
    static let editSong = "segue.song.edit"
    static let editorModeText = "segue.editor.mode.text"
    static let editorBass = "segue.editor.bass"
    static let editorDone = "segue.editor.done"
    static let rehearseButton = "segue.library.song.rehearse"
    static let sheetLine = "segue.sheet.line"
    static let sheetChord = "segue.sheet.chord"
    static let liveTitle = "segue.live.title"
    static let scale = "segue.live.bassScale"
    static let neck = "segue.live.bassNeck"
    static let endDialog = "segue.live.endDialog"
}
