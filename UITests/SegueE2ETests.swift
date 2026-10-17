import XCTest

/// Phase 0 walking-skeleton E2E: one song travels add -> library on disk -> index ->
/// setlist -> live view, driven through the real UI on a fresh temp library.
///
/// The library lives under `/private/tmp/segue-e2e/`, the only path the Debug-Personal
/// sandbox exception allows (App/Segue-Debug.entitlements).
final class SegueE2ETests: XCTestCase {
    private var libraryRoot: URL?
    private var app: XCUIApplication?

    override func setUpWithError() throws {
        continueAfterFailure = false
        let root = URL(filePath: "/private/tmp/segue-e2e", directoryHint: .isDirectory)
            .appending(path: "run-\(UUID().uuidString)", directoryHint: .isDirectory)
        try? FileManager.default.removeItem(at: root)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        libraryRoot = root
    }

    override func tearDownWithError() throws {
        if let libraryRoot {
            try? FileManager.default.removeItem(at: libraryRoot)
        }
    }

    @MainActor
    func testSongToSetlistToLiveView() throws {
        let root = try XCTUnwrap(libraryRoot)
        let app = XCUIApplication()
        self.app = app
        app.launchArguments = [
            "-SegueLibraryPath", root.path(percentEncoded: false),
            "-SegueResetState", "YES",
        ]
        app.launch()

        // Clean baseline: an empty library.
        XCTAssertTrue(element(app, AXID.libraryEmpty).waitForExistence(timeout: 15))

        // Create two songs by typing raw ChordPro (one romanized Hindi). The second is saved
        // from the unsaved-changes prompt by navigating away mid-edit.
        createSong(app, source: Fixture.english, title: "Harbour Lights")
        createSongSavingFromPrompt(app, source: Fixture.hindi, title: "Pyaar Ki Raah")
        XCTAssertEqual(songRows(app).count, 2)
        attachScreenshot(app, name: "library-with-songs")

        discardEditFromPrompt(app)
        searchLibrary(app)
        buildSetlist(app)
        perform(app)
        try assertLibraryOnDisk(root)
        app.terminate()
    }

    /// AC3: a second launch reopens the library from the stored security-scoped bookmark. The
    /// first launch stores the temp library as the bookmark (`-SegueRememberLibrary`), as the
    /// open panel would; the second has no library override, only the test defaults suite.
    @MainActor
    func testSecondLaunchReopensLibraryFromStoredBookmark() throws {
        let root = try XCTUnwrap(libraryRoot)
        try FileManager.default.createDirectory(
            at: root.appending(path: "songs", directoryHint: .isDirectory),
            withIntermediateDirectories: true,
        )
        try Data(Fixture.english.utf8).write(to: root.appending(path: "songs/harbour.cho"))

        let first = XCUIApplication()
        app = first
        first.launchArguments = [
            "-SegueLibraryPath", root.path(percentEncoded: false),
            "-SegueResetState", "YES",
            "-SegueRememberLibrary", "YES",
        ]
        first.launch()
        waitForRows(first, titles: ["Harbour Lights"])
        // The bookmark was stored without complaint (a failure shows in the error banner).
        XCTAssertFalse(first.buttons["Dismiss"].exists)
        first.terminate()

        relaunchFromStoredBookmark(expecting: ["Harbour Lights"])
    }

    // MARK: - Steps

    @MainActor
    private func searchLibrary(_ app: XCUIApplication) {
        // Search, including a romanization variant ("pyar" finds "Pyaar").
        search(app, "pyar")
        waitForRows(app, titles: ["Pyaar Ki Raah"])
        attachScreenshot(app, name: "search-pyar")
        search(app, "harbour")
        waitForRows(app, titles: ["Harbour Lights"])
        search(app, "")
        waitForRows(app, titles: ["Harbour Lights", "Pyaar Ki Raah"])
    }

    @MainActor
    private func buildSetlist(_ app: XCUIApplication) {
        // Create a setlist and add both songs.
        element(app, AXID.sidebarSetlists).click()
        element(app, AXID.newSetlist).click()
        let name = app.textFields[AXID.newSetlistName]
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        name.click()
        name.typeText("Friday Set")
        app.buttons[AXID.newSetlistCreate].click()
        XCTAssertTrue(app.staticTexts[AXID.setlistTitle].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts[AXID.setlistTitle].value as? String, "Friday Set")
        XCTAssertTrue(element(app, AXID.setlistEmpty).exists)

        // The toolbar's add button is labelled, not a bare "+".
        let addSongs = element(app, AXID.setlistAddSongs)
        XCTAssertEqual(addSongs.label, "Add Songs")
        addSongs.click()
        // The sheet searches the index: "pyar" finds "Pyaar Ki Raah" only.
        filterAddSongs(app, "harbour", expect: "Harbour Lights")
        addSong(app, title: "Harbour Lights")
        filterAddSongs(app, "pyar", expect: "Pyaar Ki Raah")
        addSong(app, title: "Pyaar Ki Raah")
        attachScreenshot(app, name: "add-songs-sheet")
        app.buttons[AXID.addSongsDone].click()
        let entries = app.descendants(matching: .any).matching(identifier: AXID.setlistEntry)
        XCTAssertTrue(wait(for: entries, count: 2))
        XCTAssertTrue(Self.text(entries.element(boundBy: 0)).contains("Harbour Lights"))
        XCTAssertTrue(Self.text(entries.element(boundBy: 1)).contains("Pyaar Ki Raah"))
        attachScreenshot(app, name: "setlist-detail")
    }

    @MainActor
    private func perform(_ app: XCUIApplication) {
        // Perform: full-screen stage shows the first song's title, meta line and chords.
        element(app, AXID.setlistPerform).click()
        let liveTitle = app.staticTexts[AXID.liveTitle]
        XCTAssertTrue(liveTitle.waitForExistence(timeout: 10))
        XCTAssertEqual(liveTitle.value as? String, "Harbour Lights")
        XCTAssertEqual(app.staticTexts[AXID.liveMeta].value as? String, "G, capo 2, 96")
        let liveView = element(app, AXID.liveView)
        let chords = liveView.descendants(matching: .staticText)
            .matching(identifier: AXID.sheetChord)
        XCTAssertTrue(chords.firstMatch.waitForExistence(timeout: 5))
        XCTAssertEqual(chords.firstMatch.value as? String, "G")
        XCTAssertEqual(app.staticTexts[AXID.liveUpNext].value as? String, "Pyaar Ki Raah")
        attachScreenshot(app, name: "live-view-song-1")

        // Next song, then back, then exit.
        app.typeKey(.rightArrow, modifierFlags: [])
        XCTAssertTrue(waitForValue(liveTitle, "Pyaar Ki Raah"))
        XCTAssertEqual(app.staticTexts[AXID.livePosition].value as? String, "2 of 2")
        attachScreenshot(app, name: "live-view-song-2")
        app.typeKey(.leftArrow, modifierFlags: [])
        XCTAssertTrue(waitForValue(liveTitle, "Harbour Lights"))
        app.typeKey(.space, modifierFlags: [])
        XCTAssertTrue(waitForValue(liveTitle, "Pyaar Ki Raah"))
        app.typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(liveTitle.waitForNonExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts[AXID.setlistTitle].waitForExistence(timeout: 5))
    }

    /// Second launch without `-SegueLibraryPath`: the app resolves the security-scoped
    /// bookmark the first launch stored and reopens the same library, songs included.
    @MainActor
    private func relaunchFromStoredBookmark(expecting titles: [String]) {
        let relaunched = XCUIApplication()
        app = relaunched
        relaunched.launchArguments = ["-SegueTestDefaults", "YES"]
        relaunched.launch()
        XCTAssertFalse(
            element(relaunched, AXID.chooserMessage).waitForExistence(timeout: 3),
            "The library chooser appeared: the stored bookmark did not reopen the library",
        )
        waitForRows(relaunched, titles: titles)
        attachScreenshot(relaunched, name: "relaunch-from-bookmark")
        relaunched.terminate()
    }

    /// On failure, attach what the app looked like (screenshot + accessibility tree).
    override func record(_ issue: XCTIssue) {
        // XCTest calls this on the main thread, where the test body runs.
        nonisolated(unsafe) var issue = issue
        let app = app
        if let app {
            MainActor.assumeIsolated {
                issue.add(XCTAttachment(screenshot: app.screenshot()))
                issue.add(XCTAttachment(string: app.debugDescription))
            }
        }
        super.record(issue)
    }

    /// Opens the new-song editor and types `source`; returns the editor.
    @MainActor
    @discardableResult
    private func typeNewSong(_ app: XCUIApplication, source: String, title: String)
        -> XCUIElement
    {
        element(app, AXID.newSong).click()
        let editor = app.textViews[AXID.editorText]
        XCTAssertTrue(editor.waitForExistence(timeout: 5))
        editor.click()
        editor.typeText(source)
        // The preview renders the typed title before saving.
        let preview = element(app, AXID.editorPreview)
        XCTAssertTrue(waitForValue(preview.staticTexts[AXID.songTitle], title))
        // Search lives in the song list column, never beside the editor's Cancel/Save.
        let search = app.searchFields[AXID.librarySearch]
        XCTAssertTrue(search.exists)
        XCTAssertLessThanOrEqual(search.frame.maxX, editor.frame.minX)
        XCTAssertLessThan(search.frame.maxX, app.buttons[AXID.editorCancel].frame.minX)
        return editor
    }

    @MainActor
    private func createSong(_ app: XCUIApplication, source: String, title: String) {
        let editor = typeNewSong(app, source: source, title: title)
        attachScreenshot(app, name: "editor-new-song")
        app.buttons[AXID.editorSave].click()
        // Saved: the detail pane shows the rendered song and the list has its row.
        XCTAssertTrue(editor.waitForNonExistence(timeout: 10))
        XCTAssertTrue(waitForValue(app.staticTexts[AXID.songTitle], title))
        XCTAssertTrue(row(app, title).waitForExistence(timeout: 10))
    }

    /// Types a new song, then clicks another song: the unsaved-changes prompt appears and
    /// "Save" creates the song before navigating.
    @MainActor
    private func createSongSavingFromPrompt(
        _ app: XCUIApplication,
        source: String,
        title: String,
    ) {
        let editor = typeNewSong(app, source: source, title: title)
        row(app, "Harbour Lights").click()
        let save = unsavedPromptButton(app, "Save")
        XCTAssertTrue(save.waitForExistence(timeout: 5), "No unsaved-changes prompt")
        attachScreenshot(app, name: "unsaved-changes-prompt")
        save.click()
        XCTAssertTrue(editor.waitForNonExistence(timeout: 10))
        XCTAssertTrue(waitForValue(app.staticTexts[AXID.songTitle], "Harbour Lights"))
        XCTAssertTrue(row(app, title).waitForExistence(timeout: 10))
    }

    /// Edits a saved song, then navigates away: "Cancel" keeps the editor and its text,
    /// "Discard Changes" drops the edit (the file on disk is checked later).
    @MainActor
    private func discardEditFromPrompt(_ app: XCUIApplication) {
        row(app, "Harbour Lights").click()
        XCTAssertTrue(waitForValue(app.staticTexts[AXID.songTitle], "Harbour Lights"))
        element(app, AXID.editSong).click()
        element(app, "segue.editor.mode.text").click() // Songs open on the visual canvas.
        let editor = app.textViews[AXID.editorText]
        XCTAssertTrue(editor.waitForExistence(timeout: 5))
        editor.click()
        editor.typeText("Unsaved line\n")

        row(app, "Pyaar Ki Raah").click()
        let cancel = unsavedPromptButton(app, "Cancel")
        XCTAssertTrue(cancel.waitForExistence(timeout: 5), "No unsaved-changes prompt")
        cancel.click()
        XCTAssertTrue(cancel.waitForNonExistence(timeout: 5))
        XCTAssertTrue(editor.exists, "Cancel must keep the editor open")
        XCTAssertTrue((editor.value as? String ?? "").contains("Unsaved line"))

        row(app, "Pyaar Ki Raah").click()
        let discard = unsavedPromptButton(app, "Discard Changes")
        XCTAssertTrue(discard.waitForExistence(timeout: 5), "No unsaved-changes prompt")
        discard.click()
        XCTAssertTrue(editor.waitForNonExistence(timeout: 10))
        XCTAssertTrue(waitForValue(app.staticTexts[AXID.songTitle], "Pyaar Ki Raah"))
    }

    /// A button of the unsaved-changes alert (a sheet on the main window).
    @MainActor
    private func unsavedPromptButton(_ app: XCUIApplication, _ title: String) -> XCUIElement {
        app.sheets.buttons[title].firstMatch
    }

    @MainActor
    private func filterAddSongs(_ app: XCUIApplication, _ query: String, expect title: String) {
        let field = app.searchFields[AXID.addSongsSearch]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.click()
        field.typeKey("a", modifierFlags: .command)
        field.typeText(query)
        let rows = app.descendants(matching: .any).matching(identifier: AXID.addSongsRow)
        let onlyMatch = NSPredicate { _, _ in
            rows.count == 1 && rows.firstMatch.staticTexts[title].exists
        }
        let expectation = XCTNSPredicateExpectation(predicate: onlyMatch, object: nil)
        XCTAssertEqual(
            XCTWaiter().wait(for: [expectation], timeout: 10),
            .completed,
            "Add Songs search \"\(query)\" should list only \(title)",
        )
    }

    @MainActor
    private func search(_ app: XCUIApplication, _ query: String) {
        let field = app.searchFields[AXID.librarySearch]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.click()
        field.typeKey("a", modifierFlags: .command)
        if query.isEmpty {
            field.typeKey(.delete, modifierFlags: [])
        } else {
            field.typeText(query)
        }
    }

    @MainActor
    private func addSong(_ app: XCUIApplication, title: String) {
        let rows = app.descendants(matching: .any).matching(identifier: AXID.addSongsRow)
        let songRow = rows
            .containing(NSPredicate(format: "label == %@ OR value == %@", title, title))
            .firstMatch
        XCTAssertTrue(songRow.waitForExistence(timeout: 5), "No add row for \(title)")
        songRow.buttons[AXID.addSongsAdd].click()
    }

    // MARK: - Disk

    private func assertLibraryOnDisk(_ root: URL) throws {
        let songs = root.appending(path: "songs", directoryHint: .isDirectory)
        let files = try FileManager.default.contentsOfDirectory(atPath: songs.path)
        let chordPro = files.filter { $0.hasSuffix(".cho") }.sorted()
        XCTAssertEqual(chordPro.count, 2, "songs/: \(files)")

        var idsByTitle: [String: String] = [:]
        for (fileName, expected) in [
            ("Harbour Lights", Fixture.english),
            ("Pyaar Ki Raah", Fixture.hindi),
        ] {
            // The .cho holds exactly what was typed (lyrics untouched, no smart quotes).
            let match = try chordPro.first { name in
                try String(contentsOf: songs.appending(path: name), encoding: .utf8) == expected
            }
            let cho = try XCTUnwrap(match, "No .cho with the typed source for \(fileName)")
            let sidecarURL = songs.appending(path: cho.dropLast(".cho".count) + ".segue.json")
            let sidecar = try XCTUnwrap(
                JSONSerialization.jsonObject(with: Data(contentsOf: sidecarURL)) as? [String: Any],
            )
            XCTAssertEqual(sidecar["schemaVersion"] as? Int, 2) // Phase 1: display prefs.
            let id = try XCTUnwrap(sidecar["id"] as? String)
            XCTAssertEqual(id.count, 26, "ULID expected, got \(id)")
            idsByTitle[fileName] = id
        }

        let setlists = root.appending(path: "setlists", directoryHint: .isDirectory)
        let setlistFiles = try FileManager.default.contentsOfDirectory(atPath: setlists.path)
            .filter { $0.hasSuffix(".setlist.json") }
        XCTAssertEqual(setlistFiles.count, 1)
        let setlistURL = try setlists.appending(path: XCTUnwrap(setlistFiles.first))
        let setlist = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(contentsOf: setlistURL)) as? [String: Any],
        )
        XCTAssertEqual(setlist["name"] as? String, "Friday Set")
        XCTAssertEqual(setlist["schemaVersion"] as? Int, 1)
        let entries = try XCTUnwrap(setlist["entries"] as? [[String: Any]])
        XCTAssertEqual(
            entries.compactMap { $0["songId"] as? String },
            [idsByTitle["Harbour Lights"], idsByTitle["Pyaar Ki Raah"]].compactMap(\.self),
        )
    }
}

// MARK: - Queries

@MainActor
extension SegueE2ETests {
    private func element(_ app: XCUIApplication, _ identifier: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    /// The visible text of an element: combined SwiftUI rows expose it as their value.
    private static func text(_ element: XCUIElement) -> String {
        element.label.isEmpty ? (element.value as? String ?? "") : element.label
    }

    private func songRows(_ app: XCUIApplication) -> XCUIElementQuery {
        app.descendants(matching: .any).matching(identifier: AXID.songRow)
    }

    private func row(_ app: XCUIApplication, _ title: String) -> XCUIElement {
        songRows(app)
            .matching(NSPredicate(
                format: "label BEGINSWITH %@ OR value BEGINSWITH %@",
                title,
                title,
            ))
            .firstMatch
    }

    private func waitForRows(_ app: XCUIApplication, titles: [String]) {
        let matched = NSPredicate { _, _ in
            let labels = self.songRows(app).allElementsBoundByIndex.map(Self.text)
            return labels.count == titles.count
                && zip(labels, titles).allSatisfy { $0.hasPrefix($1) }
        }
        let expectation = XCTNSPredicateExpectation(predicate: matched, object: nil)
        let result = XCTWaiter().wait(for: [expectation], timeout: 10)
        let found = songRows(app).allElementsBoundByIndex.map(Self.text)
        XCTAssertEqual(result, .completed, "Expected rows \(titles), got \(found)")
    }

    private func wait(for query: XCUIElementQuery, count: Int) -> Bool {
        let predicate = NSPredicate { _, _ in query.count == count }
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: nil)
        return XCTWaiter().wait(for: [expectation], timeout: 10) == .completed
    }

    private func waitForValue(_ element: XCUIElement, _ value: String) -> Bool {
        let predicate = NSPredicate(format: "value == %@", value)
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: element)
        return XCTWaiter().wait(for: [expectation], timeout: 10) == .completed
    }

    private func attachScreenshot(_ app: XCUIApplication, name: String) {
        // The stage covers the screen; elsewhere capture just the main window.
        let isLive = app.staticTexts[AXID.liveTitle].exists
        let window = app.windows.firstMatch
        let screenshot = isLive || !window.exists ? app.screenshot() : window.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}

/// Accessibility identifiers (mirrors `AccessibilityID` in SegueUI).
private enum AXID {
    static let chooserMessage = "segue.chooser.message"
    static let sidebarSetlists = "segue.sidebar.setlists"
    static let songRow = "segue.library.row"
    static let newSong = "segue.library.newSong"
    static let libraryEmpty = "segue.library.empty"
    static let songTitle = "segue.song.title"
    static let editorText = "segue.editor.text"
    static let editorCancel = "segue.editor.cancel"
    static let editSong = "segue.song.edit"
    static let librarySearch = "segue.library.search"
    static let addSongsSearch = "segue.addSongs.search"
    static let editorSave = "segue.editor.save"
    static let editorPreview = "segue.editor.preview"
    static let sheetChord = "segue.sheet.chord"
    static let newSetlist = "segue.setlists.new"
    static let newSetlistName = "segue.setlists.new.name"
    static let newSetlistCreate = "segue.setlists.new.create"
    static let setlistTitle = "segue.setlist.title"
    static let setlistEntry = "segue.setlist.entry"
    static let setlistAddSongs = "segue.setlist.addSongs"
    static let setlistPerform = "segue.setlist.perform"
    static let setlistEmpty = "segue.setlist.empty"
    static let addSongsRow = "segue.addSongs.row"
    static let addSongsAdd = "segue.addSongs.add"
    static let addSongsDone = "segue.addSongs.done"
    static let liveView = "segue.live"
    static let liveTitle = "segue.live.title"
    static let liveMeta = "segue.live.meta"
    static let livePosition = "segue.live.position"
    static let liveUpNext = "segue.live.upNext"
}

/// Songs typed in the E2E run. Original text written for this test (licence-free).
private enum Fixture {
    static let english = """
    {title: Harbour Lights}
    {artist: The Test Band}
    {key: G}
    {capo: 2}
    {tempo: 96}

    {start_of_verse}
    [G]Lanterns on the [C]water, "steady" -- now
    [Em]Calling me back [D]home
    {end_of_verse}

    {start_of_chorus}
    [C]Harbour [G]lights, [D]guide me
    {end_of_chorus}

    """

    static let hindi = """
    {title: Pyaar Ki Raah}
    {artist: Test Kalakaar}
    {key: D}

    {start_of_verse}
    [D]Dil ki baat [G]kehni hai
    [A]Tere bina [D]rehna nahin
    {end_of_verse}

    {start_of_chorus}
    [G]Pyaar ki [A]raah pe [D]chalte hain
    {end_of_chorus}

    {chorus}

    """
}
