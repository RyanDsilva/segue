import AppKit
import XCTest

/// Core UX for 0.5 (docs/release/specs/WS2a-core-ux.md, test plan 6.3), driven through the
/// real UI. Each test starts from a wiped folder under `/private/tmp/segue-e2e/` with reset
/// state, a stand-in Trash (`-SegueTrashPath`), a recorded workspace (`-SegueWorkspaceLog`)
/// and a 0.3 s autosave debounce unless the test needs the shipped timing.
final class SegueCoreUXE2ETests: XCTestCase {
    var paths: Paths?
    var app: XCUIApplication?

    override func setUpWithError() throws {
        continueAfterFailure = false
        let base = URL(filePath: "/private/tmp/segue-e2e", directoryHint: .isDirectory)
            .appending(path: "coreux-\(UUID().uuidString)", directoryHint: .isDirectory)
        try? FileManager.default.removeItem(at: base)
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        paths = Paths(base: base)
    }

    override func tearDownWithError() throws {
        E2E.terminate(app)
        if let paths {
            try? FileManager.default.removeItem(at: paths.base)
        }
    }

    // MARK: - Autosave (3.4)

    @MainActor
    func testAutosaveWritesWithoutSave() throws {
        try seedSong("harbour-lights", CoreFixture.harbour)
        let app = try launch()
        let paths = try XCTUnwrap(paths)
        let editor = openEditor(app, "Harbour Lights")

        editor.typeText("\nTyped without saving", in: app)

        XCTAssertTrue(waitForFile(paths.song("harbour-lights"), contains: "Typed without saving"))
        XCTAssertTrue(waitForStatus(app, "Saved"))
        attachScreenshot(app, name: "editor-saved")
        // File > Save only confirms.
        app.typeKey("s", modifierFlags: .command, in: app)
        XCTAssertTrue(waitForStatus(app, "All changes saved", timeout: 3))
        attachScreenshot(app, name: "editor-all-changes-saved")
        XCTAssertTrue(waitForStatus(app, "Saved", timeout: 5))
        XCTAssertFalse(app.sheets.firstMatch.exists, "Save never opens a panel")

        // Outside the editor, Cmd-S confirms in the bottom bar.
        element(app, CoreAXID.editorDone).click(in: app)
        XCTAssertTrue(editor.waitForNonExistence(timeout: 10))
        app.typeKey("s", modifierFlags: .command, in: app)
        let transient = element(app, CoreAXID.transientMessage)
        XCTAssertTrue(transient.waitForExistence(timeout: 3))
        attachScreenshot(app, name: "transient-all-changes-saved")
        XCTAssertTrue(transient.waitForNonExistence(timeout: 5))
    }

    @MainActor
    func testAutosaveRealDebounce() throws {
        try seedSong("harbour-lights", CoreFixture.harbour)
        let app = try launch(autosaveDelay: nil)
        let paths = try XCTUnwrap(paths)
        let editor = openEditor(app, "Harbour Lights")

        editor.typeText("\nShipped timing", in: app)
        let typed = Date()
        // Not before the 1 s pause, and soon after it.
        XCTAssertFalse(read(paths.song("harbour-lights")).contains("Shipped timing"))
        XCTAssertTrue(waitForFile(
            paths.song("harbour-lights"),
            contains: "Shipped timing",
            timeout: 5,
        ))
        XCTAssertGreaterThan(Date().timeIntervalSince(typed), 0.8)
    }

    @MainActor
    func testSwitchingSongsFlushes() throws {
        try seedSong("harbour-lights", CoreFixture.harbour)
        try seedSong("river-song", CoreFixture.river)
        let app = try launch(autosaveDelay: nil)
        let paths = try XCTUnwrap(paths)
        let editor = openEditor(app, "Harbour Lights")

        editor.typeText("\nFlushed on switch", in: app)
        row(app, "River Song").click(in: app)

        XCTAssertTrue(editor.waitForNonExistence(timeout: 10))
        XCTAssertFalse(app.sheets.firstMatch.exists, "Switching songs must not ask")
        XCTAssertTrue(read(paths.song("harbour-lights")).contains("Flushed on switch"))
        XCTAssertTrue(waitForValue(element(app, CoreAXID.songTitle), "River Song"))
    }

    @MainActor
    func testQuitFlushes() throws {
        try seedSong("harbour-lights", CoreFixture.harbour)
        let app = try launch(autosaveDelay: nil)
        let paths = try XCTUnwrap(paths)
        let editor = openEditor(app, "Harbour Lights")

        editor.typeText("\nSaved on quit", in: app)
        app.typeKey("q", modifierFlags: .command, in: app)

        XCTAssertTrue(app.wait(for: .notRunning, timeout: 15), "The app did not quit")
        XCTAssertTrue(read(paths.song("harbour-lights")).contains("Saved on quit"))
    }

    @MainActor
    func testExternalEditConflict() throws {
        try seedSong("harbour-lights", CoreFixture.harbour)
        let app = try launch()
        let paths = try XCTUnwrap(paths)
        let file = paths.song("harbour-lights")
        let editor = openEditor(app, "Harbour Lights")
        editor.typeText("\nMine", in: app)
        XCTAssertTrue(waitForFile(file, contains: "Mine"))

        // Another app rewrites the file; the next autosave must not overwrite it.
        let external = "{title: Harbour Lights}\nEdited in another app\n"
        try Data(external.utf8).write(to: file, options: .atomic)
        editor.typeText(" and more", in: app)

        let bar = element(app, CoreAXID.editorConflictBar)
        XCTAssertTrue(bar.waitForExistence(timeout: 10), "No conflict bar")
        XCTAssertTrue(waitForStatus(app, "Not saved"))
        XCTAssertEqual(read(file), external)
        attachScreenshot(app, name: "conflict-bar")
        // Typing still works and still writes nothing.
        editor.typeText(", still mine", in: app)
        XCTAssertEqual(read(file), external)

        element(app, CoreAXID.editorConflictCopy).click(in: app)
        XCTAssertTrue(bar.waitForNonExistence(timeout: 10))
        XCTAssertTrue(wait { self.names(in: paths.library.appending(path: "songs"))
                .filter { $0.hasSuffix(".cho") }.count == 2
        })
        XCTAssertEqual(read(file), external)
        XCTAssertTrue(read(paths.song("harbour-lights-2")).contains("and more, still mine"))

        // Variant: the file is deleted in another app while the copy (now selected) is
        // being edited.
        let copy = openSelectedEditor(app)
        let copyFile = paths.song("harbour-lights-2")
        let sidecar = paths.library.appending(path: "songs/harbour-lights-2.segue.json")
        try FileManager.default.removeItem(at: copyFile)
        try? FileManager.default.removeItem(at: sidecar)
        copy.typeText("\nAfter the delete", in: app)
        XCTAssertTrue(bar.waitForExistence(timeout: 10), "No conflict bar for a deleted file")
        let saveAsNew = element(app, CoreAXID.editorConflictCopy)
        XCTAssertEqual(saveAsNew.label, "Save as New Song")
        attachScreenshot(app, name: "conflict-bar-deleted")
        saveAsNew.click(in: app)
        XCTAssertTrue(bar.waitForNonExistence(timeout: 10))
        XCTAssertTrue(wait {
            self.names(in: paths.library.appending(path: "songs")).contains { name in
                name.hasSuffix(".cho")
                    && self.read(paths.library.appending(path: "songs/\(name)"))
                    .contains("After the delete")
            }
        })
    }

    @MainActor
    func testCleanEditorPicksUpExternalEdit() throws {
        try seedSong("harbour-lights", CoreFixture.harbour)
        let app = try launch()
        let paths = try XCTUnwrap(paths)
        let file = paths.song("harbour-lights")
        let editor = openEditor(app, "Harbour Lights")
        editor.typeText("\nMine", in: app)
        XCTAssertTrue(waitForFile(file, contains: "Mine"))

        let external = "{title: Harbour Lights}\nRewritten elsewhere\n"
        try Data(external.utf8).write(to: file, options: .atomic)
        reactivate(app)

        XCTAssertTrue(wait { (editor.value as? String) == external }, "The editor kept old text")
        XCTAssertTrue(waitForStatus(app, "Saved"))
        XCTAssertFalse(element(app, CoreAXID.editorConflictBar).exists)
        XCTAssertEqual(read(file), external)
    }

    @MainActor
    func testNewSongFileFollowsTitleUntilDone() throws {
        let app = try launch()
        let paths = try XCTUnwrap(paths)
        XCTAssertTrue(element(app, CoreAXID.libraryEmpty).waitForExistence(timeout: 15))
        element(app, CoreAXID.newSong).click(in: app)
        let editor = app.textViews[CoreAXID.editorText]
        XCTAssertTrue(editor.waitForExistence(timeout: 10))
        editor.click(in: app)

        editor.typeText("{title: Ha}\n", in: app)
        XCTAssertTrue(wait { self.exists(paths.song("ha")) }, "The first autosave made no file")
        editor.typeKey("a", modifierFlags: .command, in: app)
        editor.typeText("{title: Harbour}\nLanterns\n", in: app)
        XCTAssertTrue(waitForFile(paths.song("harbour"), contains: "Lanterns"))
        element(app, CoreAXID.editorDone).click(in: app)

        XCTAssertTrue(editor.waitForNonExistence(timeout: 10))
        let songs = names(in: paths.library.appending(path: "songs"))
            .filter { $0.hasSuffix(".cho") }
        XCTAssertEqual(songs, ["harbour.cho"])
        XCTAssertTrue(waitForValue(element(app, CoreAXID.songTitle), "Harbour"))
    }

    // MARK: - Delete and Trash (3.3)

    @MainActor
    func testDeleteSongToTrashAndUndo() throws {
        try seedSong("harbour-lights", CoreFixture.harbour, id: CoreFixture.harbourID)
        try seedSong("river-song", CoreFixture.river, id: CoreFixture.riverID)
        try seedSetlist(
            "friday",
            id: CoreFixture.fridayID,
            name: "Friday",
            songIDs: [CoreFixture.riverID],
        )
        let app = try launch()
        let paths = try XCTUnwrap(paths)

        // In no setlist: File > Move to Trash (Cmd-Delete on the focused list), no dialog.
        let harbour = row(app, "Harbour Lights")
        XCTAssertTrue(harbour.waitForExistence(timeout: 15))
        harbour.click(in: app)
        app.typeKey(.delete, modifierFlags: .command, in: app)
        XCTAssertTrue(harbour.waitForNonExistence(timeout: 10))
        XCTAssertFalse(app.sheets.firstMatch.exists, "No dialog for a song in no setlist")
        XCTAssertEqual(names(in: paths.trash), ["harbour-lights.cho", "harbour-lights.segue.json"])
        XCTAssertFalse(exists(paths.song("harbour-lights")))
        app.typeKey("z", modifierFlags: .command, in: app)
        XCTAssertTrue(
            row(app, "Harbour Lights").waitForExistence(timeout: 10),
            "Undo did not restore",
        )
        XCTAssertTrue(exists(paths.song("harbour-lights")))
        XCTAssertTrue(names(in: paths.trash).isEmpty)

        try trashSongInSetlist(app, paths)
    }

    /// A song a setlist uses: the context menu asks first, naming the setlist (A23); the
    /// builder then shows it missing until Undo, and Redo trashes it again.
    @MainActor
    private func trashSongInSetlist(_ app: XCUIApplication, _ paths: Paths) throws {
        let river = row(app, "River Song")
        contextMenu(app, river, CoreAXID.songMoveToTrash)
        let confirm = element(app, CoreAXID.songDeleteConfirm)
        XCTAssertTrue(confirm.waitForExistence(timeout: 5), "No confirmation")
        let sheet = app.sheets.firstMatch
        XCTAssertTrue(sheet.staticTexts["Move “River Song” to the Trash?"].exists)
        XCTAssertTrue(sheet.staticTexts.containing(
            NSPredicate(format: "value CONTAINS %@ OR label CONTAINS %@", "Friday", "Friday"),
        ).firstMatch.exists)
        attachScreenshot(app, name: "song-trash-confirmation")
        confirm.click(in: app)
        XCTAssertTrue(river.waitForNonExistence(timeout: 10))
        XCTAssertEqual(names(in: paths.trash), ["river-song.cho", "river-song.segue.json"])

        // The builder shows the missing song; Undo resolves it again; Redo trashes again.
        let friday = element(app, CoreAXID.setlistRow)
        friday.click(in: app)
        let entry = element(app, CoreAXID.setlistEntry)
        XCTAssertTrue(wait { entry.label == "1. Missing song" }, entry.label)
        app.typeKey("z", modifierFlags: .command, in: app)
        XCTAssertTrue(
            wait { entry.label == "1. River Song" },
            "Undo did not resolve: \(entry.label)",
        )
        XCTAssertTrue(exists(paths.song("river-song")))
        app.typeKey("z", modifierFlags: [.command, .shift], in: app)
        XCTAssertTrue(wait { entry.label == "1. Missing song" }, "Redo did not trash again")
        XCTAssertFalse(exists(paths.song("river-song")))
    }

    @MainActor
    func testDeleteShortcutNeverFiresInText() throws {
        try seedSong("harbour-lights", CoreFixture.harbour)
        let app = try launch()
        let paths = try XCTUnwrap(paths)

        // In the editor, Cmd-Delete deletes to the line start.
        let editor = openEditor(app, "Harbour Lights")
        editor.typeText("\nkeep this", in: app)
        editor.typeKey(.delete, modifierFlags: .command, in: app)
        XCTAssertTrue(wait { !((editor.value as? String) ?? "").contains("keep this") })
        XCTAssertTrue(exists(paths.song("harbour-lights")))
        element(app, CoreAXID.editorDone).click(in: app)
        XCTAssertTrue(editor.waitForNonExistence(timeout: 10))

        // In the search field too.
        let search = app.searchFields[CoreAXID.librarySearch]
        search.click(in: app)
        search.typeText("harb", in: app)
        search.typeKey(.delete, modifierFlags: .command, in: app)
        XCTAssertTrue(
            wait { !((search.value as? String) ?? "").contains("harb") },
            "Cmd-Delete left \(String(describing: search.value))",
        )
        XCTAssertTrue(exists(paths.song("harbour-lights")))
        XCTAssertTrue(names(in: paths.trash).isEmpty)
        XCTAssertTrue(row(app, "Harbour Lights").exists)
    }

    // MARK: - Show in Finder (3.8)

    @MainActor
    func testShowInFinder() throws {
        try seedSong("harbour-lights", CoreFixture.harbour, id: CoreFixture.harbourID)
        try seedSetlist(
            "friday",
            id: CoreFixture.fridayID,
            name: "Friday",
            songIDs: [CoreFixture.harbourID],
        )
        let app = try launch()
        let paths = try XCTUnwrap(paths)
        let library = paths.library.path(percentEncoded: false)
        let songPath = library + "songs/harbour-lights.cho"

        // Song: the row's context menu.
        let harbour = row(app, "Harbour Lights")
        XCTAssertTrue(harbour.waitForExistence(timeout: 15))
        contextMenu(app, harbour, CoreAXID.songShowInFinder)
        XCTAssertTrue(waitForWorkspace("reveal", [songPath]), "\(workspaceCalls())")

        // Song: File > Show in Finder (Opt-Cmd-R) with the song shown.
        harbour.click(in: app)
        let before = workspaceCalls().count
        app.typeKey("r", modifierFlags: [.command, .option], in: app)
        XCTAssertTrue(wait { self.workspaceCalls().count == before + 1 })

        // Setlist: the sidebar context menu.
        let friday = element(app, CoreAXID.setlistRow)
        contextMenu(app, friday, CoreAXID.setlistRevealAction)
        XCTAssertTrue(waitForWorkspace("reveal", [library + "setlists/friday.setlist.json"]))

        // Library: Library > Show Library in Finder.
        app.menuBars.menuBarItems["Library"].click(in: app)
        app.menuBars.menuItems["Show Library in Finder"].click(in: app)
        XCTAssertTrue(waitForWorkspace("reveal", [library]), "\(workspaceCalls())")
    }
}
