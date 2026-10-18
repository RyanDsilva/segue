import XCTest

/// E2E smoke test: the app launches from a clean baseline and shows the library chooser.
/// (Help > Acknowledgements and its credits are checked in `SegueCoreUXE2ETests.testMenus`.)
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
        // Reset state + no library path: the first-launch library chooser.
        XCTAssertTrue(app.buttons["segue.chooser.create"].exists)
        XCTAssertTrue(app.buttons["segue.chooser.open"].exists)
        let screenshot = XCTAttachment(screenshot: app.windows.firstMatch.screenshot())
        screenshot.name = "library-chooser"
        screenshot.lifetime = .keepAlways
        add(screenshot)

        app.terminate()
    }
}
