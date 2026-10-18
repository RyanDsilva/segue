import XCTest

/// What's New through the real UI (WS2b 4.3): a release in range with `showInApp` shows once
/// with word badges, a range without one stays silent, and Help reopens the notes. Version
/// rules, the Help range and the bundled file are `WhatsNewTests` (in process).
final class SegueWhatsNewE2ETests: XCTestCase {
    private var app: XCUIApplication?
    private var library: WelcomeLibrary?

    override func setUpWithError() throws {
        continueAfterFailure = false
        library = try WelcomeLibrary()
        try Data(Self.changelog.utf8).write(to: changelogFile)
    }

    override func tearDownWithError() throws {
        E2E.terminate(app)
        if let root = library?.root {
            try? FileManager.default.removeItem(at: root)
        }
    }

    private var changelogFile: URL {
        library?.root.appending(path: "changelog.json") ?? URL(filePath: "/dev/null")
    }

    /// 0.7 is shown in the app; 0.6.1 (fixes only) is not.
    static let changelog = """
    {"schema": 1, "releases": [
      {"version": "0.7", "date": "2027-03-02", "title": "Rehearsal notes and faster search",
       "summary": "Notes you take in rehearsal now follow the song onto the stage.",
       "showInApp": true, "highlights": [
        {"kind": "new", "text": "Rehearsal notes appear on stage under the song title.",
         "help": "/help/live"},
        {"kind": "new", "text": "Search finds a song by any line you remember."},
        {"kind": "improved", "text": "Deleted songs and setlists go to the Trash.",
         "help": "/help#trash"}]},
      {"version": "0.6.1", "date": "2027-02-01", "title": "Fixes", "showInApp": false,
       "highlights": [{"kind": "fixed", "text": "The checklist ticks Focus only when it ran."}]}
    ]}
    """

    @MainActor
    func testWhatsNewShowsOnceAndFromHelp() throws {
        let library = try XCTUnwrap(library)
        let changelog = changelogFile.path(percentEncoded: false)
        let app = launch(library.arguments([
            "-SegueChangelogPath", changelog, "-SegueAppVersion", "0.7",
            "-SegueLastSeenVersion", "0.6", "-SegueAppearance", "light",
        ]))
        let title = element(app, WhatsNewAXID.title)
        XCTAssertTrue(title.appears(timeout: 15), "no What's New for 0.7")
        XCTAssertEqual(text(title), "What's New in Segue 0.7")
        XCTAssertTrue(element(app, WhatsNewAXID.release("0.7")).exists)
        XCTAssertFalse(element(app, WhatsNewAXID.release("0.6.1")).exists, "0.6.1 is not in-app")
        let badges = app.descendants(matching: .any).matching(identifier: WhatsNewAXID.badge)
        XCTAssertEqual(badges.count, 3)
        XCTAssertEqual(text(badges.element(boundBy: 0)), "New")
        XCTAssertEqual(text(badges.element(boundBy: 2)), "Improved")
        attach(app, "whatsnew-light")
        element(app, WhatsNewAXID.continueButton).click(in: app)
        XCTAssertTrue(title.disappears(timeout: 5))
        app.terminate()

        // Seen: the relaunch shows nothing. Help reopens 0.7 and the releases before it.
        let again = launch([
            "-SegueLibraryPath", library.root.path(percentEncoded: false),
            "-SegueChangelogPath", changelog, "-SegueAppVersion", "0.7",
            "-SegueAppearance", "dark",
        ])
        XCTAssertTrue(element(again, WhatsNewAXID.sidebarLibrary).appears(timeout: 15))
        XCTAssertFalse(
            E2E.waitUntil(timeout: 2) { self.element(again, WhatsNewAXID.title).exists },
            "What's New came back after it was seen",
        )
        let help = again.menuBars.menuBarItems["Help"]
        help.click(in: again)
        help.menuItems["What's New in Segue"].firstMatch.click()
        XCTAssertTrue(element(again, WhatsNewAXID.title).appears(timeout: 5))
        XCTAssertTrue(element(again, WhatsNewAXID.release("0.6.1")).exists)
        attach(again, "whatsnew-help-dark")
        again.typeKey(.escape, modifierFlags: [], in: again)
        XCTAssertTrue(element(again, WhatsNewAXID.title).disappears(timeout: 5), "Esc kept it")
    }

    @MainActor
    func testRangeWithoutShowInAppIsSilent() throws {
        let library = try XCTUnwrap(library)
        let app = launch(library.arguments([
            "-SegueChangelogPath", changelogFile.path(percentEncoded: false),
            "-SegueAppVersion", "0.6.1", "-SegueLastSeenVersion", "0.6",
        ]))
        XCTAssertTrue(element(app, WhatsNewAXID.sidebarLibrary).appears(timeout: 15))
        XCTAssertFalse(E2E.waitUntil(timeout: 2) {
            self.element(app, WhatsNewAXID.title).exists
        }, "a sheet for a release the author kept out of the app")
    }
}

@MainActor
extension SegueWhatsNewE2ETests {
    private func launch(_ arguments: [String]) -> XCUIApplication {
        let app = XCUIApplication()
        self.app = app
        E2E.launch(app, arguments: arguments)
        return app
    }

    private func element(_ app: XCUIApplication, _ identifier: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    private func text(_ element: XCUIElement) -> String {
        [element.value as? String, element.label].compactMap(\.self).first { !$0.isEmpty } ?? ""
    }

    private func attach(_ app: XCUIApplication, _ name: String) {
        E2E.waitUntil(timeout: 0.4) { false }
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}

/// Identifiers the What's New E2E uses (mirrors `AccessibilityID` in SegueUI).
enum WhatsNewAXID {
    static let title = "segue.whatsNew.title"
    static let badge = "segue.whatsNew.badge"
    static let continueButton = "segue.whatsNew.continue"
    static let sidebarLibrary = "segue.sidebar.library"
    static func release(_ version: String) -> String {
        "segue.whatsNew.release.\(version)"
    }
}
