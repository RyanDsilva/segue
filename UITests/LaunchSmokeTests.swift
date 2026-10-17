import XCTest

/// E2E smoke test: the app launches from a clean baseline and shows its main window.
final class LaunchSmokeTests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testLaunchShowsMainWindow() {
        let app = XCUIApplication()
        app.launchArguments = ["-SegueResetState", "YES"]
        app.launch()

        let title = app.staticTexts["segue.root.title"]
        XCTAssertTrue(title.waitForExistence(timeout: 10))
        XCTAssertEqual(title.value as? String, "Segue")

        app.terminate()
    }
}
