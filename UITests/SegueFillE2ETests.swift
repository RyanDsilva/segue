import XCTest

/// The bass fill creator end to end (P8-7 section 16.4, R166-R168): a song in G whose verse
/// ends on C and whose chorus starts on D; the bass-note view on; in the editor's preview a
/// click on C and a shift-click on D select a span across the section boundary; Option-Cmd-F
/// opens the fill editor with options A-D; B is auditioned and chosen, one note is edited by
/// typing a fret, Piano Roll and back keep the choice, Save writes the fill to the sidecar
/// (never the `.cho`), and the fill's note names show over C in the bass view. After a
/// relaunch the library's preview shows the same fill, a rehearsal of the song shows it on
/// stage, and T turns it into a mini tab. No audio is asserted (P8-6 15.4).
final class SegueFillE2ETests: SetlistE2ETestCase {
    private static let stem = "fill-harbour"
    private static let song = """
    {title: Fill Harbour}
    {key: G}

    {start_of_verse}
    [G]Hello
    [C]there
    {end_of_verse}

    {start_of_chorus}
    [D]friend
    [G]home
    {end_of_chorus}
    """
    /// A song ID is a ULID (a UUID here made the sidecar unreadable, so the song opened
    /// read-only and had no Edit).
    private static let sidecar = """
    {
      "schemaVersion" : 3,
      "id" : "01JC0000000000000000000F11",
      "createdAt" : "2026-10-01T10:00:00Z",
      "updatedAt" : "2026-10-01T10:00:00Z"
    }
    """

    @MainActor
    func testCreateFillAndReadItOnStage() throws {
        let root = try XCTUnwrap(libraryRoot)
        let cho = root.appending(path: "songs/\(Self.stem).cho")
        try SetlistFixture.write(Self.song, to: cho)
        try SetlistFixture.write(
            Self.sidecar,
            to: root.appending(path: "songs/\(Self.stem).segue.json"),
        )
        let app = try launch(waitForSongs: false)
        turnOnWalkUps(app)
        openEditorWithBassView(app)
        selectSpan(app)
        let run = createFill(app)
        XCTAssertEqual(
            try String(contentsOf: cho, encoding: .utf8),
            Self.song,
            "Save touched the .cho",
        )
        let sidecar = root.appending(path: "songs/\(Self.stem).segue.json")
        SetlistE2E.waitForDisk("the fill never reached the sidecar") {
            try (SetlistFixture.json(sidecar)["parts"] as? [Any])?.count == 1
        }
        relaunchAndCheckLibrary(app, run: run)
        rehearseAndReadTab(app, run: run)
    }

    /// Settings > Instrument > Walk-ups on charts > Every change: fills follow the walk-up
    /// density (R168 Q7), so with walk-ups Off (the default) a saved fill draws nowhere.
    @MainActor
    private func turnOnWalkUps(_ app: XCUIApplication) {
        E2E.bringToFront(app)
        app.typeKey(",", modifierFlags: .command, in: app)
        let instrumentTab = app.toolbars.buttons["Instrument"].firstMatch
        XCTAssertTrue(instrumentTab.appears(timeout: 10), "no Instrument pane")
        instrumentTab.click(in: app)
        let picker = app.popUpButtons[FillAXID.walkUpsPicker]
        XCTAssertTrue(picker.appears(timeout: 5), "no walk-ups picker")
        // The pane scrolls: bring the picker into the window before opening it.
        let anchor = element(app, FillAXID.playsBass)
        XCTAssertTrue(anchor.appears(timeout: 5))
        // The picker is disabled until "I play bass" is on.
        anchor.click(in: app)
        SetlistE2E.waitUntil("the walk-ups picker never enabled") { picker.isEnabled }
        anchor.hover()
        for _ in 0 ..< 6 where !picker.isHittable {
            anchor.scroll(byDeltaX: 0, deltaY: -300)
        }
        // Off, Into sections, Every change: two Downs from Off, then Return.
        picker.click(in: app)
        app.typeKey(.downArrow, modifierFlags: [], in: app)
        app.typeKey(.downArrow, modifierFlags: [], in: app)
        app.typeKey(.return, modifierFlags: [], in: app)
        SetlistE2E.waitUntil("walk-ups never turned on") {
            SetlistE2E.text(picker).contains("Every change")
        }
        app.typeKey("w", modifierFlags: .command, in: app)
        XCTAssertTrue(instrumentTab.disappears(timeout: 5))
    }

    /// Library > Fill Harbour > Edit, text mode, and the Bass segment on (user-level).
    @MainActor
    private func openEditorWithBassView(_ app: XCUIApplication) {
        E2E.bringToFront(app)
        element(app, FillAXID.sidebarLibrary).click(in: app)
        let row = SetlistE2E.row(app, FillAXID.songRow, "Fill Harbour")
        XCTAssertTrue(row.appears(timeout: 10), "the song is not listed")
        row.click(in: app)
        let edit = element(app, FillAXID.editSong)
        XCTAssertTrue(edit.appears(timeout: 5))
        edit.click(in: app)
        let textMode = element(app, FillAXID.editorModeText)
        XCTAssertTrue(textMode.appears(timeout: 10))
        textMode.click(in: app)
        let bass = element(app, FillAXID.editorBass)
        XCTAssertTrue(bass.appears(timeout: 5))
        // "I play bass" (turnOnWalkUps) already turned the bass-note view on; a click here
        // would turn it off again.
        SetlistE2E.waitUntil("the preview never showed the chart") {
            SetlistE2E.texts(app, FillAXID.sheetLine).contains { $0.hasSuffix("there") }
        }
    }

    /// A click on C (the verse's last chord) anchors the span; a shift-click on D (the
    /// chorus's first) extends it silently across the section boundary.
    @MainActor
    private func selectSpan(_ app: XCUIApplication) {
        chordAtLineStart(app, lyric: "there").click()
        let landing = chordAtLineStart(app, lyric: "friend")
        XCUIElement.perform(withKeyModifiers: .shift) { landing.click() }
        let capsule = element(app, FillAXID.create)
        XCTAssertTrue(capsule.appears(timeout: 5), "no Create Bass Fill capsule")
        XCTAssertTrue(
            SetlistE2E.text(capsule).contains("from C to D"),
            SetlistE2E.text(capsule),
        )
        screenshot(app, "fill-span")
    }

    /// Option-Cmd-F, options A-D, audition B, choose it, type a fret on the grid, Save.
    /// Returns the fill's note names as the preview shows them over C.
    @MainActor
    private func createFill(_ app: XCUIApplication) -> String {
        app.typeKey("f", modifierFlags: [.command, .option], in: app)
        let sheet = element(app, FillAXID.editor)
        XCTAssertTrue(sheet.appears(timeout: 10), "the fill editor never opened")
        for letter in ["a", "b", "c", "d"] {
            XCTAssertTrue(
                element(app, FillAXID.candidate(letter)).appears(timeout: 5),
                "no option \(letter.uppercased())",
            )
        }
        // Audition B (it plays and selects the row), then stop it.
        let play = element(app, FillAXID.candidatePlay("b"))
        play.click(in: app)
        SetlistE2E.waitUntil("B never started") { play.label == "Stop" }
        play.click(in: app)
        SetlistE2E.waitUntil("B never stopped") { play.label == "Play" }
        let optionB = element(app, FillAXID.candidate("b"))
        optionB.click(in: app)
        SetlistE2E.waitUntil("B was never chosen") { optionB.isSelected }

        // Edit a note: a click on the grid's first steps focuses it and puts the cursor
        // there (on a note, or a new one on the chord's note); a typed 9 sets that note to
        // fret 9 on its string, and the mini tab follows.
        let tab = element(app, FillAXID.miniTab)
        XCTAssertTrue(tab.appears(timeout: 5), "no mini tab")
        let before = SetlistE2E.text(tab)
        let grid = element(app, FillAXID.grid)
        XCTAssertTrue(grid.appears(timeout: 5), "no step grid")
        grid.coordinate(withNormalizedOffset: CGVector(dx: 0.04, dy: 0.6)).click()
        app.typeKey("9", modifierFlags: [], in: app)
        SetlistE2E.waitUntil("typing a fret never changed the fill (\(before))") {
            SetlistE2E.text(tab) != before
        }
        screenshot(app, "fill-editor")

        // Piano Roll and back: the chosen option and its edit stay.
        let edited = SetlistE2E.text(tab)
        element(app, FillAXID.viewPianoRoll).click(in: app)
        XCTAssertTrue(element(app, FillAXID.pianoRoll).appears(timeout: 5), "no piano roll")
        element(app, FillAXID.viewFretboard).click(in: app)
        XCTAssertTrue(grid.appears(timeout: 5), "the grid never came back")
        XCTAssertTrue(optionB.isSelected, "switching views lost the chosen option")
        XCTAssertEqual(SetlistE2E.text(tab), edited, "switching views changed the fill")

        element(app, FillAXID.save).click(in: app)
        XCTAssertTrue(sheet.disappears(timeout: 10), "Save never closed the sheet")
        var run = ""
        SetlistE2E.waitUntil("the preview never showed the fill over C") {
            run = Self.previewFillLine(app) ?? ""
            return !run.isEmpty
        }
        screenshot(app, "fill-saved")
        element(app, FillAXID.editorDone).click(in: app)
        return run
    }

    /// The preview's line that carries a fill. A preview line is one accessibility element
    /// (children ignored, WS2b 4.9.2), so the fill's notes are read from its spoken label
    /// ("..., fill: E, F sharp into D, ...: lyric"), not from the drawn run inside it.
    @MainActor
    private static func previewFillLine(_ app: XCUIApplication) -> String? {
        SetlistE2E.texts(app, FillAXID.sheetLine).first { $0.contains("fill: ") }
    }

    /// Quits, launches again on the same library (state kept, so the bass-note view is still
    /// on), and the library's preview shows the same fill.
    @MainActor
    private func relaunchAndCheckLibrary(_ app: XCUIApplication, run: String) {
        let arguments = app.launchArguments
        app.terminate()
        XCTAssertTrue(app.reaches(.notRunning, timeout: 20))
        var kept = arguments
        if let reset = kept.firstIndex(of: "-SegueResetState") {
            kept.removeSubrange(reset ... reset + 1)
        }
        app.launchArguments = kept
        app.launch()
        E2E.bringToFront(app)
        XCTAssertTrue(app.windows.firstMatch.appears(timeout: 15))
        element(app, FillAXID.sidebarLibrary).click(in: app)
        let row = SetlistE2E.row(app, FillAXID.songRow, "Fill Harbour")
        XCTAssertTrue(row.appears(timeout: 10), "the song is not listed after a relaunch")
        row.click(in: app)
        SetlistE2E.waitUntil("the library never showed the fill after a relaunch") {
            Self.previewFillLine(app) == run
        }
        screenshot(app, "fill-relaunched")
    }

    /// Rehearse the song from the library (R150): the stage shows the fill's notes over C;
    /// T shows every fill as a mini tab instead; End.
    @MainActor
    private func rehearseAndReadTab(_ app: XCUIApplication, run: String) {
        let rehearse = element(app, FillAXID.rehearseButton)
        XCTAssertTrue(rehearse.appears(timeout: 10))
        rehearse.click(in: app)
        let title = app.staticTexts[FillAXID.liveTitle]
        XCTAssertTrue(title.appears(timeout: 10), "the stage never opened")
        // The preview speaks the fill ("... fill: E, F sharp into D ..."); the stage draws
        // it ("E F\u{266F} ..."), so the first note's letter is what they share.
        let first = run.range(of: "fill: ").flatMap { run[$0.upperBound...].first.map(String.init) } ?? run
        SetlistE2E.waitUntil("the stage never showed the fill (\(run))") {
            SetlistE2E.texts(app, FillAXID.liveFillRun).contains { $0.hasPrefix(first) }
        }
        screenshot(app, "fill-stage")
        app.typeKey("t", modifierFlags: [], in: app)
        XCTAssertTrue(
            element(app, FillAXID.liveFillTab).appears(timeout: 5),
            "T never showed the fill as tab",
        )
        SetlistE2E.waitUntil("the names stayed beside the tab") {
            SetlistE2E.texts(app, FillAXID.liveFillRun).isEmpty
        }
        screenshot(app, "fill-stage-tab")
        app.typeKey(".", modifierFlags: .command, in: app)
        XCTAssertTrue(element(app, FillAXID.endDialog).appears(timeout: 5))
        app.typeKey(.return, modifierFlags: [], in: app)
        XCTAssertTrue(title.disappears(timeout: 10))
    }

    /// The chord over the first lyric of the preview line ending in `lyric`: lines in this
    /// song carry one chord, at their start, so the point is just inside the line's top left.
    @MainActor
    private func chordAtLineStart(_ app: XCUIApplication, lyric: String) -> XCUICoordinate {
        let line = SetlistE2E.all(app, FillAXID.sheetLine)
            // The line's lyric is its label or its value (chords may lead the label).
            .matching(NSPredicate(format: "label ENDSWITH %@ OR value ENDSWITH %@", lyric, lyric))
            .firstMatch
        XCTAssertTrue(line.appears(timeout: 5), "no preview line ending in \(lyric)")
        return line.coordinate(withNormalizedOffset: .zero)
            .withOffset(CGVector(dx: 6, dy: 8))
    }

    @MainActor
    private func element(_ app: XCUIApplication, _ identifier: String) -> XCUIElement {
        SetlistE2E.element(app, identifier)
    }
}

/// Mirrors `AccessibilityID+Fill` and the library and editor IDs this suite reads.
enum FillAXID {
    static let playsBass = "segue.settings.instrument.playsBass"
    static let walkUpsPicker = "segue.settings.instrument.walkUps"
    static let sidebarLibrary = "segue.sidebar.library"
    static let songRow = "segue.library.row"
    static let editSong = "segue.song.edit"
    static let editorModeText = "segue.editor.mode.text"
    static let editorBass = "segue.editor.bass"
    static let editorDone = "segue.editor.done"
    static let sheetLine = "segue.sheet.line"
    static let sheetFillRun = "segue.sheet.fillRun"
    static let create = "segue.fill.create"
    static let editor = "segue.fill.editor"
    static let grid = "segue.fill.grid"
    static let miniTab = "segue.fill.miniTab"
    static let save = "segue.fill.save"
    static let viewFretboard = "segue.fill.view.fretboard"
    static let viewPianoRoll = "segue.fill.view.pianoRoll"
    static let pianoRoll = "segue.fill.pianoRoll"
    static let rehearseButton = "segue.library.song.rehearse"
    static let liveTitle = "segue.live.title"
    static let liveFillRun = "segue.live.fillRun"
    static let liveFillTab = "segue.live.fillTab"
    static let endDialog = "segue.live.endDialog"

    static func candidate(_ letter: String) -> String {
        "segue.fill.candidate.\(letter)"
    }

    static func candidatePlay(_ letter: String) -> String {
        "segue.fill.candidate.\(letter).play"
    }
}
