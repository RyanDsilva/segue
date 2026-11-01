import XCTest

/// Phase 2 setlist builder E2E (unit D), layout a "library to set": create a setlist, add
/// songs with `+` and by dragging, reorder, start times and the running total vs target,
/// per-slot overrides and notes, gig details, rename / duplicate / delete. Every change is
/// checked in the setlist file.
final class SegueSetlistBuilderE2ETests: SetlistE2ETestCase {
    private let planned = [
        "Morning Ferry", "Paper Boats", "Kitchen Radio", "Harbor Lights", "Saawan Ki Shaam",
    ]
    private let reordered = [
        "Saawan Ki Shaam", "Morning Ferry", "Paper Boats", "Kitchen Radio", "Harbor Lights",
    ]

    @MainActor
    func testBuildSetlistFromTheLibrary() throws {
        let root = try XCTUnwrap(libraryRoot)
        let app = try launch(light: true)
        createSetlist(app, "Friday - Dockside")
        screenshot(app, "builder-empty")

        for title in planned {
            addWithPlus(app, title)
        }
        waitForEntries(app, planned)
        // Start times accumulate from tempo x bars; the song with no tempo shows --:-- and
        // the total says so (P8-8).
        XCTAssertEqual(
            SetlistE2E.texts(app, SetlistAXID.entryStart),
            SetlistFixture.starts(planned),
        )
        XCTAssertEqual(
            SetlistE2E.labels(app, SetlistAXID.entryTime).first,
            SetlistFixture.song(planned[0]).time,
        )
        XCTAssertEqual(SetlistE2E.labels(app, SetlistAXID.entryTime).last, "--:--")
        XCTAssertEqual(
            SetlistE2E.element(app, SetlistAXID.setlistTotal).label,
            SetlistFixture.total(planned),
        )
        // Songs already in the set are marked in the library column.
        let library = SetlistE2E.texts(app, SetlistAXID.builderLibraryRow)
        XCTAssertTrue(library.contains("Paper Boats, already in set"), "\(library)")
        XCTAssertTrue(library.contains("Dil Ki Raah"), "\(library)")

        try reorder(app)
        try dragFromLibrary(app)
        try editDetails(app, root)
        try editEntry(app, root)
        screenshot(app, "builder-full")
        try renameDuplicateDelete(app, root)
        try removeEntry(app, root)
    }

    /// A song is in a set at most once: after `+`, its library row shows "In set" instead
    /// of `+`, VoiceOver says it is already in the set, and dragging it into the set adds
    /// nothing.
    @MainActor
    func testSongAppearsOnceInTheSet() throws {
        let root = try XCTUnwrap(libraryRoot)
        let app = try launch(light: true)
        createSetlist(app, "Saturday")
        addWithPlus(app, "Paper Boats")
        SetlistE2E.search(app, SetlistAXID.builderSearch, "paper")
        SetlistE2E.waitUntil("Builder search never narrowed to Paper Boats") {
            let rows = SetlistE2E.texts(app, SetlistAXID.builderLibraryRow)
            return rows.count == 1 && rows[0].hasPrefix("Paper Boats")
        }

        // Dragging the song in again adds nothing.
        let source = SetlistE2E.row(app, SetlistAXID.builderLibraryRow, "Paper Boats")
        drag(
            app,
            from: source.coordinate(withNormalizedOffset: CGVector(dx: 0.4, dy: 0.5)),
            to: SetlistE2E.element(app, SetlistAXID.setlistDropZone)
                .coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)),
        )
        XCTAssertFalse(
            E2E.waitUntil(timeout: 2) {
                SetlistE2E.all(app, SetlistAXID.setlistEntry).count > 1
            },
            "Dragging Paper Boats again added it twice",
        )

        // No `+` on the row; an "In set" mark instead, and VoiceOver says so.
        XCTAssertEqual(
            SetlistE2E.texts(app, SetlistAXID.builderLibraryRow),
            ["Paper Boats, already in set"],
        )
        XCTAssertFalse(source.buttons[SetlistAXID.builderAdd].exists, "+ is still offered")
        XCTAssertTrue(source.descendants(matching: .any)[SetlistAXID.builderInSet].exists)
        screenshot(app, "in-set")
        waitForEntries(app, ["Paper Boats"])
        SetlistE2E.waitForDisk("The setlist file holds the song more than once") {
            let file = try XCTUnwrap(SetlistFixture.setlistFiles(root).first)
            return (file["entries"] as? [Any])?.count == 1
        }
    }

    // MARK: - Steps

    @MainActor
    private func createSetlist(_ app: XCUIApplication, _ name: String) {
        click(app, SetlistAXID.newSetlist)
        let field = app.textFields[SetlistAXID.newSetlistName]
        XCTAssertTrue(field.appears(timeout: 5))
        field.click(in: app)
        field.typeText(name, in: app)
        app.buttons[SetlistAXID.newSetlistCreate].click(in: app)
        waitForTitle(app, name)
        XCTAssertTrue(SetlistE2E.element(app, SetlistAXID.setlistDropZone).exists)
        XCTAssertFalse(SetlistE2E.element(app, SetlistAXID.setlistStartShow).isEnabled)
    }

    @MainActor
    private func addWithPlus(_ app: XCUIApplication, _ title: String) {
        let row = SetlistE2E.row(app, SetlistAXID.builderLibraryRow, title)
        XCTAssertTrue(row.appears(timeout: 5), "No library row \(title)")
        let count = SetlistE2E.all(app, SetlistAXID.setlistEntry).count
        row.buttons[SetlistAXID.builderAdd].click(in: app)
        SetlistE2E.waitUntil("+ did not add \(title)") {
            SetlistE2E.all(app, SetlistAXID.setlistEntry).count == count + 1
        }
    }

    /// Drags "Dil Ki Raah" from the library column onto the set's drop zone (appends).
    @MainActor
    private func dragFromLibrary(_ app: XCUIApplication) throws {
        let source = SetlistE2E.row(app, SetlistAXID.builderLibraryRow, "Dil Ki Raah")
        let target = SetlistE2E.element(app, SetlistAXID.setlistDropZone)
        // Narrow the column so the row is in view.
        SetlistE2E.search(app, SetlistAXID.builderSearch, "dil")
        SetlistE2E.waitUntil("Builder search never narrowed to Dil Ki Raah") {
            SetlistE2E.texts(app, SetlistAXID.builderLibraryRow) == ["Dil Ki Raah"]
        }
        XCTAssertTrue(source.appears(timeout: 5))
        XCTAssertTrue(target.appears(timeout: 5))
        drag(
            app,
            from: source.coordinate(withNormalizedOffset: CGVector(dx: 0.4, dy: 0.5)),
            to: target.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)),
        )
        waitForEntries(app, reordered + ["Dil Ki Raah"])
        SetlistE2E.search(app, SetlistAXID.builderSearch, "")
    }

    /// Drags the last entry ("Saawan Ki Shaam", no tempo) to the top of the set.
    @MainActor
    private func reorder(_ app: XCUIApplication) throws {
        let entries = SetlistE2E.all(app, SetlistAXID.setlistEntry)
        let last = entries.element(boundBy: entries.count - 1)
        let first = entries.element(boundBy: 0)
        drag(
            app,
            from: last.coordinate(withNormalizedOffset: CGVector(dx: 0.3, dy: 0.5)),
            to: first.coordinate(withNormalizedOffset: CGVector(dx: 0.3, dy: 0.15)),
        )
        waitForEntries(app, reordered)
        // Every start after the unknown time is a lower bound ("≥"); right after it,
        // with nothing known yet, the start is unknown too.
        XCTAssertEqual(
            SetlistE2E.texts(app, SetlistAXID.entryStart),
            SetlistFixture.starts(reordered),
        )
    }

    @MainActor
    private func editDetails(_ app: XCUIApplication, _ root: URL) throws {
        click(app, SetlistAXID.setlistDetailsLine)
        let venue = app.textFields[SetlistAXID.detailsVenue]
        XCTAssertTrue(venue.appears(timeout: 5))
        venue.click(in: app)
        venue.typeText("Dockside", in: app)
        click(app, SetlistAXID.detailsHasDate)
        let target = app.textFields[SetlistAXID.detailsTarget]
        target.click(in: app)
        target.typeText("45", in: app)
        screenshot(app, "builder-details")
        click(app, SetlistAXID.detailsSave)

        let line = SetlistE2E.element(app, SetlistAXID.setlistDetailsLine)
        SetlistE2E.waitUntil("Details line never showed the venue") {
            SetlistE2E.text(line).hasPrefix("Dockside · ")
        }
        XCTAssertEqual(
            SetlistE2E.text(SetlistE2E.element(app, SetlistAXID.setlistTarget)),
            "target 45:00",
        )
        SetlistE2E.waitForDisk("Venue, date and target never reached the file") {
            let file = try XCTUnwrap(SetlistFixture.setlistFiles(root).first)
            return file["venue"] as? String == "Dockside"
                && (file["date"] as? String)?.count == 10
                && file["targetDuration"] as? Double == 2700
        }
    }

    /// Harbor Lights (G, capo 2): this slot plays it capo 4 with a note.
    @MainActor
    private func editEntry(_ app: XCUIApplication, _ root: URL) throws {
        let row = SetlistE2E.row(app, SetlistAXID.setlistEntry, "5. Harbor Lights")
        XCTAssertTrue(row.appears(timeout: 5))
        XCTAssertEqual(SetlistE2E.text(row.staticTexts[SetlistAXID.entryCapo]), "Capo 2")
        row.staticTexts[SetlistAXID.entryTitle].click(in: app)
        let capoUp = SetlistE2E.element(app, SetlistAXID.entryCapoUp)
        XCTAssertTrue(capoUp.appears(timeout: 5))
        capoUp.click(in: app)
        SetlistE2E.waitUntil("Capo override never applied") {
            SetlistE2E.text(SetlistE2E.element(app, SetlistAXID.entryCapoValue)) == "Capo 3"
        }
        capoUp.click(in: app)
        SetlistE2E.waitUntil("Second capo step never applied") {
            SetlistE2E.text(SetlistE2E.element(app, SetlistAXID.entryCapoValue)) == "Capo 4"
        }
        let note = app.textFields[SetlistAXID.entryNoteField]
        note.click(in: app)
        note.typeText("start soft", in: app)
        screenshot(app, "builder-entry-editor")
        click(app, SetlistAXID.entryDone)

        SetlistE2E.waitUntil("Row never showed the override") {
            SetlistE2E.text(row.staticTexts[SetlistAXID.entryCapo]) == "Capo 4"
                && row.staticTexts[SetlistAXID.entryNote].exists
        }
        // Concert A with capo 4 is played as F shapes.
        XCTAssertEqual(SetlistE2E.text(row.staticTexts[SetlistAXID.entryKey]), "F")
        SetlistE2E.waitForDisk("Override and note never reached the file") {
            let file = try XCTUnwrap(SetlistFixture.setlistFiles(root).first)
            let entries = try XCTUnwrap(file["entries"] as? [[String: Any]])
            let harbor = SetlistFixture.song("Harbor Lights").id
            let entry = try XCTUnwrap(entries.first { $0["songId"] as? String == harbor })
            let overrides = entry["overrides"] as? [String: Any]
            return overrides?["capo"] as? Int == 4 && entry["note"] as? String == "start soft"
        }
    }

    @MainActor
    private func renameDuplicateDelete(_ app: XCUIApplication, _ root: URL) throws {
        menuAction(app, SetlistAXID.setlistRenameAction)
        let field = app.textFields[SetlistAXID.setlistNameField]
        XCTAssertTrue(field.appears(timeout: 5))
        field.click(in: app)
        field.typeKey("a", modifierFlags: .command, in: app)
        field.typeText("Friday - Dockside Late", in: app)
        click(app, SetlistAXID.setlistNameSave)
        waitForTitle(app, "Friday - Dockside Late")

        menuAction(app, SetlistAXID.setlistDuplicateAction)
        waitForTitle(app, "Friday - Dockside Late copy")
        XCTAssertEqual(SetlistE2E.all(app, SetlistAXID.setlistRow).count, 2)
        waitForEntries(app, reordered + ["Dil Ki Raah"])
        screenshot(app, "builder-duplicate")
        SetlistE2E.waitForDisk("The copy was never written") {
            let files = try SetlistFixture.setlistFiles(root)
            let ids = Set(files.compactMap { $0["id"] as? String })
            let items = files.flatMap { $0["entries"] as? [[String: Any]] ?? [] }
                .compactMap { $0["itemId"] as? String }
            return files.count == 2 && ids.count == 2 && Set(items).count == items.count
        }

        // Move to Trash: no confirmation (A23), the file lands in the trash, Undo brings
        // it back and Redo trashes it again.
        menuAction(app, SetlistAXID.setlistDeleteAction)
        XCTAssertFalse(app.sheets.firstMatch.appears(timeout: 1), "No dialog expected")
        SetlistE2E.waitUntil("The copy was never moved to the Trash") {
            SetlistE2E.all(app, SetlistAXID.setlistRow).count == 1
        }
        SetlistE2E.waitForDisk("The copy's file was never removed") {
            let files = try SetlistFixture.setlistFiles(root)
            return files.count == 1 && files[0]["name"] as? String == "Friday - Dockside Late"
        }
        XCTAssertEqual(Self.trashed(root), ["friday-dockside-late-copy.setlist.json"])
        app.typeKey("z", modifierFlags: .command, in: app)
        SetlistE2E.waitUntil("Undo never restored the copy") {
            SetlistE2E.all(app, SetlistAXID.setlistRow).count == 2
        }
        XCTAssertTrue(Self.trashed(root).isEmpty)
        waitForTitle(app, "Friday - Dockside Late copy")
        app.typeKey("z", modifierFlags: [.command, .shift], in: app)
        SetlistE2E.waitUntil("Redo never trashed the copy again") {
            SetlistE2E.all(app, SetlistAXID.setlistRow).count == 1
        }
        SetlistE2E.waitForDisk("Redo left the copy's file") {
            try SetlistFixture.setlistFiles(root).count == 1
        }
    }

    /// Hovering a row reveals its remove button.
    @MainActor
    private func removeEntry(_ app: XCUIApplication, _ root: URL) throws {
        let sidebarRow = SetlistE2E.row(app, SetlistAXID.setlistRow, "Friday - Dockside Late")
        sidebarRow.click(in: app)
        waitForTitle(app, "Friday - Dockside Late")
        let row = SetlistE2E.row(app, SetlistAXID.setlistEntry, "1. Saawan Ki Shaam")
        XCTAssertTrue(row.appears(timeout: 5))
        row.hover()
        row.buttons[SetlistAXID.entryRemove].click(in: app)
        waitForEntries(app, Array(reordered.dropFirst()) + ["Dil Ki Raah"])
        XCTAssertEqual(
            SetlistE2E.element(app, SetlistAXID.setlistTotal).label,
            SetlistFixture.total(Array(reordered.dropFirst()) + ["Dil Ki Raah"]),
        )
        SetlistE2E.waitForDisk("The removal never reached the file") {
            let file = try XCTUnwrap(SetlistFixture.setlistFiles(root).first)
            return (file["entries"] as? [Any])?.count == 5
        }
    }

    // MARK: - Helpers

    /// A slow drag that hovers over the target before releasing, so SwiftUI's drop
    /// destinations see the drag enter.
    @MainActor
    private func drag(_ app: XCUIApplication, from: XCUICoordinate, to: XCUICoordinate) {
        E2E.bringToFront(app)
        from.press(
            forDuration: 0.5,
            thenDragTo: to,
            withVelocity: 300,
            thenHoldForDuration: 0.8,
        )
    }

    @MainActor
    private func click(_ app: XCUIApplication, _ identifier: String) {
        E2E.bringToFront(app)
        let element = SetlistE2E.element(app, identifier)
        XCTAssertTrue(element.appears(timeout: 5), "No \(identifier)")
        element.click(in: app)
    }

    @MainActor
    private func menuAction(_ app: XCUIApplication, _ identifier: String) {
        click(app, SetlistAXID.setlistMenu)
        let item = app.menuItems[identifier].firstMatch
        XCTAssertTrue(item.appears(timeout: 5), "No menu item \(identifier)")
        item.click(in: app)
    }

    @MainActor
    private func waitForTitle(_ app: XCUIApplication, _ name: String) {
        let title = app.staticTexts[SetlistAXID.setlistTitle]
        SetlistE2E.waitUntil("The builder never showed \(name)") {
            title.exists && SetlistE2E.text(title) == name
        }
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
