import XCTest

/// Per-slot arrangements E2E (P3-16, R122, R123) on a fresh library: a slot's popover >
/// Arrange Sections > skip the Bridge, last Chorus x2, a 2:40 slot length; the builder shows
/// the mark and the slot length; the show plays the arrangement with every pass written out
/// and on the section map (R147); the gig log says so; an edit to the song makes the
/// arrangement out of date. The `.cho` is never changed by it.
final class SegueArrangementE2ETests: SetlistE2ETestCase {
    private static let song = """
    {title: Harbor Lights}
    {artist: The Lanterns}
    {key: G}
    {tempo: 96}
    {duration: 3:40}

    {start_of_verse: Verse 1}
    [G]Lanterns on the water, boats come drifting in
    {end_of_verse}

    {start_of_chorus}
    [C]Hold on, harbor lights
    {end_of_chorus}

    {start_of_verse: Verse 2}
    [G]Salt upon my collar and the tide is turning thin
    {end_of_verse}

    {chorus}

    {start_of_bridge}
    [Em]Somewhere past the breakwater
    {end_of_bridge}

    {chorus}
    """

    @MainActor
    func testArrangeSectionsForOneGig() throws {
        let root = try XCTUnwrap(libraryRoot)
        try seed(root)
        let app = try launch(light: false)
        openSetlistInArrange(app)
        try arrange(app, root)
        try playTheShow(app)
        try outOfDate(app, root)
    }

    // MARK: Steps

    @MainActor
    private func seed(_ root: URL) throws {
        try SetlistFixture.write(Self.song, to: root.appending(path: "songs/harbor-lights.cho"))
        let song = SetlistFixture.song("Harbor Lights")
        try SetlistFixture.write(
            """
            {"schemaVersion": 4, "id": "01JC0000000000000000000F07", "name": "Friday",
             "entries": [{"itemId": "01JC0000000000000000000T07", "songId": "\(song.id)"}]}
            """,
            to: root.appending(path: "setlists/friday.setlist.json"),
        )
    }

    @MainActor
    private func openSetlistInArrange(_ app: XCUIApplication) {
        click(app, ArrangementAXID.sidebarSetlists)
        click(app, SetlistAXID.setlistRow)
        app.typeKey("2", modifierFlags: .command)
        let row = SetlistE2E.row(app, SetlistAXID.setlistEntry, "1. Harbor Lights")
        XCTAssertTrue(row.appears(timeout: 10))
    }

    /// The popover's Sections button opens the sheet; skip, x2, length; Done.
    @MainActor
    private func arrange(_ app: XCUIApplication, _ root: URL) throws {
        let cho = try String(
            contentsOf: root.appending(path: "songs/harbor-lights.cho"),
            encoding: .utf8,
        )
        app.staticTexts[SetlistAXID.entryTitle].firstMatch.click(in: app)
        click(app, ArrangementAXID.open)
        let sheet = SetlistE2E.element(app, ArrangementAXID.sheet)
        XCTAssertTrue(sheet.appears(timeout: 10), "Arrange Sections never opened")
        screenshot(app, "arrangement-sheet-full")

        // Skip the Bridge (row 5).
        click(app, ArrangementAXID.play(4))
        SetlistE2E.waitForDisk("Skipping the Bridge never reached the setlist file") {
            try Self.modes(root) == ["full", "full", "full", "full", "skip", "full"]
        }
        // The last chorus (row 6) twice: select it, then +.
        click(app, ArrangementAXID.row(5))
        click(app, ArrangementAXID.countUp(5))
        SetlistE2E.waitForDisk("The play count never reached the setlist file") {
            try Self.modes(root) == ["full", "full", "full", "full", "skip", "full", "full"]
        }
        // A length for this slot.
        let field = app.textFields[SetlistAXID.songCardLength].firstMatch
        XCTAssertTrue(field.appears(timeout: 5))
        field.click(in: app)
        field.typeText("2:40\r", in: app)
        SetlistE2E.waitForDisk("The slot length never reached the setlist file") {
            try Self.arrangement(root)?["length"] as? Double == 160
        }
        screenshot(app, "arrangement-sheet-arranged")
        click(app, ArrangementAXID.done)
        XCTAssertTrue(sheet.disappears(timeout: 5))

        // The row shows the mark and the slot's own length; the song keeps its 3:40.
        let mark = SetlistE2E.element(app, ArrangementAXID.mark)
        XCTAssertTrue(mark.appears(timeout: 5))
        XCTAssertEqual(mark.label, "Custom arrangement")
        XCTAssertEqual(
            SetlistE2E.text(app.staticTexts[SetlistAXID.entryLength].firstMatch),
            "2:40",
        )
        screenshot(app, "arrangement-row")
        let after = try String(
            contentsOf: root.appending(path: "songs/harbor-lights.cho"),
            encoding: .utf8,
        )
        XCTAssertEqual(after, cho, "The song file changed")
        let file = try XCTUnwrap(SetlistFixture.setlistFiles(root).first)
        XCTAssertEqual(file["schemaVersion"] as? Int, 6)
    }

    /// Start Show: the stage says "Arranged", no Bridge, every chorus written out in full (no
    /// "Repeat chorus"): the map has six chips, the four choruses badged "1 of 4" ...; the gig
    /// log names the arrangement.
    @MainActor
    private func playTheShow(_ app: XCUIApplication) throws {
        click(app, SetlistAXID.setlistStartShow)
        click(app, ArrangementAXID.checklistStart)
        let title = app.staticTexts[ArrangementAXID.liveTitle]
        XCTAssertTrue(title.appears(timeout: 10))
        let tag = app.staticTexts[ArrangementAXID.liveArrangement]
        XCTAssertTrue(tag.appears(timeout: 5))
        XCTAssertEqual(tag.value as? String, "Arranged for this gig")
        XCTAssertTrue(SetlistE2E.element(app, ArrangementAXID.liveBody).appears(timeout: 5))
        // Every pass written out, on the map with its badge (R147).
        XCTAssertTrue(SetlistE2E.element(app, ArrangementAXID.liveMap).appears(timeout: 5))
        let lastChip = SetlistE2E.element(app, ArrangementAXID.mapChip(6))
        XCTAssertTrue(lastChip.appears(timeout: 5))
        XCTAssertEqual(lastChip.label, "Chorus, 4 of 4")
        XCTAssertFalse(SetlistE2E.element(app, ArrangementAXID.mapChip(7)).exists)
        XCTAssertTrue(SetlistE2E.element(app, ArrangementAXID.passBadge(2)).exists)
        XCTAssertEqual(
            app.staticTexts.matching(NSPredicate(format: "value == 'Repeat chorus'")).count,
            0,
            "A repeat is collapsed on stage",
        )
        XCTAssertEqual(
            app.staticTexts.matching(NSPredicate(format: "value == 'Bridge'")).count,
            0,
            "The skipped Bridge is on stage",
        )
        screenshot(app, "arrangement-stage")
        app.typeKey(".", modifierFlags: .command, in: app)
        XCTAssertTrue(SetlistE2E.element(app, ArrangementAXID.liveEndDialog).appears(timeout: 5))
        app.typeKey(.return, modifierFlags: [], in: app)
        XCTAssertTrue(title.disappears(timeout: 10))

        click(app, SetlistAXID.sidebarGigLog)
        click(app, SetlistAXID.gigLogRow)
        let played = SetlistE2E.element(app, SetlistAXID.gigPlayedRow)
        XCTAssertTrue(played.appears(timeout: 5))
        XCTAssertTrue(
            SetlistE2E.text(played)
                .contains(
                    "Custom arrangement: Verse 1, Chorus, Verse 2, Chorus 2nd, Chorus 3rd x2",
                ),
            SetlistE2E.text(played),
        )
        screenshot(app, "arrangement-gig-log")
    }

    /// Renaming a played section in the song makes the slot's arrangement out of date.
    @MainActor
    private func outOfDate(_ app: XCUIApplication, _ root: URL) throws {
        try SetlistFixture.write(
            Self.song.replacingOccurrences(of: "Verse 2}", with: "Verse Two}"),
            to: root.appending(path: "songs/harbor-lights.cho"),
        )
        click(app, ArrangementAXID.sidebarSetlists)
        click(app, SetlistAXID.setlistRow)
        app.typeKey("r", modifierFlags: .command, in: app)
        let mark = SetlistE2E.element(app, ArrangementAXID.mark)
        SetlistE2E.waitUntil("The mark never said out of date") {
            mark.exists && mark.label.hasPrefix("Arrangement out of date")
        }
        screenshot(app, "arrangement-out-of-date")
    }

    // MARK: Helpers

    @MainActor
    private func click(_ app: XCUIApplication, _ identifier: String) {
        E2E.bringToFront(app)
        let element = SetlistE2E.element(app, identifier)
        XCTAssertTrue(element.appears(timeout: 10), "No \(identifier)")
        element.click(in: app)
    }

    private static func arrangement(_ root: URL) throws -> [String: Any]? {
        let file = try XCTUnwrap(SetlistFixture.setlistFiles(root).first)
        let entries = try XCTUnwrap(file["entries"] as? [[String: Any]])
        return entries.first?["arrangement"] as? [String: Any]
    }

    /// The saved passes' show modes ("full" when the key is absent).
    private static func modes(_ root: URL) throws -> [String] {
        let passes = try arrangement(root)?["passes"] as? [[String: Any]] ?? []
        return passes.map { $0["mode"] as? String ?? "full" }
    }
}

/// Mirrors `AccessibilityID+Arrangement` and the live IDs this suite reads.
enum ArrangementAXID {
    static let sidebarSetlists = "segue.sidebar.setlists"
    static let open = "segue.setlist.arrangement.open"
    static let mark = "segue.setlist.arrangement.mark"
    static let sheet = "segue.setlist.arrangement.sheet"
    static let done = "segue.setlist.arrangement.done"
    static let checklistStart = "segue.live.checklist.start"
    static let liveTitle = "segue.live.title"
    static let liveBody = "segue.live.body"
    static let liveArrangement = "segue.live.arrangement"
    static let liveEndDialog = "segue.live.endDialog"
    static let liveMap = "segue.live.map"

    static func mapChip(_ number: Int) -> String {
        "segue.live.map.chip.\(number)"
    }

    static func passBadge(_ number: Int) -> String {
        "segue.live.passBadge.\(number)"
    }

    static func row(_ index: Int) -> String {
        "segue.setlist.arrangement.row.\(index)"
    }

    static func play(_ index: Int) -> String {
        "segue.setlist.arrangement.play.\(index)"
    }

    static func countUp(_ index: Int) -> String {
        "segue.setlist.arrangement.count.\(index).up"
    }
}
