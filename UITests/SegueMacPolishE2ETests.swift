import XCTest

/// Mac polish (P9-5 9.3, 9.4): the offline Help Book opens in Tips, the macOS 26 Help Viewer,
/// from Help > Segue Help and from an in-app Help button; and the launch-time metric. The
/// routing, the web fallback and the waits while performing are `HelpBookRoutingTests`.
final class SegueMacPolishE2ETests: XCTestCase {
    private var app: XCUIApplication?
    private var library: WelcomeLibrary?

    override func setUpWithError() throws {
        continueAfterFailure = false
        library = try WelcomeLibrary()
    }

    override func tearDownWithError() throws {
        quitTips()
        E2E.terminate(app)
        if let root = library?.root {
            try? FileManager.default.removeItem(at: root)
        }
    }

    @MainActor
    func testHelpOpensTheBook() throws {
        let library = try XCTUnwrap(library)
        quitTips()
        let app = XCUIApplication()
        self.app = app
        E2E.launch(app, arguments: library.arguments(["-SegueHelpBook", "YES"]))

        // Help > Segue Help: Tips comes to the front with the book.
        let help = app.menuBars.menuBarItems["Help"]
        help.click(in: app)
        help.menuItems["Segue Help"].firstMatch.click()
        XCTAssertTrue(tips.reaches(.runningForeground, timeout: 20), "Tips did not open")
        quitTips()

        // Settings > Live's Help button opens its page in the book too.
        E2E.bringToFront(app)
        app.typeKey(",", modifierFlags: .command, in: app)
        let live = app.toolbars.buttons["Live"].firstMatch
        XCTAssertTrue(live.appears(timeout: 10), "no Settings")
        live.click(in: app)
        let button = app.descendants(matching: .any)
            .matching(identifier: "segue.guideHelp.minimumSize").firstMatch
        XCTAssertTrue(button.appears(timeout: 10), "no Help button in Settings > Live")
        button.click(in: app)
        XCTAssertTrue(tips.reaches(.runningForeground, timeout: 20), "Tips did not open")
    }

    /// P9-5 P4: launch to the first frame on the Welcome library (Debug build), recorded in
    /// docs/test-performance.md and never asserted, so Help Book registration and later
    /// launch work show up as a number.
    @MainActor
    func testLaunchTime() throws {
        let library = try XCTUnwrap(library)
        let app = XCUIApplication()
        self.app = app
        app.launchArguments = library.arguments(["-SegueSeedWelcome", "YES"])
            + E2E.freshInstanceArguments + E2E.statePathArguments
        let options = XCTMeasureOptions()
        options.iterationCount = 3
        measure(metrics: [XCTApplicationLaunchMetric()], options: options) {
            app.launch()
        }
    }

    /// Tips (`com.apple.helpviewer`), which shows Help Books.
    @MainActor
    private var tips: XCUIApplication {
        XCUIApplication(bundleIdentifier: "com.apple.helpviewer")
    }
}

/// Quits Tips if it is running, so each check starts with it closed.
private func quitTips() {
    MainActor.assumeIsolated {
        let tips = XCUIApplication(bundleIdentifier: "com.apple.helpviewer")
        if tips.state != .notRunning {
            tips.terminate()
        }
    }
}
