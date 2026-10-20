import XCTest

/// Phase 3 set building E2E (P3-12, R84-R88) on a fresh library: Pick with the keyboard
/// (filter, Return, Space, ⌘A), Arrange (⌘-click, ⌥↑, Insert Break, part totals), the
/// missing-lengths list filled in place, and Library multi-select's Add to Setlist. Every
/// change is checked in the files.
final class SegueSetBuilderE2ETests: SetlistE2ETestCase {
    @MainActor
    func testPickArrangeBreaksAndMissingLengths() throws {
        let root = try XCTUnwrap(libraryRoot)
        let app = try launchBuilder(appearance: "dark")
        createSetlist(app, "Friday")
        let picked = pickWithTheKeyboard(app)
        try arrange(app, root, picked: picked)
        try fillMissingLength(app, root)
    }

    /// Pick: filter, Return, Space, ↓, ⌘A. Returns the set's titles.
    @MainActor
    private func pickWithTheKeyboard(_ app: XCUIApplication) -> [String] {
        // Pick: filter, Return to the first result, Space ticks it.
        SetlistE2E.search(app, SetlistAXID.builderSearch, "harbor")
        SetlistE2E.waitUntil("The filter never narrowed to Harbor Lights") {
            SetlistE2E.texts(app, SetlistAXID.builderLibraryRow) == ["Harbor Lights"]
        }
        app.typeKey(.return, modifierFlags: [])
        app.typeKey(.space, modifierFlags: [])
        waitForEntries(app, ["Harbor Lights"])
        // Clear the filter: Return, Space (Dil Ki Raah), ↓ ↓ Space (Kitchen Radio).
        SetlistE2E.search(app, SetlistAXID.builderSearch, "")
        SetlistE2E.waitUntil("The filter never cleared") {
            SetlistE2E.texts(app, SetlistAXID.builderLibraryRow).count == 8
        }
        app.typeKey(.return, modifierFlags: [])
        app.typeKey(.space, modifierFlags: [])
        app.typeKey(.downArrow, modifierFlags: [])
        app.typeKey(.downArrow, modifierFlags: [])
        app.typeKey(.space, modifierFlags: [])
        waitForEntries(app, ["Harbor Lights", "Dil Ki Raah", "Kitchen Radio"])
        // ⌘A ticks every row the filter shows; nothing is added twice.
        app.typeKey("a", modifierFlags: .command)
        let picked = [
            "Harbor Lights", "Dil Ki Raah", "Kitchen Radio", "Lamplighter", "Morning Ferry",
            "Northbound", "Paper Boats", "Saawan Ki Shaam",
        ]
        waitForEntries(app, picked)
        screenshot(app, "pick-dark")
        return picked
    }

    /// Arrange: ⌘-click the last row, ⌥↑, Insert Break; part totals and the file.
    @MainActor
    private func arrange(_ app: XCUIApplication, _ root: URL, picked: [String]) throws {
        // Arrange (⌘2): ⌘-click the last row, ⌥↑, Insert Break (⇧⌘B).
        app.typeKey("2", modifierFlags: .command)
        SetlistE2E.waitUntil("Arrange still shows the library column") {
            !SetlistE2E.element(app, SetlistAXID.builderLibrary).exists
        }
        let saawan = SetlistE2E.row(app, SetlistAXID.setlistEntry, "8. Saawan Ki Shaam")
        XCTAssertTrue(saawan.appears(timeout: 5))
        XCUIElement.perform(withKeyModifiers: .command) {
            saawan.staticTexts[SetlistAXID.entryTitle].click()
        }
        app.typeKey(.upArrow, modifierFlags: .option)
        let arranged = Array(picked.prefix(5)) + ["Northbound", "Saawan Ki Shaam", "Paper Boats"]
        waitForEntries(app, arranged)
        app.typeKey("b", modifierFlags: [.command, .shift])
        SetlistE2E.waitUntil("Insert Break added no break row") {
            SetlistE2E.texts(app, SetlistAXID.setlistBreakTotal) == ["3:12"]
        }
        XCTAssertEqual(
            SetlistE2E.text(SetlistE2E.element(app, SetlistAXID.setlistTotal)),
            "≥25:05 + 1 unknown",
        )
        screenshot(app, "arrange-dark")
        SetlistE2E.waitForDisk("The break never reached the setlist file") {
            let file = try XCTUnwrap(SetlistFixture.setlistFiles(root).first)
            let entries = try XCTUnwrap(file["entries"] as? [[String: Any]])
            let breakRow = entries[7]["break"] as? [String: Any]
            return entries.count == 9 && breakRow?["label"] as? String == "Set 2"
        }
    }

    /// The missing-lengths list: exactly Saawan Ki Shaam; 4:05 typed in place.
    @MainActor
    private func fillMissingLength(_ app: XCUIApplication, _ root: URL) throws {
        // The "1 unknown" button lists Saawan Ki Shaam; typing 4:05 fills it in place.
        click(app, SetlistAXID.setlistUnknownButton)
        let row = SetlistE2E.row(app, SetlistAXID.missingLengthsRow, "Saawan Ki Shaam")
        XCTAssertTrue(row.appears(timeout: 5))
        XCTAssertEqual(SetlistE2E.all(app, SetlistAXID.missingLengthsRow).count, 1)
        screenshot(app, "missing-lengths-dark")
        let field = row.textFields[SetlistAXID.songCardLength]
        XCTAssertTrue(field.appears(timeout: 5))
        field.click(in: app)
        field.typeText("4:05\r", in: app)
        SetlistE2E.waitUntil("The total never lost its unknown") {
            SetlistE2E.text(SetlistE2E.element(app, SetlistAXID.setlistTotal)) == "29:10"
        }
        XCTAssertFalse(SetlistE2E.element(app, SetlistAXID.setlistUnknownButton).exists)
        SetlistE2E.waitForDisk("The length never reached the song file") {
            let text = try String(
                contentsOf: root.appending(path: "songs/saawan-ki-shaam.cho"),
                encoding: .utf8,
            )
            return text.contains("{duration: 4:05}")
        }
    }

    @MainActor
    func testLibraryMultiSelectAddsToSetlist() throws {
        let root = try XCTUnwrap(libraryRoot)
        let app = try launchBuilder(appearance: "light")
        createSetlist(app, "Friday")
        click(app, SetlistAXID.sidebarLibrary)

        let first = SetlistE2E.row(app, SetlistAXID.songRow, "Dil Ki Raah")
        XCTAssertTrue(first.appears(timeout: 5))
        first.click(in: app)
        for title in ["Kitchen Radio", "Northbound"] {
            let row = SetlistE2E.row(app, SetlistAXID.songRow, title)
            XCUIElement.perform(withKeyModifiers: .command) { row.click() }
        }
        let pane = SetlistE2E.element(app, SetlistAXID.multiSelection)
        XCTAssertTrue(pane.appears(timeout: 5), "No multi-selection pane")
        screenshot(app, "library-multi-light")
        let menu = pane.descendants(matching: .any)[SetlistAXID.addToSetlistMenu]
        menu.click(in: app)
        let item = app.menuItems["Friday"]
        XCTAssertTrue(item.appears(timeout: 5))
        item.click()

        SetlistE2E.waitForDisk("Add to Setlist never added the three songs") {
            let file = try XCTUnwrap(SetlistFixture.setlistFiles(root).first)
            let ids = (file["entries"] as? [[String: Any]])?.compactMap { $0["songId"] as? String }
            return ids == ["Dil Ki Raah", "Kitchen Radio", "Northbound"]
                .map { SetlistFixture.song($0).id }
        }
    }

    // MARK: - Steps

    /// `launch` with a forced appearance (`-SegueAppearance light|dark`).
    @MainActor
    private func launchBuilder(appearance: String) throws -> XCUIApplication {
        let root = try XCTUnwrap(libraryRoot)
        let app = XCUIApplication()
        self.app = app
        E2E.launch(app, arguments: [
            "-SegueLibraryPath", root.path(percentEncoded: false),
            "-SegueResetState", "YES",
            "-SegueTrashPath", Self.trashFolder(root).path(percentEncoded: false),
            "-SegueWorkspaceLog", Self.workspaceLog(root).path(percentEncoded: false),
            "-SegueAppearance", appearance,
        ])
        SetlistE2E.waitUntil("The seeded songs never listed") {
            SetlistE2E.all(app, SetlistAXID.songRow).count == SetlistFixture.songs.count
        }
        return app
    }

    @MainActor
    private func createSetlist(_ app: XCUIApplication, _ name: String) {
        click(app, SetlistAXID.newSetlist)
        let field = app.textFields[SetlistAXID.newSetlistName]
        XCTAssertTrue(field.appears(timeout: 5))
        field.click(in: app)
        field.typeText(name, in: app)
        app.buttons[SetlistAXID.newSetlistCreate].click(in: app)
        let title = app.staticTexts[SetlistAXID.setlistTitle]
        SetlistE2E.waitUntil("The builder never showed \(name)") {
            title.exists && SetlistE2E.text(title) == name
        }
    }

    @MainActor
    private func click(_ app: XCUIApplication, _ identifier: String) {
        E2E.bringToFront(app)
        let element = SetlistE2E.element(app, identifier)
        XCTAssertTrue(element.appears(timeout: 5), "No \(identifier)")
        element.click(in: app)
    }

    @MainActor
    private func waitForEntries(_ app: XCUIApplication, _ titles: [String]) {
        SetlistE2E.waitUntil(
            "Expected entries \(titles), got \(SetlistE2E.texts(app, SetlistAXID.entryTitle))",
        ) {
            SetlistE2E.texts(app, SetlistAXID.entryTitle) == titles
        }
    }
}

extension SetlistAXID {
    static let setlistBreakTotal = "segue.setlist.break.total"
    static let setlistUnknownButton = "segue.setlist.unknown"
    static let missingLengthsRow = "segue.setlist.missingLengths.row"
    static let songCardLength = "segue.songCard.length"
    static let multiSelection = "segue.library.multiSelection"
    static let addToSetlistMenu = "segue.song.addToSetlist"
}
