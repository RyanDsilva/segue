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
        XCTAssertTrue(editor.disappears(timeout: 10))
        app.typeKey("s", modifierFlags: .command, in: app)
        let transient = element(app, CoreAXID.transientMessage)
        XCTAssertTrue(transient.appears(timeout: 3))
        attachScreenshot(app, name: "transient-all-changes-saved")
        XCTAssertTrue(transient.disappears(timeout: 5))
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

        XCTAssertTrue(editor.disappears(timeout: 10))
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

        XCTAssertTrue(app.reaches(.notRunning, timeout: 15), "The app did not quit")
        XCTAssertTrue(read(paths.song("harbour-lights")).contains("Saved on quit"))
    }

    /// Edits made in another app (B2: one scenario, one seeded song): a clean editor picks
    /// them up; an edited one shows the conflict bar and saves a copy; a file deleted
    /// elsewhere is saved as a new song.
    @MainActor
    func testExternalEdits() throws {
        try seedSong("harbour-lights", CoreFixture.harbour)
        let app = try launch()
        let paths = try XCTUnwrap(paths)
        let file = paths.song("harbour-lights")
        let editor = openEditor(app, "Harbour Lights")
        editor.typeText("\nMine", in: app)
        XCTAssertTrue(waitForFile(file, contains: "Mine"))
        // The save is complete (the editor is clean), not just its bytes on disk.
        XCTAssertTrue(waitForStatus(app, "Saved"))

        // Clean (saved) editor: another app's rewrite replaces its text on activation.
        let rewritten = "{title: Harbour Lights}\nRewritten elsewhere\n"
        try Data(rewritten.utf8).write(to: file, options: .atomic)
        reactivate(app)
        XCTAssertTrue(wait { (editor.value as? String) == rewritten }, "The editor kept old text")
        XCTAssertTrue(waitForStatus(app, "Saved"))
        XCTAssertFalse(element(app, CoreAXID.editorConflictBar).exists)
        XCTAssertEqual(read(file), rewritten)

        try conflictWhileEditing(app, paths, editor)
    }

    /// Another app rewrites the file while the editor has typing in it: the next autosave
    /// must not overwrite it.
    @MainActor
    private func conflictWhileEditing(
        _ app: XCUIApplication,
        _ paths: Paths,
        _ editor: XCUIElement,
    ) throws {
        let file = paths.song("harbour-lights")
        editor.typeKey(.downArrow, modifierFlags: .command, in: app)
        editor.typeText("\nMine", in: app)
        XCTAssertTrue(waitForFile(file, contains: "Mine"))
        // The save is complete (the editor is clean), not just its bytes on disk.
        XCTAssertTrue(waitForStatus(app, "Saved"))

        let external = "{title: Harbour Lights}\nEdited in another app\n"
        try Data(external.utf8).write(to: file, options: .atomic)
        editor.typeText(" and more", in: app)

        let bar = element(app, CoreAXID.editorConflictBar)
        XCTAssertTrue(bar.appears(timeout: 10), "No conflict bar")
        XCTAssertTrue(waitForStatus(app, "Not saved"))
        XCTAssertEqual(read(file), external)
        attachScreenshot(app, name: "conflict-bar")
        // Typing still works and still writes nothing.
        editor.typeText(", still mine", in: app)
        XCTAssertEqual(read(file), external)

        element(app, CoreAXID.editorConflictCopy).click(in: app)
        XCTAssertTrue(bar.disappears(timeout: 10))
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
        XCTAssertTrue(bar.appears(timeout: 10), "No conflict bar for a deleted file")
        let saveAsNew = element(app, CoreAXID.editorConflictCopy)
        XCTAssertEqual(saveAsNew.label, "Save as New Song")
        attachScreenshot(app, name: "conflict-bar-deleted")
        saveAsNew.click(in: app)
        XCTAssertTrue(bar.disappears(timeout: 10))
        XCTAssertTrue(wait {
            self.names(in: paths.library.appending(path: "songs")).contains { name in
                name.hasSuffix(".cho")
                    && self.read(paths.library.appending(path: "songs/\(name)"))
                    .contains("After the delete")
            }
        })
    }

    @MainActor
    func testNewSongFileFollowsTitleUntilDone() throws {
        let app = try launch()
        let paths = try XCTUnwrap(paths)
        XCTAssertTrue(element(app, CoreAXID.libraryEmpty).appears(timeout: 15))
        element(app, CoreAXID.newSong).click(in: app)
        // New Song opens the paste flow (R83); Start blank is the empty song.
        element(app, "segue.paste.startBlank").click(in: app)
        let editor = app.textViews[CoreAXID.editorText]
        XCTAssertTrue(editor.appears(timeout: 10))
        editor.click(in: app)

        editor.typeText("{title: Ha}\n", in: app)
        XCTAssertTrue(wait { self.exists(paths.song("ha")) }, "The first autosave made no file")
        editor.typeKey("a", modifierFlags: .command, in: app)
        editor.typeText("{title: Harbour}\nLanterns\n", in: app)
        XCTAssertTrue(waitForFile(paths.song("harbour"), contains: "Lanterns"))
        element(app, CoreAXID.editorDone).click(in: app)

        // Done flushes and renames; a loaded host stalls it.
        XCTAssertTrue(editor.disappears(timeout: 30))
        let songs = names(in: paths.library.appending(path: "songs"))
            .filter { $0.hasSuffix(".cho") }
        XCTAssertEqual(songs, ["harbour.cho"])
        XCTAssertTrue(waitForValue(element(app, CoreAXID.songTitle), "Harbour"))
    }
}
