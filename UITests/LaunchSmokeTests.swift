import XCTest

/// E2E smoke test: the app launches from a clean baseline and shows the Welcome sheet's
/// library page (WS2b 4.1) over the wordmark.
final class LaunchSmokeTests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testLaunchShowsMainWindow() {
        let app = XCUIApplication()
        E2E.launch(app, arguments: ["-SegueResetState", "YES"])

        let title = app.staticTexts["segue.root.title"]
        XCTAssertTrue(title.appears(timeout: 10))
        XCTAssertEqual(title.value as? String, "Segue")
        // Reset state + no library path: the chooser's buttons are on the Welcome sheet's
        // page 1.
        XCTAssertTrue(app.buttons["segue.chooser.create"].appears(timeout: 10))
        XCTAssertTrue(app.buttons["segue.chooser.open"].exists)
        XCTAssertTrue(app.staticTexts["segue.welcome.step"].exists)
        let screenshot = XCTAttachment(screenshot: app.windows.firstMatch.screenshot())
        screenshot.name = "welcome-library-page"
        screenshot.lifetime = .keepAlways
        add(screenshot)

        app.terminate()
    }
}
