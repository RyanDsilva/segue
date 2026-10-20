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
        E2E.terminate(app)
        if let libraryRoot {
            try? FileManager.default.removeItem(at: libraryRoot)
        }
    }

    @MainActor
    func testSongToSetlistToLiveView() throws {
        let root = try XCTUnwrap(libraryRoot)
        let app = XCUIApplication()
        self.app = app
        E2E.launch(app, arguments: [
            "-SegueLibraryPath", root.path(percentEncoded: false),
            "-SegueResetState", "YES",
            // Shortcut hooks are recorded, never run, in tests.
            "-SegueShortcutLog", root.appending(path: "shortcuts.log").path(percentEncoded: false),
        ])

        // Clean baseline: an empty library.
        XCTAssertTrue(element(app, AXID.libraryEmpty).appears(timeout: 15))

        // Create two songs by typing raw ChordPro (one romanized Hindi). The second is saved
        // by autosave when navigating away mid-edit, with no prompt.
        createSong(app, source: Fixture.english, title: "Harbour Lights")
        createSongSavingBySwitching(app, source: Fixture.hindi, title: "Pyaar Ki Raah")
        XCTAssertEqual(songRows(app).count, 2)
        attachScreenshot(app, name: "library-with-songs")

        try editSavingBySwitching(app, root: root)
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
        E2E.launch(first, arguments: [
            "-SegueLibraryPath", root.path(percentEncoded: false),
            "-SegueResetState", "YES",
            "-SegueRememberLibrary", "YES",
        ])
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
        // Create a setlist from the sidebar; the builder opens on it, empty.
        element(app, AXID.newSetlist).click(in: app)
        let name = app.textFields[AXID.newSetlistName]
        XCTAssertTrue(name.appears(timeout: 5))
        name.click(in: app)
        name.typeText("Friday Set", in: app)
        app.buttons[AXID.newSetlistCreate].click(in: app)
        XCTAssertTrue(app.staticTexts[AXID.setlistTitle].appears(timeout: 5))
        XCTAssertEqual(app.staticTexts[AXID.setlistTitle].value as? String, "Friday Set")
        XCTAssertTrue(element(app, AXID.setlistDropZone).exists)

        // The builder's library column searches the index: "pyar" finds "Pyaar Ki Raah".
        filterBuilder(app, "harbour", expect: "Harbour Lights")
        addSong(app, title: "Harbour Lights")
        filterBuilder(app, "pyar", expect: "Pyaar Ki Raah")
        addSong(app, title: "Pyaar Ki Raah")
        let entries = app.descendants(matching: .any).matching(identifier: AXID.setlistEntry)
        XCTAssertTrue(wait(for: entries, count: 2))
        XCTAssertTrue(Self.text(entries.element(boundBy: 0)).contains("Harbour Lights"))
        XCTAssertTrue(Self.text(entries.element(boundBy: 1)).contains("Pyaar Ki Raah"))
        attachScreenshot(app, name: "setlist-builder")
    }

    @MainActor
    private func perform(_ app: XCUIApplication) {
        // Start show: the stage shows the first song, then the next, then ends.
        element(app, AXID.setlistStartShow).click(in: app)
        let start = element(app, AXID.checklistStart)
        if start.appears(timeout: 5) {
            start.click(in: app)
        }
        let liveTitle = app.staticTexts[AXID.liveTitle]
        XCTAssertTrue(liveTitle.appears(timeout: 10))
        XCTAssertTrue(waitForValue(liveTitle, "Harbour Lights"))
        let liveView = element(app, AXID.liveView)
        let chords = liveView.descendants(matching: .staticText)
            .matching(identifier: AXID.sheetChord)
        XCTAssertTrue(chords.firstMatch.appears(timeout: 5))
        attachScreenshot(app, name: "live-view-song-1")

        app.typeKey(.rightArrow, modifierFlags: [], in: app)
        XCTAssertTrue(waitForValue(liveTitle, "Pyaar Ki Raah"))
        attachScreenshot(app, name: "live-view-song-2")
        app.typeKey(".", modifierFlags: .command, in: app)
        let confirm = element(app, AXID.liveEndConfirm)
        XCTAssertTrue(confirm.appears(timeout: 5))
        confirm.click(in: app)
        XCTAssertTrue(liveTitle.disappears(timeout: 10))
        XCTAssertTrue(app.staticTexts[AXID.setlistTitle].appears(timeout: 5))
    }

    /// Second launch without `-SegueLibraryPath`: the app resolves the security-scoped
    /// bookmark the first launch stored and reopens the same library, songs included.
    @MainActor
    private func relaunchFromStoredBookmark(expecting titles: [String]) {
        let relaunched = XCUIApplication()
        app = relaunched
        E2E.launch(relaunched, arguments: ["-SegueTestDefaults", "YES"])
        XCTAssertFalse(
            element(relaunched, AXID.chooserMessage).appears(timeout: 3),
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
        if MainActor.assumeIsolated({ E2E.isExpectedExit(issue) }) {
            return
        }
        let app = app
        MainActor.assumeIsolated {
            for attachment in E2E.failureAttachments(for: app) {
                issue.add(attachment)
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
        element(app, AXID.newSong).click(in: app)
        let editor = app.textViews[AXID.editorText]
        XCTAssertTrue(editor.appears(timeout: 5))
        editor.click(in: app)
        editor.typeText(source, in: app)
        // The preview renders the typed title before saving.
        let preview = element(app, AXID.editorPreview)
        XCTAssertTrue(waitForValue(preview.staticTexts[AXID.songTitle], title))
        // Search lives in the song list column, never beside the editor's Done.
        let search = app.searchFields[AXID.librarySearch]
        XCTAssertTrue(search.exists)
        XCTAssertLessThanOrEqual(search.frame.maxX, editor.frame.minX)
        XCTAssertLessThan(search.frame.maxX, app.buttons[AXID.editorDone].frame.minX)
        return editor
    }

    @MainActor
    private func createSong(_ app: XCUIApplication, source: String, title: String) {
        let editor = typeNewSong(app, source: source, title: title)
        attachScreenshot(app, name: "editor-new-song")
        app.buttons[AXID.editorDone].click(in: app)
        // Saved: the detail pane shows the rendered song and the list has its row.
        XCTAssertTrue(editor.disappears(timeout: 10))
        XCTAssertTrue(waitForValue(app.staticTexts[AXID.songTitle], title))
        XCTAssertTrue(row(app, title).appears(timeout: 10))
    }

    /// Types a new song, then clicks another song at once: no prompt, the song is saved
    /// (autosave flushes on navigation) and the other song is shown.
    @MainActor
    private func createSongSavingBySwitching(
        _ app: XCUIApplication,
        source: String,
        title: String,
    ) {
        let editor = typeNewSong(app, source: source, title: title)
        row(app, "Harbour Lights").click(in: app)
        XCTAssertTrue(editor.disappears(timeout: 10))
        XCTAssertFalse(app.sheets.firstMatch.exists, "Navigating must not ask")
        XCTAssertTrue(waitForValue(app.staticTexts[AXID.songTitle], "Harbour Lights"))
        XCTAssertTrue(row(app, title).appears(timeout: 10))
    }

    /// Edits a saved song, then switches songs: the edit is on disk with no prompt. The
    /// file is then put back as it was, from outside the app (the later checks expect the
    /// typed fixture).
    @MainActor
    private func editSavingBySwitching(_ app: XCUIApplication, root: URL) throws {
        row(app, "Harbour Lights").click(in: app)
        XCTAssertTrue(waitForValue(app.staticTexts[AXID.songTitle], "Harbour Lights"))
        element(app, AXID.editSong).click(in: app)
        element(app, "segue.editor.mode.text").click(in: app) // Songs open on the visual canvas.
        let editor = app.textViews[AXID.editorText]
        XCTAssertTrue(editor.appears(timeout: 5))
        editor.click(in: app)
        editor.typeText("Saved by switching\n", in: app)

        row(app, "Pyaar Ki Raah").click(in: app)
        XCTAssertTrue(editor.disappears(timeout: 10))
        XCTAssertFalse(app.sheets.firstMatch.exists, "Navigating must not ask")
        XCTAssertTrue(waitForValue(app.staticTexts[AXID.songTitle], "Pyaar Ki Raah"))
        let file = root.appending(path: "songs/harbour-lights.cho")
        XCTAssertTrue(try String(contentsOf: file, encoding: .utf8).contains("Saved by switching"))
        try Data(Fixture.english.utf8).write(to: file, options: .atomic)
    }

    @MainActor
    private func filterBuilder(_ app: XCUIApplication, _ query: String, expect title: String) {
        let field = app.searchFields[AXID.builderSearch]
        XCTAssertTrue(field.appears(timeout: 5))
        field.click(in: app)
        field.typeKey("a", modifierFlags: .command, in: app)
        field.typeText(query, in: app)
        let rows = app.descendants(matching: .any).matching(identifier: AXID.builderLibraryRow)
        XCTAssertTrue(
            E2E.waitUntil { rows.count == 1 && rows.firstMatch.label == title },
            "Builder search \"\(query)\" should list only \(title)",
        )
    }

    @MainActor
    private func search(_ app: XCUIApplication, _ query: String) {
        let field = app.searchFields[AXID.librarySearch]
        XCTAssertTrue(field.appears(timeout: 5))
        field.click(in: app)
        field.typeKey("a", modifierFlags: .command, in: app)
        if query.isEmpty {
            field.typeKey(.delete, modifierFlags: [], in: app)
        } else {
            field.typeText(query, in: app)
        }
    }

    @MainActor
    private func addSong(_ app: XCUIApplication, title: String) {
        let row = app.descendants(matching: .any).matching(identifier: AXID.builderLibraryRow)
            .matching(NSPredicate(format: "label == %@", title))
            .firstMatch
        XCTAssertTrue(row.appears(timeout: 5), "No library row for \(title)")
        row.buttons[AXID.builderAdd].click(in: app)
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
            XCTAssertEqual(sidecar["schemaVersion"] as? Int, 3) // Phase 2: cues, live prefs.
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
        XCTAssertEqual(setlist["schemaVersion"] as? Int, 3) // Phase 3: breaks, changeover.
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

    private static func text(_ element: any XCUIElementSnapshot) -> String {
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
        let rows = { E2E.snapshots(app, identifier: AXID.songRow).map(Self.text) }
        let matched = E2E.waitUntil {
            let labels = rows()
            return labels.count == titles.count
                && zip(labels, titles).allSatisfy { $0.hasPrefix($1) }
        }
        let found = rows()
        XCTAssertTrue(matched, "Expected rows \(titles), got \(found)")
    }

    private func wait(for query: XCUIElementQuery, count: Int) -> Bool {
        E2E.waitUntil { query.count == count }
    }

    private func waitForValue(_ element: XCUIElement, _ value: String) -> Bool {
        element.hasValue(value)
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
    static let songRow = "segue.library.row"
    static let newSong = "segue.library.newSong"
    static let libraryEmpty = "segue.library.empty"
    static let songTitle = "segue.song.title"
    static let editorText = "segue.editor.text"
    static let editSong = "segue.song.edit"
    static let librarySearch = "segue.library.search"
    static let editorDone = "segue.editor.done"
    static let editorPreview = "segue.editor.preview"
    static let sheetChord = "segue.sheet.chord"
    static let newSetlist = "segue.setlists.new"
    static let newSetlistName = "segue.setlists.new.name"
    static let newSetlistCreate = "segue.setlists.new.create"
    static let setlistTitle = "segue.setlist.title"
    static let setlistEntry = "segue.setlist.entry"
    static let setlistStartShow = "segue.setlist.startShow"
    static let setlistDropZone = "segue.setlist.dropZone"
    static let builderSearch = "segue.builder.search"
    static let builderLibraryRow = "segue.builder.library.row"
    static let builderAdd = "segue.builder.add"
    static let liveView = "segue.live"
    static let liveTitle = "segue.live.title"
    static let liveEndConfirm = "segue.live.endConfirm"
    static let checklistStart = "segue.live.checklist.start"
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
