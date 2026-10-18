import XCTest

/// The review prompt through real shows (WS2b 4.5, R20, A12), with `-SegueReviewLog` as the
/// oracle (the OS rate-limits the real prompt and TestFlight never shows it): after the 1st
/// completed gig once the end-of-show flow is done, once per version, never for a rehearsal,
/// never while the stage is up. The rules table is `ReviewPromptPolicyTests`.
final class SegueReviewPromptE2ETests: XCTestCase {
    private var library: LiveLibrary?
    private var app: XCUIApplication?

    override func setUpWithError() throws {
        continueAfterFailure = false
        library = try LiveLibrary()
    }

    override func tearDownWithError() throws {
        E2E.terminate(app)
        library?.remove()
    }

    private var reviewLog: URL {
        library?.root.appending(path: "reviews.log") ?? URL(filePath: "/dev/null")
    }

    private func requests() -> Int {
        let text = (try? String(contentsOf: reviewLog, encoding: .utf8)) ?? ""
        return text.split(separator: "\n").count
    }

    @MainActor
    func testReviewAfterFirstGigOncePerVersion() throws {
        let library = try XCTUnwrap(library)
        let log = reviewLog.path(percentEncoded: false)
        let app = launch(library.arguments(extra: [
            "-SegueReviewLog", log, "-SegueAppVersion", "0.5",
        ]))

        // The 1st gig: nothing while the stage is up, one request once it is over.
        playShow(app, rehearse: false)
        XCTAssertTrue(E2E.waitUntil(timeout: 8) { self.requests() == 1 }, "no review request")
        XCTAssertFalse(E2E.waitUntil(timeout: 1) { self.requests() > 1 })

        // A rehearsal and a 2nd gig in the same version: no new request.
        playShow(app, rehearse: true)
        playShow(app, rehearse: false)
        XCTAssertFalse(E2E.waitUntil(timeout: 4) { self.requests() != 1 }, "asked twice in 0.5")
        app.terminate()

        // A new version with one gig already counted: the next gig asks again.
        let updated = launch(library.arguments(reset: false, extra: [
            "-SegueReviewLog", log, "-SegueAppVersion", "0.6", "-SegueCompletedGigs", "1",
        ]))
        playShow(updated, rehearse: false)
        XCTAssertTrue(E2E.waitUntil(timeout: 8) { self.requests() == 2 }, "no request in 0.6")
    }
}

@MainActor
extension SegueReviewPromptE2ETests {
    private func launch(_ arguments: [String]) -> XCUIApplication {
        let app = XCUIApplication()
        self.app = app
        E2E.launch(app, arguments: arguments)
        return app
    }

    private func element(_ app: XCUIApplication, _ identifier: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    /// Starts the Friday setlist as a gig (or rehearsal), checks the prompt stays away on
    /// stage, ends it and answers any reorder review.
    private func playShow(_ app: XCUIApplication, rehearse: Bool) {
        let before = requests()
        element(app, LiveAXID.sidebarSetlists).click(in: app)
        let row = element(app, LiveAXID.setlistRow)
        XCTAssertTrue(row.appears(timeout: 10))
        row.click(in: app)
        let start = element(app, rehearse ? LiveAXID.setlistRehearse : LiveAXID.setlistStartShow)
        XCTAssertTrue(start.appears(timeout: 10))
        start.click(in: app)
        let checklistStart = element(app, LiveAXID.checklistStart)
        if checklistStart.appears(timeout: 3) {
            checklistStart.click(in: app)
        }
        let title = app.staticTexts[LiveAXID.liveTitle]
        XCTAssertTrue(title.appears(timeout: 10))
        app.typeKey(.rightArrow, modifierFlags: [], in: app)
        XCTAssertFalse(E2E.waitUntil(timeout: 1) { self.requests() != before }, "asked on stage")
        app.typeKey(".", modifierFlags: .command, in: app)
        XCTAssertTrue(element(app, LiveAXID.liveEndDialog).appears(timeout: 5))
        app.typeKey(.return, modifierFlags: [], in: app)
        XCTAssertTrue(title.disappears(timeout: 10))
        let discard = element(app, LiveAXID.reorderDiscard)
        if discard.appears(timeout: 2) {
            XCTAssertEqual(requests(), before, "asked before the review was answered")
            discard.click(in: app)
            XCTAssertTrue(discard.disappears(timeout: 5))
        }
    }
}
