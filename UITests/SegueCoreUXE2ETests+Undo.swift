import AppKit
import XCTest

/// Setlist builder and song metadata undo (WS2a 6.3, tests 16a undo, 19, 19a).
extension SegueCoreUXE2ETests {
    @MainActor
    func testSetlistBuilderUndoRedo() throws {
        try seedSong("harbour-lights", CoreFixture.harbour, id: CoreFixture.harbourID)
        try seedSong("river-song", CoreFixture.river, id: CoreFixture.riverID)
        try seedSetlist(
            "friday",
            id: CoreFixture.fridayID,
            name: "Friday",
            songIDs: [CoreFixture.harbourID],
        )
        let app = try launch()
        let paths = try XCTUnwrap(paths)
        let file = paths.library.appending(path: "setlists/friday.setlist.json")

        // Add (Setlist menu), then in the builder: rename and remove.
        let river = row(app, "River Song")
        XCTAssertTrue(river.waitForExistence(timeout: 15))
        river.click(in: app)
        menu(app, "Setlist", "Add Selected Song to Setlist", "Friday")
        XCTAssertTrue(wait { self.entryCount(file) == 2 })
        element(app, CoreAXID.setlistRow).click(in: app)
        XCTAssertTrue(element(app, CoreAXID.setlistEntry).waitForExistence(timeout: 10))
        element(app, CoreAXID.setlistMenu).click(in: app)
        app.menuItems[CoreAXID.setlistRenameAction].firstMatch.click(in: app)
        let field = element(app, CoreAXID.renameField)
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.typeKey("a", modifierFlags: .command, in: app)
        field.typeText("Friday Late\n", in: app)
        XCTAssertTrue(wait { self.setlistName(file) == "Friday Late" })
        let first = element(app, CoreAXID.setlistEntry)
        first.hover()
        first.buttons[CoreAXID.entryRemove].click(in: app)
        XCTAssertTrue(wait { self.entryCount(file) == 1 })

        // Undo walks back each step, with the file on disk after each.
        app.typeKey("z", modifierFlags: .command, in: app)
        XCTAssertTrue(wait { self.entryCount(file) == 2 }, "Undo Remove Song")
        app.typeKey("z", modifierFlags: .command, in: app)
        XCTAssertTrue(wait { self.setlistName(file) == "Friday" }, "Undo Rename Setlist")
        app.typeKey("z", modifierFlags: .command, in: app)
        XCTAssertTrue(wait { self.entryCount(file) == 1 }, "Undo Add Song")
        // Redo replays them.
        app.typeKey("z", modifierFlags: [.command, .shift], in: app)
        XCTAssertTrue(wait { self.entryCount(file) == 2 }, "Redo Add Song")
        app.typeKey("z", modifierFlags: [.command, .shift], in: app)
        XCTAssertTrue(wait { self.setlistName(file) == "Friday Late" }, "Redo Rename Setlist")

        try externalEditDropsUndo(app, file)
    }

    /// Another app edits the setlist: Segue shows it, and its undo actions are gone (B-16).
    @MainActor
    private func externalEditDropsUndo(_ app: XCUIApplication, _ file: URL) throws {
        let external = read(file).replacingOccurrences(of: "Friday Late", with: "Edited Elsewhere")
        try Data(external.utf8).write(to: file, options: .atomic)
        reactivate(app)
        XCTAssertTrue(app.staticTexts["Edited Elsewhere"].firstMatch.waitForExistence(timeout: 10))
        app.menuBars.menuBarItems["Edit"].click(in: app)
        let undo = app.menuBars.menuItems.matching(NSPredicate(
            format: "title BEGINSWITH %@",
            "Undo",
        )).firstMatch
        XCTAssertTrue(undo.exists)
        XCTAssertFalse(undo.title.contains("Setlist") || undo.title.contains("Song"), undo.title)
        app.typeKey(.escape, modifierFlags: [], in: app)
        XCTAssertEqual(setlistName(file), "Edited Elsewhere")
    }

    @MainActor
    func testSongMetadataUndo() throws {
        try seedSong("harbour-lights", CoreFixture.harbour)
        let app = try launch()
        let paths = try XCTUnwrap(paths)
        let sidecar = paths.library.appending(path: "songs/harbour-lights.segue.json")
        let harbour = row(app, "Harbour Lights")
        XCTAssertTrue(harbour.waitForExistence(timeout: 15))
        harbour.click(in: app)

        let tagField = element(app, CoreAXID.songTagField)
        tagField.click(in: app)
        tagField.typeText("opener\n", in: app)
        XCTAssertTrue(wait { self.sidecarValue(sidecar, "tags") as? [String] == ["opener"] })
        element(app, CoreAXID.proficiency("ready")).click(in: app)
        XCTAssertTrue(wait { self.sidecarValue(sidecar, "proficiency") as? String == "ready" })

        harbour.click(in: app) // Leave the tag field, so Cmd-Z is the window's.
        app.typeKey("z", modifierFlags: .command, in: app)
        XCTAssertTrue(wait { self.sidecarValue(sidecar, "proficiency") == nil }, "Undo proficiency")
        XCTAssertEqual(sidecarValue(sidecar, "tags") as? [String], ["opener"])
        app.typeKey("z", modifierFlags: .command, in: app)
        XCTAssertTrue(
            wait { (self.sidecarValue(sidecar, "tags") as? [String])?.isEmpty == true },
            "Undo tag",
        )
        app.typeKey("z", modifierFlags: [.command, .shift], in: app)
        XCTAssertTrue(
            wait { self.sidecarValue(sidecar, "tags") as? [String] == ["opener"] },
            "Redo tag",
        )
        app.typeKey("z", modifierFlags: [.command, .shift], in: app)
        XCTAssertTrue(
            wait { self.sidecarValue(sidecar, "proficiency") as? String == "ready" },
            "Redo",
        )
    }

    // MARK: - State restore (3.10)

    @MainActor
    func testRestoresSectionAndSongAcrossLaunches() throws {
        try seedSong("harbour-lights", CoreFixture.harbour, id: CoreFixture.harbourID)
        try seedSetlist(
            "friday",
            id: CoreFixture.fridayID,
            name: "Friday",
            songIDs: [CoreFixture.harbourID],
        )
        let paths = try XCTUnwrap(paths)
        var app = try launch()
        element(app, CoreAXID.setlistRow).click(in: app)
        XCTAssertTrue(element(app, CoreAXID.setlistEntry).waitForExistence(timeout: 10))
        Thread.sleep(forTimeInterval: 1.5) // past the 0.5 s write debounce
        app.terminate()

        app = try launch(reset: false)
        XCTAssertTrue(element(app, CoreAXID.setlistEntry).waitForExistence(timeout: 15), "builder")

        element(app, CoreAXID.sidebarLibrary).click(in: app)
        openEditor(app, "Harbour Lights")
        Thread.sleep(forTimeInterval: 1.5)
        app.terminate()

        app = try launch(reset: false)
        XCTAssertTrue(waitForValue(element(app, CoreAXID.songTitle), "Harbour Lights"))
        XCTAssertFalse(app.textViews[CoreAXID.editorText].exists, "the editor never reopens")
        app.terminate()

        // The song is gone from disk: no selection, no crash.
        try FileManager.default.removeItem(at: paths.song("harbour-lights"))
        app = try launch(reset: false)
        XCTAssertTrue(element(app, CoreAXID.libraryEmpty).waitForExistence(timeout: 15))
        XCTAssertFalse(element(app, CoreAXID.songTitle).exists)
    }

    // MARK: - Pixel pass (step 11): the new surfaces in the light appearance

    @MainActor
    func testNewSurfacesInLightAppearance() throws {
        let paths = try XCTUnwrap(paths)
        try FileManager.default.createDirectory(
            at: paths.importSource,
            withIntermediateDirectories: true,
        )
        let river = paths.importSource.appending(path: "river-song.chopro")
        try Data(CoreFixture.river.utf8).write(to: river)
        let picture = paths.importSource.appending(path: "cover.png")
        try Data([0x89, 0x50, 0x4E, 0x47]).write(to: picture)
        let app = try launch(extraArguments: [
            "-NSRequiresAquaSystemAppearance", "YES",
            "-SegueImportPanelPaths", [river, picture].map { $0.path(percentEncoded: false) }
                .joined(separator: ":"),
        ])
        XCTAssertTrue(element(app, CoreAXID.libraryEmpty).waitForExistence(timeout: 15))
        attachScreenshot(app, name: "light-empty-library")

        app.typeKey("i", modifierFlags: [.command, .shift], in: app)
        XCTAssertTrue(element(app, CoreAXID.importSummary).waitForExistence(timeout: 10))
        attachScreenshot(app, name: "light-import-summary")
        element(app, CoreAXID.songMoreMenu).click(in: app)
        attachScreen(name: "light-song-more-menu")
        app.typeKey(.escape, modifierFlags: [], in: app)

        let editor = openEditor(app, "River Song")
        editor.typeText("\nMine", in: app)
        XCTAssertTrue(waitForFile(paths.song("river-song"), contains: "Mine"))
        try Data("{title: River Song}\nTheirs\n".utf8).write(
            to: paths.song("river-song"),
            options: .atomic,
        )
        editor.typeText(" and more", in: app)
        XCTAssertTrue(element(app, CoreAXID.editorConflictBar).waitForExistence(timeout: 10))
        attachScreenshot(app, name: "light-conflict-bar")
        element(app, CoreAXID.editorConflictReload).click(in: app)

        app.typeKey("/", modifierFlags: .command, in: app)
        XCTAssertTrue(element(app, CoreAXID.shortcutsWindow).waitForExistence(timeout: 10))
        attachScreen(name: "light-keyboard-shortcuts")
    }

    /// The setlist name in a setlist file.
    func setlistName(_ url: URL) -> String? {
        sidecarValue(url, "name") as? String
    }

    /// One top-level field of a JSON file.
    func sidecarValue(_ url: URL, _ key: String) -> Any? {
        guard let data = try? Data(contentsOf: url),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }
        return object[key]
    }
}
