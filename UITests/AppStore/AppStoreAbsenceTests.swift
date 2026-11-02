import XCTest

/// P9-4 spec 15.5: the App Store flavour has no web import and no Find Lyrics. No File menu
/// item, no shortcut, and a lone address pasted into New Song is converted as
/// text, as it always was (no web field, no fetch).
@MainActor
final class AppStoreAbsenceTests: XCTestCase {
    private var app: XCUIApplication?

    override func setUp() async throws {
        continueAfterFailure = false
    }

    override func tearDown() async throws {
        E2E.terminate(app)
    }

    func testNoWebImportOrFindLyrics() {
        let app = XCUIApplication()
        self.app = app
        // The Welcome library in the container: the App Store flavour has no
        // /private/tmp/segue-e2e exception (see GuideShotSupport.statePath).
        E2E.launch(app, arguments: [
            "-SegueScreenshotLibrary", "YES",
            "-SegueResetState", "YES",
            "-SegueStatePath", Self.statePath,
        ])
        XCTAssertTrue(element(app, "segue.library.list").appears(timeout: 15))

        let file = app.menuBars.menuBarItems["File"]
        file.click(in: app)
        XCTAssertTrue(file.menuItems["Import Songs…"].appears(timeout: 5))
        XCTAssertFalse(file.menuItems["Import from Web Page…"].exists)
        XCTAssertFalse(file.menuItems["Find Lyrics…"].exists)
        app.typeKey(.escape, modifierFlags: [], in: app)

        // ⇧⌘L and ⇧⌘U open nothing.
        app.typeKey("l", modifierFlags: [.command, .shift], in: app)
        app.typeKey("u", modifierFlags: [.command, .shift], in: app)
        XCTAssertFalse(element(app, "segue.paste.sheet").exists)

        // New Song: no web field; a lone address is typed text and converts as a paste.
        app.typeKey("n", modifierFlags: .command, in: app)
        let input = element(app, "segue.paste.input")
        XCTAssertTrue(input.appears(timeout: 10), "No New Song sheet")
        XCTAssertFalse(element(app, "segue.paste.webField").exists)
        input.click(in: app)
        input.typeText("https://example.com/tab/tum-hi-ho-chords", in: app)
        app.typeKey(.return, modifierFlags: .command, in: app)
        XCTAssertTrue(element(app, "segue.paste.accept").appears(timeout: 10), "No review")
        XCTAssertFalse(element(app, "segue.paste.sourceLine").exists)
        element(app, "segue.paste.cancel").click(in: app)
        XCTAssertTrue(element(app, "segue.paste.sheet").disappears(timeout: 10))
    }

    static let statePath: String = {
        let home = getpwuid(getuid()).map { String(cString: $0.pointee.pw_dir) }
            ?? NSHomeDirectory()
        return "\(home)/Library/Containers/dev.ryandsilva.segue/Data/tmp/"
            + "segue-absence-state-\(UUID().uuidString)"
    }()

    private func element(_ app: XCUIApplication, _ identifier: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }
}
