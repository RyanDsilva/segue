import XCTest

/// The set assistant E2E (P3-7, R114-R116) on a fresh library: a one-line request in
/// Arrange's command bar shows its chips, Build fills the open setlist within the target,
/// a row's score breakdown opens from the keyboard, a lock survives Rebuild and reaches the
/// file, and the song with no tempo (so no time) is named (P8-8 5.4). No model is installed: the
/// lexicon
/// alone reads the request.
final class SegueAssistantE2ETests: SetlistE2ETestCase {
    /// Every seeded song is Ready or Pro except Northbound (Learning).
    override func setUpWithError() throws {
        try super.setUpWithError()
        let root = try XCTUnwrap(libraryRoot)
        for (offset, song) in SetlistFixture.songs.enumerated() {
            let level = song.title == "Northbound" ? "learning"
                : offset.isMultiple(of: 2) ? "pro" : "ready"
            try SetlistFixture.write(
                """
                {"schemaVersion": 3, "id": "\(song.id)", "tags": [], "proficiency": "\(level)",
                 "createdAt": "2026-10-01T10:00:00.000Z", "updatedAt": "2026-10-01T10:00:00.000Z"}
                """,
                to: root.appending(path: "songs/\(song.stem).segue.json"),
            )
        }
    }

    @MainActor
    func testRequestChipsBuildBreakdownLockAndRebuild() throws {
        let root = try XCTUnwrap(libraryRoot)
        let app = try launch()
        createSetlistInArrange(app, "Friday")

        // The request: chips at once, from the lexicon.
        let field = app.textFields[AssistantAXID.field]
        XCTAssertTrue(field.appears(timeout: 5), "No assistant field in Arrange")
        field.click(in: app)
        field.typeText("20 min set, songs I know well", in: app)
        SetlistE2E.waitUntil("The chips never showed 20 min and Ready+") {
            SetlistE2E.all(app, AssistantAXID.chip).allElementsBoundByIndex.map(\.label)
                == ["20 min", "Ready+"]
        }

        // Build fills this setlist within 20:00 +/- 3 min; Northbound (Learning) stays out.
        app.buttons[AssistantAXID.build].click(in: app)
        SetlistE2E.waitUntil("Build never filled the set") {
            !SetlistE2E.texts(app, SetlistAXID.entryTitle).isEmpty
        }
        let titles = SetlistE2E.texts(app, SetlistAXID.entryTitle)
        XCTAssertFalse(titles.contains("Northbound"))
        XCTAssertFalse(titles.contains("Saawan Ki Shaam"), "A song with no time was packed")
        let seconds = titles.compactMap { SetlistFixture.song($0).seconds }.reduce(0, +)
        XCTAssertLessThanOrEqual(abs(seconds - 1200), 180, "\(titles)")
        // Saawan Ki Shaam has no tempo, so no time, and is named.
        let leftOut = SetlistE2E.element(app, AssistantAXID.leftOut)
        XCTAssertTrue(leftOut.appears(timeout: 5))
        XCTAssertTrue(SetlistE2E.text(leftOut).contains("1 song left out: no tempo"))
        screenshot(app, "assistant-built-dark")

        // The first row's breakdown: select it, Space.
        let first = SetlistE2E.all(app, SetlistAXID.setlistEntry).element(boundBy: 0)
        let firstTitle = first.staticTexts[SetlistAXID.entryTitle]
        // ⌘-click selects without opening the row editor, and focuses the list.
        XCUIElement.perform(withKeyModifiers: .command) { firstTitle.click() }
        app.typeKey(.space, modifierFlags: [])
        let breakdown = SetlistE2E.element(app, AssistantAXID.breakdown)
        XCTAssertTrue(breakdown.appears(timeout: 5), "Space opened no breakdown")
        screenshot(app, "assistant-breakdown-dark")
        app.typeKey(.escape, modifierFlags: [])

        // Lock the first song (VoiceOver's action path), Rebuild: it stays first, in the file.
        let lockedTitle = SetlistE2E.text(firstTitle)
        let lock = first.buttons[AssistantAXID.lock]
        XCTAssertTrue(lock.appears(timeout: 5))
        lock.click(in: app)
        SetlistE2E.waitForDisk("The lock never reached the setlist file") {
            let file = try XCTUnwrap(SetlistFixture.setlistFiles(root).first)
            let entries = try XCTUnwrap(file["entries"] as? [[String: Any]])
            // Locked slots need schema 4 or later (the build writes 5 since P3-16).
            return (file["schemaVersion"] as? Int ?? 0) >= 4
                && entries.first?["locked"] as? Bool == true
                && file["targetDuration"] as? Double == 1200
        }
        app.buttons[AssistantAXID.rebuild].click(in: app)
        SetlistE2E.waitUntil("Rebuild moved the locked song") {
            SetlistE2E.texts(app, SetlistAXID.entryTitle).first == lockedTitle
        }
        screenshot(app, "assistant-rebuilt-dark")
    }

    // MARK: - Steps

    @MainActor
    private func createSetlistInArrange(_ app: XCUIApplication, _ name: String) {
        E2E.bringToFront(app)
        let new = SetlistE2E.element(app, SetlistAXID.newSetlist)
        XCTAssertTrue(new.appears(timeout: 5))
        new.click(in: app)
        let field = app.textFields[SetlistAXID.newSetlistName]
        XCTAssertTrue(field.appears(timeout: 5))
        field.click(in: app)
        field.typeText(name, in: app)
        app.buttons[SetlistAXID.newSetlistCreate].click(in: app)
        let title = app.staticTexts[SetlistAXID.setlistTitle]
        SetlistE2E.waitUntil("The builder never showed \(name)") {
            title.exists && SetlistE2E.text(title) == name
        }
        app.typeKey("2", modifierFlags: .command)
    }
}

/// The assistant's identifiers (mirrors `AccessibilityID+Assistant.swift`).
enum AssistantAXID {
    static let field = "segue.assistant.field"
    static let build = "segue.assistant.build"
    static let rebuild = "segue.assistant.rebuild"
    static let chip = "segue.assistant.chip"
    static let leftOut = "segue.assistant.leftOut"
    static let breakdown = "segue.assistant.breakdown"
    static let lock = "segue.setlist.entry.lock"
}
