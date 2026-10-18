import XCTest

/// Phase 2 library metadata E2E (unit D): proficiency, tags, notes and cues edited in the
/// library preview and saved to the sidecar; simple filtering by chips, typed tokens and
/// sidebar tags.
final class SegueSetlistLibraryE2ETests: SetlistE2ETestCase {
    @MainActor
    func testMetadataEditingAndFiltering() throws {
        let root = try XCTUnwrap(libraryRoot)
        let app = try launch(light: true)
        screenshot(app, "library-initial")

        // Proficiency and tags, saved to the sidecar at once.
        select(app, "Harbor Lights")
        click(app, SetlistAXID.songProficiency("pro"))
        addTag(app, "upbeat")
        addTag(app, "crowd pleaser")
        SetlistE2E.waitForDisk("Harbor Lights sidecar never got pro + tags") {
            let sidecar = try SetlistFixture.sidecarJSON(root, "Harbor Lights")
            return sidecar["proficiency"] as? String == "pro"
                && sidecar["tags"] as? [String] == ["upbeat", "crowd pleaser"]
        }
        select(app, "Paper Boats")
        click(app, SetlistAXID.songProficiency("ready"))
        addTag(app, "Upbeat") // Case-insensitive: offered and stored as typed.
        select(app, "Saawan Ki Shaam")
        click(app, SetlistAXID.songProficiency("learning"))
        SetlistE2E.waitForDisk("Saawan Ki Shaam never became learning") {
            try SetlistFixture.sidecarJSON(root, "Saawan Ki Shaam")["proficiency"] as? String
                == "learning"
        }

        // Clicking the current level clears it.
        click(app, SetlistAXID.songProficiency("learning"))
        SetlistE2E.waitForDisk("Clearing the proficiency did not save") {
            try SetlistFixture.sidecarJSON(root, "Saawan Ki Shaam")["proficiency"] == nil
        }
        click(app, SetlistAXID.songProficiency("learning"))

        try editNotesAndCues(app, root)
        screenshot(app, "library-detail-metadata")
        try filter(app)
    }

    // MARK: - Steps

    @MainActor
    private func editNotesAndCues(_ app: XCUIApplication, _ root: URL) throws {
        select(app, "Harbor Lights")
        click(app, SetlistAXID.songEditNotes)
        let notes = app.textViews[SetlistAXID.notesEditorText]
        XCTAssertTrue(notes.appears(timeout: 5))
        notes.click(in: app)
        notes.typeText("Start soft, build into the last chorus", in: app)
        click(app, SetlistAXID.notesEditorAddCue)
        let cue = app.textFields[SetlistAXID.notesEditorCueText]
        XCTAssertTrue(cue.appears(timeout: 5))
        cue.click(in: app)
        cue.typeText("Watch Ravi for the stop", in: app)
        screenshot(app, "notes-editor")
        click(app, SetlistAXID.notesEditorSave)

        let shown = SetlistE2E.element(app, SetlistAXID.songNotes)
        XCTAssertTrue(shown.appears(timeout: 5))
        XCTAssertEqual(
            SetlistE2E.text(shown),
            "Start soft, build into the last chorus",
        )
        let shownCue = SetlistE2E.element(app, SetlistAXID.songCue)
        XCTAssertTrue(shownCue.appears(timeout: 5))
        XCTAssertTrue(SetlistE2E.text(shownCue).contains("Watch Ravi for the stop"))
        SetlistE2E.waitForDisk("Notes and cues never reached the sidecar") {
            let sidecar = try SetlistFixture.sidecarJSON(root, "Harbor Lights")
            let cues = sidecar["cues"] as? [[String: Any]] ?? []
            return sidecar["notes"] as? String == "Start soft, build into the last chorus"
                && cues.count == 1
                && cues.first?["text"] as? String == "Watch Ravi for the stop"
                && cues.first?["section"] as? String == "Verse"
        }
        // The .cho is untouched by metadata edits.
        let cho = try String(
            contentsOf: root.appending(path: "songs/harbor-lights.cho"),
            encoding: .utf8,
        )
        XCTAssertEqual(cho, SetlistFixture.song("Harbor Lights").source)
    }

    @MainActor
    private func filter(_ app: XCUIApplication) throws {
        // Proficiency chip.
        click(app, SetlistAXID.filterProficiency("ready"))
        waitForRows(app, ["Paper Boats"])
        screenshot(app, "library-filter-ready")
        click(app, SetlistAXID.filterProficiency("ready"))
        waitForRows(app, SetlistFixture.sortedTitles)

        // Typed tokens: proficiency + known tag, then key, then free text + tag.
        SetlistE2E.search(app, SetlistAXID.librarySearch, "pro, upbeat")
        waitForRows(app, ["Harbor Lights"])
        SetlistE2E.search(app, SetlistAXID.librarySearch, "key Am")
        waitForRows(app, ["Dil Ki Raah"])
        SetlistE2E.search(app, SetlistAXID.librarySearch, "upbeat paper")
        waitForRows(app, ["Paper Boats"])
        screenshot(app, "library-filter-typed")
        SetlistE2E.search(app, SetlistAXID.librarySearch, "")
        waitForRows(app, SetlistFixture.sortedTitles)

        // Tag chip in the chip row, then the sidebar's Tags section.
        let upbeat = SetlistE2E.all(app, SetlistAXID.filterTag)
            .matching(NSPredicate(format: "label ==[c] %@", "upbeat")).firstMatch
        XCTAssertTrue(upbeat.appears(timeout: 5))
        upbeat.click(in: app)
        waitForRows(app, ["Harbor Lights", "Paper Boats"])
        upbeat.click(in: app)
        waitForRows(app, SetlistFixture.sortedTitles)
        let sidebarTag = SetlistE2E.all(app, SetlistAXID.sidebarTag)
            .matching(NSPredicate(format: "label BEGINSWITH[c] %@", "crowd pleaser")).firstMatch
        XCTAssertTrue(sidebarTag.appears(timeout: 5))
        sidebarTag.click(in: app)
        waitForRows(app, ["Harbor Lights"])
        screenshot(app, "library-filter-sidebar-tag")

        // Rows carry the proficiency mark.
        let harbor = SetlistE2E.row(app, SetlistAXID.songRow, "Harbor Lights")
        XCTAssertTrue(SetlistE2E.text(harbor).contains("Pro"), SetlistE2E.text(harbor))
    }

    // MARK: - Helpers

    @MainActor
    private func select(_ app: XCUIApplication, _ title: String) {
        let row = SetlistE2E.row(app, SetlistAXID.songRow, title)
        XCTAssertTrue(row.appears(timeout: 10), "No row \(title)")
        row.click(in: app)
        let heading = app.staticTexts[SetlistAXID.songTitle]
        SetlistE2E.waitUntil("\(title) never showed in the preview") {
            heading.exists && SetlistE2E.text(heading) == title
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
    private func addTag(_ app: XCUIApplication, _ tag: String) {
        let field = app.textFields[SetlistAXID.songTagField]
        XCTAssertTrue(field.appears(timeout: 5))
        field.click(in: app)
        field.typeText(tag + "\n", in: app)
        SetlistE2E.waitUntil("Tag \(tag) never showed") {
            SetlistE2E.texts(app, SetlistAXID.songTag).contains { $0.hasPrefix(tag) }
        }
    }

    @MainActor
    private func waitForRows(_ app: XCUIApplication, _ titles: [String]) {
        SetlistE2E.waitUntil(
            "Expected rows \(titles), got \(SetlistE2E.texts(app, SetlistAXID.songRow))",
        ) {
            let rows = SetlistE2E.texts(app, SetlistAXID.songRow)
            return rows.count == titles.count
                && zip(rows, titles).allSatisfy { $0.hasPrefix($1) }
        }
    }
}
