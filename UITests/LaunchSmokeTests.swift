import XCTest

/// E2E smoke test: the app launches from a clean baseline and shows the library chooser.
final class LaunchSmokeTests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testLaunchShowsMainWindow() {
        let app = XCUIApplication()
        E2E.launch(app, arguments: ["-SegueResetState", "YES"])

        let title = app.staticTexts["segue.root.title"]
        XCTAssertTrue(title.waitForExistence(timeout: 10))
        XCTAssertEqual(title.value as? String, "Segue")
        // Reset state + no library path: the first-launch library chooser.
        XCTAssertTrue(app.buttons["segue.chooser.create"].exists)
        XCTAssertTrue(app.buttons["segue.chooser.open"].exists)
        let screenshot = XCTAttachment(screenshot: app.windows.firstMatch.screenshot())
        screenshot.name = "library-chooser"
        screenshot.lifetime = .keepAlways
        add(screenshot)

        // Help > Acknowledgements (moved from the app menu, A34) credits the bundled font
        // and dependencies.
        app.menuBars.menuBarItems["Help"].click(in: app)
        app.menuBars.menuBarItems["Help"].menuItems["Acknowledgements"].click(in: app)
        let acknowledgements = app.descendants(matching: .any)
            .matching(identifier: "segue.acknowledgements").firstMatch
        XCTAssertTrue(acknowledgements.waitForExistence(timeout: 5))
        for name in ["Schibsted Grotesk", "GRDB", "Tonic"] {
            XCTAssertTrue(acknowledgements.staticTexts[name].exists, "\(name) not credited")
        }
        let ofl = NSPredicate(format: "value BEGINSWITH %@", "SIL Open Font License 1.1")
        XCTAssertTrue(acknowledgements.staticTexts.matching(ofl).firstMatch.exists)
        let credits = XCTAttachment(screenshot: app.windows["Acknowledgements"].screenshot())
        credits.name = "acknowledgements"
        credits.lifetime = .keepAlways
        add(credits)

        app.terminate()
    }
}
