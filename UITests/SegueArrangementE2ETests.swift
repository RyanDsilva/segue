import XCTest

/// Arrange Sections E2E (P8-3, R149, R156) on a fresh library: a slot's popover > Sections
/// opens the sequence strip with one chip per part; S skips the Bridge, a chip's "+" plays
/// the last chorus again, a typed roadmap commits with Return and keeps the sheet open, the
/// slot gets a 2:40 length; the row shows the mark and 2:40; "Rehearse this" plays the slot
/// as arranged (every pass on the section map, no Bridge) and the sheet opens again when it
/// ends; a full show plays it too and the gig log names the arrangement; an edit to the song
/// makes the arrangement out of date and Update brings it back. The `.cho` is never changed.
final class SegueArrangementE2ETests: SetlistE2ETestCase {
    private static let song = """
    {title: Harbor Lights}
    {artist: The Lanterns}
    {key: G}
    {tempo: 96}

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
        try rehearseThis(app)
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

    /// The popover's Sections button opens the sheet: six chips; S skips the Bridge, "+"
    /// repeats the last chorus, a roadmap commits on Return; Done.
    @MainActor
    private func arrange(_ app: XCUIApplication, _ root: URL) throws {
        let cho = try String(
            contentsOf: root.appending(path: "songs/harbor-lights.cho"),
            encoding: .utf8,
        )
        let sheet = openSheet(app)
        XCTAssertTrue(SetlistE2E.element(app, ArrangementAXID.chip(5)).appears(timeout: 5))
        XCTAssertFalse(SetlistE2E.element(app, ArrangementAXID.chip(6)).exists)
        screenshot(app, "arrangement-sheet-full")

        // Select the Bridge (chip 5) and skip it with S.
        click(app, ArrangementAXID.chip(4))
        app.typeKey("s", modifierFlags: [], in: app)
        SetlistE2E.waitForDisk("Skipping the Bridge never reached the setlist file") {
            try Self.modes(root) == ["full", "full", "full", "full", "skip", "full"]
        }
        // The last chorus again: its hover "+".
        let last = SetlistE2E.element(app, ArrangementAXID.chip(5))
        last.hover()
        click(app, ArrangementAXID.chipDuplicate(5))
        SetlistE2E.waitForDisk("The extra chorus never reached the setlist file") {
            try Self.modes(root) == ["full", "full", "full", "full", "skip", "full", "full"]
        }
        // A typed roadmap: Return commits and the sheet stays open.
        let roadmap = app.textFields[ArrangementAXID.roadmap].firstMatch
        XCTAssertTrue(roadmap.appears(timeout: 5))
        roadmap.click(in: app)
        app.typeKey("a", modifierFlags: .command, in: app)
        roadmap.typeText("V1 C V2 C -B C C:1\r", in: app)
        SetlistE2E.waitForDisk("The roadmap never reached the setlist file") {
            try Self.modes(root) == ["full", "full", "full", "full", "skip", "full", "first"]
        }
        XCTAssertTrue(sheet.exists, "Return in the roadmap closed the sheet")
        // The footer times the passes played: six one-bar passes at 96 BPM (Skip adds
        // nothing), the default bar per chord, so "~0:15".
        XCTAssertTrue(SetlistE2E.element(app, ArrangementAXID.time).appears(timeout: 5))
        SetlistE2E.waitUntil("The footer never showed the slot's time") {
            app.staticTexts.matching(NSPredicate(
                format: "label CONTAINS %@ OR value CONTAINS %@", "15 seconds", "15 seconds",
            ))
            .firstMatch.exists
        }
        screenshot(app, "arrangement-sheet-arranged")
        click(app, ArrangementAXID.done)
        XCTAssertTrue(sheet.disappears(timeout: 5))

        // The row shows the mark and the slot's own time from its passes (the full song is
        // 8 bars, ~0:20); the song file never changed.
        let mark = SetlistE2E.element(app, ArrangementAXID.mark)
        XCTAssertTrue(mark.appears(timeout: 5))
        XCTAssertEqual(mark.label, "Custom arrangement, 7 passes, 1 skipped")
        XCTAssertEqual(SetlistE2E.labels(app, SetlistAXID.entryTime).first, "~0:15")
        screenshot(app, "arrangement-row")
        let after = try String(
            contentsOf: root.appending(path: "songs/harbor-lights.cho"),
            encoding: .utf8,
        )
        XCTAssertEqual(after, cho, "The song file changed")
        let file = try XCTUnwrap(SetlistFixture.setlistFiles(root).first)
        // Setlist schema 7 holds medley slots (P9-3 5.2); an arranged song slot saves as 7.
        XCTAssertEqual(file["schemaVersion"] as? Int, 7)
    }

    /// "Rehearse this": the stage plays the slot as arranged (no Bridge, the fourth chorus
    /// pass first line only on the map); ending it opens the sheet again.
    @MainActor
    private func rehearseThis(_ app: XCUIApplication) throws {
        let sheet = openSheet(app)
        click(app, ArrangementAXID.rehearse)
        let title = app.staticTexts[ArrangementAXID.liveTitle]
        XCTAssertTrue(title.appears(timeout: 10), "Rehearse this never reached the stage")
        XCTAssertTrue(SetlistE2E.element(app, ArrangementAXID.liveMap).appears(timeout: 5))
        let lastChip = SetlistE2E.element(app, ArrangementAXID.mapChip(6))
        XCTAssertTrue(lastChip.appears(timeout: 5))
        XCTAssertEqual(lastChip.label, "Chorus, 4 of 4, first line only")
        XCTAssertFalse(SetlistE2E.element(app, ArrangementAXID.mapChip(7)).exists)
        XCTAssertEqual(
            app.staticTexts.matching(NSPredicate(format: "value == 'Bridge'")).count,
            0,
            "The skipped Bridge is on stage",
        )
        screenshot(app, "arrangement-rehearse-this")
        app.typeKey(".", modifierFlags: .command, in: app)
        XCTAssertTrue(SetlistE2E.element(app, ArrangementAXID.liveEndDialog).appears(timeout: 5))
        app.typeKey(.return, modifierFlags: [], in: app)
        XCTAssertTrue(title.disappears(timeout: 10))
        XCTAssertTrue(sheet.appears(timeout: 10), "The sheet did not open again")
        click(app, ArrangementAXID.done)
        XCTAssertTrue(sheet.disappears(timeout: 5))
    }

    /// Start Show: the stage says "Arranged", no Bridge, every pass written out (the map's
    /// last chip is the fourth chorus, first line only); the gig log names the arrangement.
    @MainActor
    private func playTheShow(_ app: XCUIApplication) throws {
        click(app, SetlistAXID.setlistStartShow)
        click(app, ArrangementAXID.checklistStart)
        let title = app.staticTexts[ArrangementAXID.liveTitle]
        XCTAssertTrue(title.appears(timeout: 10))
        let tag = app.staticTexts[ArrangementAXID.liveArrangement]
        XCTAssertTrue(tag.appears(timeout: 5))
        XCTAssertEqual(tag.value as? String, "Arranged for this gig")
        let lastChip = SetlistE2E.element(app, ArrangementAXID.mapChip(6))
        XCTAssertTrue(lastChip.appears(timeout: 5))
        XCTAssertEqual(lastChip.label, "Chorus, 4 of 4, first line only")
        XCTAssertFalse(SetlistE2E.element(app, ArrangementAXID.mapChip(7)).exists)
        screenshot(app, "arrangement-stage")
        app.typeKey(".", modifierFlags: .command, in: app)
        XCTAssertTrue(SetlistE2E.element(app, ArrangementAXID.liveEndDialog).appears(timeout: 5))
        app.typeKey(.return, modifierFlags: [], in: app)
        XCTAssertTrue(title.disappears(timeout: 10))

        click(app, SetlistAXID.sidebarGigLog)
        click(app, SetlistAXID.gigLogRow)
        let played = SetlistE2E.element(app, SetlistAXID.gigPlayedRow)
        XCTAssertTrue(played.appears(timeout: 5))
        let text = SetlistE2E.text(played)
        XCTAssertTrue(
            text.contains("Custom arrangement: Verse 1, Chorus, Verse 2, Chorus 2nd"),
            text,
        )
        XCTAssertTrue(text.contains("(first line)"), text)
        screenshot(app, "arrangement-gig-log")
    }

    @MainActor
    private func openSheet(_ app: XCUIApplication) -> XCUIElement {
        app.staticTexts[SetlistAXID.entryTitle].firstMatch.click(in: app)
        click(app, ArrangementAXID.open)
        let sheet = SetlistE2E.element(app, ArrangementAXID.sheet)
        XCTAssertTrue(sheet.appears(timeout: 10), "Arrange Sections never opened")
        return sheet
    }

    /// Renaming a played section in the song makes the slot's arrangement out of date; the
    /// sheet's banner lists it and Update keeps the passes that still match.
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

        let sheet = openSheet(app)
        XCTAssertTrue(SetlistE2E.element(app, ArrangementAXID.missing).appears(timeout: 5))
        click(app, ArrangementAXID.update)
        XCTAssertTrue(SetlistE2E.element(app, ArrangementAXID.missing).disappears(timeout: 5))
        click(app, ArrangementAXID.done)
        XCTAssertTrue(sheet.disappears(timeout: 5))
        SetlistE2E.waitUntil("Update never brought the arrangement back") {
            mark.exists && mark.label.hasPrefix("Custom arrangement")
        }
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
    static let time = "segue.arrangement.time"
    static let sheet = "segue.setlist.arrangement.sheet"
    static let done = "segue.setlist.arrangement.done"
    static let update = "segue.setlist.arrangement.update"
    static let missing = "segue.setlist.arrangement.missing"
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

    static let roadmap = "segue.setlist.arrangement.roadmap"
    static let rehearse = "segue.setlist.arrangement.rehearse"

    static func chip(_ index: Int) -> String {
        "segue.setlist.arrangement.chip.\(index)"
    }

    static func chipDuplicate(_ index: Int) -> String {
        "segue.setlist.arrangement.chip.\(index).duplicate"
    }
}
