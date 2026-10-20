import XCTest

/// R102: no song twice in a show. Quick search shows where a song stands, refuses a played
/// one ("Already played tonight") and offers Move to Next for one still in the set.
@MainActor
extension SegueLiveE2ETests {
    func testQuickSearchRefusesARepeatAndMovesAnUpcomingSongToNext() throws {
        let library = try XCTUnwrap(library)
        let app = launch(library)
        startShow(app, rehearse: false)
        let title = app.staticTexts[LiveAXID.liveTitle]
        key(app, .rightArrow)
        XCTAssertTrue(waitForValue(title, "Paper Boats"))

        // Song 1 was played: its row says so, and Insert Next is refused.
        key(app, "/")
        let field = app.textFields[LiveAXID.liveSearchField]
        XCTAssertTrue(field.appears(timeout: 5))
        field.typeText("harbor", in: app)
        let result = element(app, LiveAXID.liveSearchResult)
        XCTAssertTrue(result.appears(timeout: 5))
        XCTAssertTrue(
            waitFor(result) { ($0.value as? String) == "Already played" },
            result.debugDescription,
        )
        key(app, .return, [.option])
        let refusal = element(app, LiveAXID.liveSearchRefusal)
        XCTAssertTrue(refusal.appears(timeout: 5))
        XCTAssertEqual(refusal.label, "Already played tonight: Harbor Lights")
        screenshot(app, "50-search-already-played")
        // Esc goes back to the results; nothing was added.
        key(app, .escape)
        XCTAssertTrue(refusal.disappears(timeout: 5))
        XCTAssertTrue(field.appears(timeout: 5))

        // Night Bus is still in the set: refused with Move to Next, which Return confirms.
        field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 6), in: app)
        field.typeText("night bus", in: app)
        XCTAssertTrue(waitFor(result) { $0.label.contains("Night Bus") }, result.label)
        key(app, .return, [.option])
        XCTAssertTrue(refusal.appears(timeout: 5))
        XCTAssertEqual(refusal.label, "Already in the set: Night Bus")
        XCTAssertTrue(element(app, LiveAXID.liveSearchMoveToNext).exists)
        screenshot(app, "51-search-already-in-set")
        key(app, .return)
        XCTAssertTrue(element(app, LiveAXID.liveSearch).disappears(timeout: 5))
        XCTAssertTrue(waitForValue(app.staticTexts[LiveAXID.liveUpNext], "Night Bus"))
        XCTAssertEqual(app.staticTexts[LiveAXID.liveUpNextLabel].value as? String, "Up next")
        XCTAssertEqual(app.staticTexts[LiveAXID.livePosition].value as? String, "2 of 10")
        screenshot(app, "52-moved-to-next")
    }
}
