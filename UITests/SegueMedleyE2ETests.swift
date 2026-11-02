import XCTest

/// Medleys end to end (P9-3 17.5): a fresh library with a setlist of three songs with
/// tempos in different keys; Arrange, select rows 1-2 (click, Shift-click), Shift-Cmd-M; the
/// medley row reads "2 songs" and "E → A"; a transition is typed; on disk the setlist is
/// schema 7 with one medley of two members and the transition; Start Show; the header reads
/// "Medley 1 of 2", the map groups both members and the footer says "Next in medley"; →
/// brings the second member's header and transition, and the footer then reads "Up next"
/// with song 3; Page Down to the bottom reaches song 3; End Show; the Gig Log nests the two
/// members under the medley.
final class SegueMedleyE2ETests: SetlistE2ETestCase {
    private static let setlistID = "01JC0000000000000000000T31"
    private static let titles = ["Northbound", "Kitchen Radio", "Lamplighter"]

    @MainActor
    func testMakeMedleyAndPlayThrough() throws {
        let root = try XCTUnwrap(libraryRoot)
        try seedSetlist(root)
        let app = try launch()

        try makeMedley(app, root)
        try playThrough(app)
        try gigLog(app)
    }

    // MARK: - Steps

    @MainActor
    private func makeMedley(_ app: XCUIApplication, _ root: URL) throws {
        SetlistE2E.element(app, MedleyAXID.sidebarSetlists).click(in: app)
        let row = SetlistE2E.element(app, SetlistAXID.setlistRow)
        XCTAssertTrue(row.appears(timeout: 10), "the setlist is not listed")
        row.click(in: app)
        E2E.bringToFront(app)
        app.typeKey("2", modifierFlags: .command, in: app)

        let entries = SetlistE2E.all(app, SetlistAXID.setlistEntry)
        SetlistE2E.waitUntil("the three slots never listed") { entries.count == 3 }
        entries.element(boundBy: 0).click(in: app)
        // Close the slot popover the plain click opened, then Shift-click the second row.
        app.typeKey(.escape, modifierFlags: [], in: app)
        XCUIElement.perform(withKeyModifiers: .shift) {
            entries.element(boundBy: 1).click()
        }
        app.typeKey("m", modifierFlags: [.command, .shift], in: app)

        let medley = SetlistE2E.element(app, MedleyAXID.medley)
        XCTAssertTrue(medley.appears(timeout: 10), "no medley row after Shift-Cmd-M")
        XCTAssertEqual(SetlistE2E.text(SetlistE2E.element(app, MedleyAXID.songCount)), "2 songs")
        XCTAssertTrue(SetlistE2E.text(SetlistE2E.element(app, MedleyAXID.keyPath))
            .contains("E to A"))
        screenshot(app, "medley-made")

        // The transition into the second member.
        SetlistE2E.element(app, MedleyAXID.transition).click(in: app)
        let field = app.textFields[MedleyAXID.transition].firstMatch
        XCTAssertTrue(field.appears(timeout: 5), "the transition field never opened")
        field.typeText("Hold the E, drums fill\n", in: app)
        screenshot(app, "medley-transition")

        SetlistE2E.waitForDisk("the medley never reached the setlist file") {
            let file = try XCTUnwrap(SetlistFixture.setlistFiles(root)
                .first { $0["id"] as? String == Self.setlistID })
            guard file["schemaVersion"] as? Int == 7,
                  let entries = file["entries"] as? [[String: Any]],
                  let medley = entries.first?["medley"] as? [String: Any],
                  let members = medley["members"] as? [[String: Any]]
            else { return false }
            return entries.count == 2 && members.count == 2
                && members[1]["transition"] as? String == "Hold the E, drums fill"
                && members.map { $0["songId"] as? String }
                == Self.titles.prefix(2).map { SetlistFixture.song($0).id }
        }
    }

    @MainActor
    private func playThrough(_ app: XCUIApplication) throws {
        SetlistE2E.element(app, SetlistAXID.setlistStartShow).click(in: app)
        let start = SetlistE2E.element(app, MedleyAXID.checklistStart)
        XCTAssertTrue(start.appears(timeout: 10), "no pre-show checklist")
        start.click(in: app)
        let title = app.staticTexts[MedleyAXID.liveTitle]
        XCTAssertTrue(title.appears(timeout: 10), "the stage never opened")

        let chip = SetlistE2E.element(app, MedleyAXID.liveMedley)
        XCTAssertTrue(chip.appears(timeout: 10), "no medley chip on stage")
        XCTAssertTrue(SetlistE2E.text(chip).contains("1 of 2"), SetlistE2E.text(chip))
        XCTAssertEqual(SetlistE2E.all(app, MedleyAXID.mapMember).count, 2)
        let upNextLabel = SetlistE2E.element(app, MedleyAXID.upNextLabel)
        SetlistE2E.waitUntil("the footer never read Next in medley") {
            SetlistE2E.text(upNextLabel) == "Next in medley"
        }
        screenshot(app, "medley-stage-1")

        // → : the second member, its header and transition in view; the footer moves on.
        E2E.bringToFront(app)
        app.typeKey(.rightArrow, modifierFlags: [], in: app)
        SetlistE2E.waitUntil("the chip never read Medley 2 of 2") {
            SetlistE2E.text(chip).contains("2 of 2")
        }
        XCTAssertTrue(SetlistE2E.element(app, MedleyAXID.memberTransition).exists)
        SetlistE2E.waitUntil("the footer never read Up next") {
            SetlistE2E.text(upNextLabel) == "Up next"
        }
        XCTAssertTrue(SetlistE2E.text(SetlistE2E.element(app, MedleyAXID.upNext))
            .contains(Self.titles[2]))
        screenshot(app, "medley-stage-2")

        // Page Down through to the bottom: song 3.
        for _ in 0 ..< 30 where SetlistE2E.text(title) != Self.titles[2] {
            app.typeKey(.pageDown, modifierFlags: [], in: app)
        }
        SetlistE2E.waitUntil("Page Down never reached \(Self.titles[2])") {
            SetlistE2E.text(title) == Self.titles[2]
        }
        XCTAssertFalse(chip.exists, "the medley chip stayed after the medley")

        // End the show.
        app.typeKey(".", modifierFlags: .command, in: app)
        XCTAssertTrue(SetlistE2E.element(app, MedleyAXID.endDialog).appears(timeout: 5))
        app.typeKey(.return, modifierFlags: [], in: app)
        XCTAssertTrue(title.disappears(timeout: 10))
    }

    @MainActor
    private func gigLog(_ app: XCUIApplication) throws {
        SetlistE2E.element(app, SetlistAXID.sidebarGigLog).click(in: app)
        let entry = SetlistE2E.element(app, SetlistAXID.gigLogRow)
        XCTAssertTrue(entry.appears(timeout: 10), "no gig in the Gig Log")
        entry.click(in: app)
        let medley = SetlistE2E.element(app, MedleyAXID.gigMedley)
        XCTAssertTrue(medley.appears(timeout: 10), "the Gig Log shows no medley")
        XCTAssertEqual(SetlistE2E.all(app, MedleyAXID.gigMedleyMember).count, 2)
        screenshot(app, "medley-gig-log")
    }

    // MARK: - Seed

    /// "Medley Night": Northbound (E), Kitchen Radio (A), Lamplighter (F) as slots (schema 6).
    private func seedSetlist(_ root: URL) throws {
        let rows = Self.titles.enumerated().map { offset, title in
            #"{"itemId": "01JC0000000000000000000E3\#(offset)", "#
                + #""songId": "\#(SetlistFixture.song(title).id)"}"#
        }
        try SetlistFixture.write(
            #"{"schemaVersion": 6, "id": "\#(Self.setlistID)", "name": "Medley Night", "#
                + #""entries": [\#(rows.joined(separator: ", "))]}"#,
            to: root.appending(path: "setlists/medley-night.setlist.json"),
        )
    }
}

/// Mirrors `AccessibilityID` (SegueUI) for the medley flow.
private enum MedleyAXID {
    static let sidebarSetlists = "segue.sidebar.setlists"
    static let medley = "segue.setlist.medley"
    static let songCount = "segue.setlist.medley.songs"
    static let keyPath = "segue.setlist.medley.keyPath"
    static let transition = "segue.setlist.medley.transition"
    static let checklistStart = "segue.live.checklist.start"
    static let liveTitle = "segue.live.title"
    static let liveMedley = "segue.live.medley"
    static let mapMember = "segue.live.map.member"
    static let memberTransition = "segue.live.medley.transition"
    static let upNext = "segue.live.upNext"
    static let upNextLabel = "segue.live.upNextLabel"
    static let endDialog = "segue.live.endDialog"
    static let gigMedley = "segue.gig.medley"
    static let gigMedleyMember = "segue.gig.medley.member"
}
