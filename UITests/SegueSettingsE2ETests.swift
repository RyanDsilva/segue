import XCTest

/// Settings (WS2b 4.6) and Help > Welcome to Segue… through the real UI: the six panes, the
/// last pane restored, Appearance kept across a relaunch, Remove Welcome Songs moving files to
/// the Trash, and the Welcome sheet's revisit mode adding them back. The reset scopes and the
/// edited-song rule are `WelcomeSeedingTests` (in process).
final class SegueSettingsE2ETests: XCTestCase {
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

    /// Appearance > Dark, every pane in dark, then the last pane comes back after closing.
    @MainActor
    private func darkPanesAndRestore(_ app: XCUIApplication) {
        pane(app, "Appearance")
        let dark = app.radioButtons["Dark"].firstMatch
        XCTAssertTrue(dark.appears(timeout: 5))
        dark.click(in: app)
        XCTAssertTrue(E2E.waitUntil { (dark.value as? Int) == 1 })
        attach(app, "settings-appearance-dark")
        pane(app, "Live")
        attach(app, "settings-live-dark")
        pane(app, "AI")
        attach(app, "settings-ai-dark")
        pane(app, "Privacy")
        attach(app, "settings-privacy-dark")
        pane(app, "Data")
        attach(app, "settings-data-dark")
        app.typeKey("w", modifierFlags: .command, in: app)
        XCTAssertTrue(element(app, SettingsAXID.pane("data")).disappears(timeout: 10))
        openSettings(app)
        XCTAssertTrue(
            element(app, SettingsAXID.pane("data")).appears(timeout: 5),
            "Settings did not reopen on Data",
        )
        app.typeKey("w", modifierFlags: .command, in: app)
    }

    /// Help > Welcome to Segue…: revisit mode adds the songs back; Esc closes it.
    @MainActor
    private func addWelcomeSongsFromHelp(
        _ app: XCUIApplication,
        _ library: WelcomeLibrary,
    ) throws {
        let help = app.menuBars.menuBarItems["Help"]
        help.click(in: app)
        help.menuItems["Welcome to Segue…"].firstMatch.click()
        let add = element(app, SettingsAXID.welcomeAdd)
        XCTAssertTrue(add.appears(timeout: 10), "no Add Welcome Songs in revisit mode")
        XCTAssertFalse(element(app, SettingsAXID.welcomeStep).exists, "revisit shows a step")
        attach(app, "welcome-revisit-dark")
        add.click(in: app)
        XCTAssertTrue(element(app, SettingsAXID.welcomeInLibrary).appears(timeout: 10))
        XCTAssertEqual(try library.songFiles().count, 4)
        app.typeKey(.escape, modifierFlags: [], in: app)
        XCTAssertTrue(element(app, SettingsAXID.welcomeTitle).disappears(timeout: 5))
    }

    @MainActor
    func testSettingsPanesAndWelcomeSongs() throws {
        let library = try XCTUnwrap(library)
        let trash = library.root.appending(path: "Trash", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: trash, withIntermediateDirectories: true)
        let app = launch(library.arguments([
            "-SegueSeedWelcome", "YES", "-SegueRememberLibrary", "YES",
            "-SegueTrashPath", trash.path(percentEncoded: false), "-SegueAppearance", "light",
        ]))
        XCTAssertTrue(row(app, SettingsAXID.songRow, "Soundcheck at Seven").appears(timeout: 15))

        // Six panes; General shows the folder.
        openSettings(app)
        for pane in ["General", "Appearance", "Live", "AI", "Privacy", "Data"] {
            XCTAssertTrue(app.toolbars.buttons[pane].firstMatch.exists, "no \(pane) pane")
        }
        pane(app, "General")
        let path = element(app, SettingsAXID.libraryPath)
        XCTAssertTrue(path.appears(timeout: 5))
        XCTAssertTrue(text(path).hasSuffix(library.root.lastPathComponent), text(path))
        XCTAssertTrue(element(app, SettingsAXID.showLibrary).exists)
        attach(app, "settings-general-light")

        // Data > Remove Welcome Songs… > Move to Trash.
        pane(app, "Data")
        attach(app, "settings-data-light")
        element(app, SettingsAXID.removeWelcome).click(in: app)
        let confirm = element(app, SettingsAXID.removeWelcomeConfirm)
        XCTAssertTrue(confirm.appears(timeout: 10), "no confirmation")
        attach(app, "settings-remove-welcome")
        confirm.click(in: app)
        XCTAssertTrue(
            E2E.waitUntil { (try? library.songFiles())?.isEmpty == true },
            "songs still there",
        )
        // The songs move first, then the setlist: wait for both.
        let trashed = { (try? FileManager.default.contentsOfDirectory(atPath: trash.path)) ?? [] }
        XCTAssertTrue(
            E2E.waitUntil { trashed().contains("welcome-set.setlist.json") },
            "\(trashed())",
        )
        XCTAssertTrue(trashed().contains("soundcheck-at-seven.cho"), "\(trashed())")

        darkPanesAndRestore(app)

        try addWelcomeSongsFromHelp(app, library)
        app.terminate()

        // Appearance is kept across a relaunch; Match System puts it back.
        let relaunched = launch(["-SegueTestDefaults", "YES"])
        XCTAssertTrue(element(relaunched, SettingsAXID.sidebarLibrary).appears(timeout: 15))
        openSettings(relaunched)
        pane(relaunched, "Appearance")
        let kept = relaunched.radioButtons["Dark"].firstMatch
        XCTAssertTrue(kept.appears(timeout: 5))
        XCTAssertEqual(kept.value as? Int, 1, "Dark was not kept")
        let system = relaunched.radioButtons["Match System"].firstMatch
        system.click(in: relaunched)
        XCTAssertTrue(E2E.waitUntil { (system.value as? Int) == 1 })
    }
}

@MainActor
extension SegueSettingsE2ETests {
    private func launch(_ arguments: [String]) -> XCUIApplication {
        let app = XCUIApplication()
        self.app = app
        E2E.launch(app, arguments: arguments)
        return app
    }

    private func openSettings(_ app: XCUIApplication) {
        app.typeKey(",", modifierFlags: .command, in: app)
        XCTAssertTrue(app.toolbars.buttons["General"].firstMatch.appears(timeout: 10))
    }

    private func pane(_ app: XCUIApplication, _ title: String) {
        app.toolbars.buttons[title].firstMatch.click(in: app)
        // The window title follows the pane.
        XCTAssertTrue(app.windows[title].firstMatch.appears(timeout: 5), "no \(title) pane")
    }

    private func element(_ app: XCUIApplication, _ identifier: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    private func row(_ app: XCUIApplication, _ identifier: String, _ text: String)
        -> XCUIElement
    {
        app.descendants(matching: .any)
            .matching(NSPredicate(
                format: "identifier == %@ AND label CONTAINS %@",
                argumentArray: [identifier, text],
            ))
            .firstMatch
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

/// Identifiers the Settings E2E uses (mirrors `AccessibilityID` in SegueUI).
enum SettingsAXID {
    static func pane(_ name: String) -> String {
        "segue.settings.pane.\(name)"
    }

    static let libraryPath = "segue.settings.general.libraryPath"
    static let showLibrary = "segue.settings.general.showInFinder"
    static let removeWelcome = "segue.settings.data.removeWelcome"
    static let removeWelcomeConfirm = "segue.settings.data.removeWelcome.confirm"
    static let welcomeAdd = "segue.welcome.addWelcomeSongs"
    static let welcomeInLibrary = "segue.welcome.inLibrary"
    static let welcomeStep = "segue.welcome.step"
    static let welcomeTitle = "segue.welcome.title"
    static let songRow = "segue.library.row"
    static let sidebarLibrary = "segue.sidebar.library"
}
