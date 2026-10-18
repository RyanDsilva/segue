import XCTest

/// File-level integration through the real UI (WS2b 4.7, 4.8): File > Export Library Archive…
/// writes a zip (its contents are checked by `LibraryArchiveTests` in SegueCore).
///
/// Open With is `OpenDocumentsTests` (in process): `XCUIApplication.open(_:)` with a file URL
/// ended the app under test on macOS 26, so the Finder double-click is a manual check
/// (docs/release/walkthrough.md).
final class SegueFinderE2ETests: XCTestCase {
    private var app: XCUIApplication?
    private var library: WelcomeLibrary?

    override func setUpWithError() throws {
        continueAfterFailure = false
        library = try WelcomeLibrary()
    }

    override func tearDownWithError() throws {
        E2E.terminate(app)
        if let root = library?.root {
            try? FileManager.default.removeItem(at: root)
        }
    }

    @MainActor
    func testExportLibraryArchive() throws {
        let library = try XCTUnwrap(library)
        let zip = library.root.appending(path: "out.zip")
        let app = launch(library.arguments([
            "-SegueSeedWelcome", "YES", "-SegueExportPath", zip.path(percentEncoded: false),
        ]))
        XCTAssertTrue(element(app, FinderAXID.songRow).appears(timeout: 15))
        let file = app.menuBars.menuBarItems["File"]
        file.click(in: app)
        let item = file.menuItems["Export Library Archive…"].firstMatch
        XCTAssertTrue(item.appears(timeout: 5), "no File > Export Library Archive…")
        item.click()
        XCTAssertTrue(E2E.waitUntil {
            ((try? Data(contentsOf: zip)) ?? Data()).starts(with: Data("PK".utf8))
        }, "no zip written")
        XCTAssertGreaterThan(try Data(contentsOf: zip).count, 1000)
    }
}

@MainActor
extension SegueFinderE2ETests {
    private func launch(_ arguments: [String]) -> XCUIApplication {
        let app = XCUIApplication()
        self.app = app
        E2E.launch(app, arguments: arguments)
        return app
    }

    private func element(_ app: XCUIApplication, _ identifier: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }
}

/// Identifiers the Finder E2E uses (mirrors `AccessibilityID` in SegueUI).
enum FinderAXID {
    static let songRow = "segue.library.row"
}
