import AppKit
import XCTest

/// Delete and Trash, Show in Finder and import (WS2a 6.3, tests 8-13).
@MainActor
extension SegueCoreUXE2ETests {
    // MARK: - Delete and Trash (3.3)

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

    // MARK: - Import (3.2)

    func testImportFromMenu() throws {
        try seedSong("harbour-lights", CoreFixture.harbour)
        let paths = try XCTUnwrap(paths)
        let source = paths.importSource
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        let files: [(String, Data)] = [
            ("harbour-copy.cho", Data(CoreFixture.harbour.utf8)),
            ("river-song.chopro", Data(CoreFixture.river.utf8)),
            ("night-drive.txt", Data("Em        C\nHeadlights on the highway\n".utf8)),
            ("cover.png", Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])),
        ]
        for (name, data) in files {
            try data.write(to: source.appending(path: name))
        }
        let list = files.map { source.appending(path: $0.0).path(percentEncoded: false) }
        let app = try launch(extraArguments: [
            "-SegueImportPanelPaths",
            list.joined(separator: ":"),
        ])
        XCTAssertTrue(row(app, "Harbour Lights").waitForExistence(timeout: 15))

        app.typeKey("i", modifierFlags: [.command, .shift], in: app)

        let summary = element(app, CoreAXID.importSummary)
        XCTAssertTrue(summary.waitForExistence(timeout: 10), "No import summary")
        XCTAssertTrue(wait {
            summary.label == "Imported 2 songs. 2 skipped." || summary
                .value as? String == "Imported 2 songs. 2 skipped."
        })
        attachScreenshot(app, name: "import-summary")
        element(app, CoreAXID.importSummaryDetails).click(in: app)
        XCTAssertTrue(app.staticTexts["Already in your library as “Harbour Lights”"]
            .waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Not a ChordPro or text file"].exists)
        attachScreenshot(app, name: "import-summary-details")
        app.typeKey(.escape, modifierFlags: [], in: app)

        // The first import is selected; both files have sidecars.
        XCTAssertTrue(waitForValue(element(app, CoreAXID.songTitle), "River Song"))
        for slug in ["river-song", "night-drive"] {
            XCTAssertTrue(exists(paths.song(slug)), slug)
            XCTAssertTrue(exists(paths.library.appending(path: "songs/\(slug).segue.json")), slug)
        }
        XCTAssertEqual(read(paths.song("night-drive")), "Em        C\nHeadlights on the highway\n")

        // Edit > Undo Import moves both to the Trash.
        row(app, "River Song").click(in: app)
        app.typeKey("z", modifierFlags: .command, in: app)
        XCTAssertTrue(wait { self.names(in: paths.trash).count == 4 }, "\(names(in: paths.trash))")
        XCTAssertFalse(exists(paths.song("river-song")))
        XCTAssertTrue(row(app, "River Song").waitForNonExistence(timeout: 10))
    }
}
