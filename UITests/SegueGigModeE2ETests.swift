import XCTest

/// Gig Mode Shortcuts and the pre-show checklist's Focus row (R18, R35; WS1 6.3): the
/// Shortcuts are off until the user sets them up, and the Focus row ticks only on observed
/// completion or the performer's Done. Every test starts from a reset library with the
/// recording runner (`-SegueShortcutLog`): the production Shortcuts Events runner talking to a
/// fake Shortcuts Events that answers by name prefix like the real one did in the R35 probe
/// ("fail" -1753, "missing" -1728, "denied" -1743, "hang" a timeout, anything else finishes).
///
/// Manual check (needs the user's real Shortcuts, not automatable): on the Personal build set
/// the start Shortcut to a real one, press Test in Settings > Live and allow the Automation
/// prompt once, then start a gig; the row ticks only after the Shortcut finished, Shortcuts
/// does not come to the front, and a failing or missing Shortcut shows its failure.
final class SegueGigModeE2ETests: XCTestCase {
    var library: LiveLibrary?
    var app: XCUIApplication?

    override func setUpWithError() throws {
        continueAfterFailure = false
        library = try LiveLibrary()
    }

    override func tearDownWithError() throws {
        E2E.terminate(app)
        library?.remove()
    }

    // MARK: 1. Off by default

    @MainActor
    func testGigModeShortcutsAreOffByDefault() throws {
        let library = try XCTUnwrap(library)
        let app = launch(library)
        openLiveSettings(app)
        for id in [GigAXID.settingsStartShortcut, GigAXID.settingsEndShortcut] {
            let field = app.textFields[id].firstMatch
            XCTAssertTrue(field.appears(timeout: 10))
            XCTAssertEqual(field.value as? String ?? "", "", "\(id) has a stored value")
        }
        screenshot(app, "settings-off-by-default")
        app.typeKey("w", modifierFlags: .command, in: app)

        openChecklist(app)
        XCTAssertFalse(focusRow(app).exists, "an unconfigured checklist shows the Focus row")
        XCTAssertTrue(element(app, LiveAXID.checklistRow).exists, "the other rows stay")
        screenshot(app, "checklist-without-focus")
        startFromChecklist(app)
        XCTAssertEqual(library.shortcutsRun(), [])
        endShow(app)
        // Nothing may run late: give a stray run the time a real one needs.
        XCTAssertFalse(waitFor(timeout: 1) { !library.shortcutsRun().isEmpty })
    }

    // MARK: 2. Set up through the real UI

    @MainActor
    func testShortcutsSetInSettingsRunAtStartAndEnd() throws {
        let library = try XCTUnwrap(library)
        let app = launch(library)
        openLiveSettings(app)
        type("Gig Mode On", into: GigAXID.settingsStartShortcut, app)
        type("Gig Mode Off", into: GigAXID.settingsEndShortcut, app)
        screenshot(app, "settings-configured")
        app.typeKey("w", modifierFlags: .command, in: app)

        openChecklist(app)
        let row = focusRow(app)
        XCTAssertTrue(row.appears(timeout: 10))
        XCTAssertTrue(waitFor { library.shortcutsRun() == ["Gig Mode On"] })
        XCTAssertTrue(waitForFocus(app, "done"), "an observed completion ticks the row")
        XCTAssertFalse(element(app, GigAXID.checklistFocusDone).exists)
        screenshot(app, "checklist-focus-ran")
        startFromChecklist(app)
        endShow(app)
        XCTAssertTrue(waitFor { library.shortcutsRun() == ["Gig Mode On", "Gig Mode Off"] })
    }

    // MARK: 3. A failure stays unticked; Done is the fallback

    @MainActor
    func testFailedShortcutStaysUntickedUntilDone() throws {
        let library = try XCTUnwrap(library)
        let app = launch(library, extra: ["-SegueStartShortcut", "fail-gig"])
        openChecklist(app)
        let row = focusRow(app)
        XCTAssertTrue(row.appears(timeout: 10))
        XCTAssertTrue(waitForFocus(app, "not done"))
        XCTAssertTrue(detail(row, containing: "failed").appears(timeout: 5))
        XCTAssertTrue(element(app, GigAXID.checklistFocusRetry).appears(timeout: 5))
        let done = element(app, GigAXID.checklistFocusDone)
        XCTAssertTrue(done.appears(timeout: 5))
        screenshot(app, "checklist-focus-failed")

        done.click(in: app)
        XCTAssertTrue(waitForFocus(app, "done"))
        element(app, GigAXID.checklistFocusDone).click(in: app)
        XCTAssertTrue(waitForFocus(app, "not done"))

        // Retry runs the start Shortcut again (it fails again).
        element(app, GigAXID.checklistFocusRetry).click(in: app)
        XCTAssertTrue(waitFor { library.shortcutsRun() == ["fail-gig", "fail-gig"] })
        XCTAssertTrue(waitForFocus(app, "not done"))
    }

    // MARK: 4. A timeout stays unticked

    @MainActor
    func testUnconfirmedShortcutTimesOutUnticked() throws {
        let library = try XCTUnwrap(library)
        // The live clock runs 10x faster: the 30 s confirmation timeout passes in 3 s, long
        // enough to see the pending state first.
        let app = launch(
            library,
            extra: ["-SegueStartShortcut", "hang-gig", "-SegueLiveTimeScale", "10"],
        )
        openChecklist(app)
        let row = focusRow(app)
        XCTAssertTrue(row.appears(timeout: 10))
        XCTAssertTrue(detail(row, containing: "Running").appears(timeout: 5))
        XCTAssertTrue(waitForFocus(app, "not done"))
        XCTAssertFalse(element(app, GigAXID.checklistFocusDone).exists)

        XCTAssertTrue(detail(row, containing: "confirm it finished").appears(timeout: 10))
        XCTAssertTrue(waitForFocus(app, "not done"))
        screenshot(app, "checklist-focus-unknown")
        let done = element(app, GigAXID.checklistFocusDone)
        XCTAssertTrue(done.appears(timeout: 5))
        done.click(in: app)
        XCTAssertTrue(waitForFocus(app, "done"))
    }

    // MARK: 5. Observed completion ticks (Path SE)

    @MainActor
    func testObservedCompletionTicksWithoutDone() throws {
        let library = try XCTUnwrap(library)
        let app = launch(library, extra: ["-SegueStartShortcut", "Gig Mode On"])
        openChecklist(app)
        let row = focusRow(app)
        XCTAssertTrue(row.appears(timeout: 10))
        XCTAssertTrue(waitForFocus(app, "done"))
        XCTAssertTrue(detail(row, containing: "“Gig Mode On” ran.").appears(timeout: 5))
        XCTAssertFalse(element(app, GigAXID.checklistFocusDone).exists)
        XCTAssertFalse(element(app, GigAXID.checklistFocusRetry).exists)
        XCTAssertEqual(library.shortcutsRun(), ["Gig Mode On"])
    }

    // MARK: 6. Not set up (-1728) and not permitted (-1743)

    @MainActor
    func testMissingShortcutFailsAsNotSetUp() throws {
        let library = try XCTUnwrap(library)
        let app = launch(library, extra: ["-SegueStartShortcut", "missing-gig"])
        openChecklist(app)
        let row = focusRow(app)
        XCTAssertTrue(row.appears(timeout: 10))
        XCTAssertTrue(waitForFocus(app, "not done"))
        let detail = detail(row, containing: "no Shortcut with this name")
        XCTAssertTrue(detail.appears(timeout: 5))
        XCTAssertTrue(element(app, GigAXID.checklistFocusRetry).appears(timeout: 5))
        XCTAssertTrue(element(app, GigAXID.checklistFocusDone).appears(timeout: 5))
        screenshot(app, "checklist-focus-missing")
    }

    @MainActor
    func testDeniedAutomationPointsToSystemSettings() throws {
        let library = try XCTUnwrap(library)
        let workspaceLog = library.root.appending(path: "workspace.log")
        let app = launch(
            library,
            extra: [
                "-SegueStartShortcut", "denied-gig",
                "-SegueWorkspaceLog", workspaceLog.path(percentEncoded: false),
            ],
        )
        openLiveSettings(app)
        app.buttons["Test"].firstMatch.click(in: app)
        let result = element(app, GigAXID.settingsShortcutTestResult)
        XCTAssertTrue(waitFor { result.exists && self.text(result).contains("System Settings") })
        let open = element(app, GigAXID.settingsAutomationSettings)
        XCTAssertTrue(open.appears(timeout: 5))
        screenshot(app, "settings-automation-denied")
        open.click(in: app)
        XCTAssertTrue(waitFor {
            let log = (try? String(contentsOf: workspaceLog, encoding: .utf8)) ?? ""
            return log.contains("Privacy_Automation")
        })
        app.typeKey("w", modifierFlags: .command, in: app)

        openChecklist(app)
        let row = focusRow(app)
        XCTAssertTrue(row.appears(timeout: 10))
        XCTAssertTrue(waitForFocus(app, "not done"))
        XCTAssertTrue(detail(row, containing: "Privacy & Security").appears(timeout: 5))
        XCTAssertTrue(element(app, GigAXID.checklistFocusDone).appears(timeout: 5))
        screenshot(app, "checklist-focus-denied")
        XCTAssertTrue(waitFor { library.shortcutsRun() == ["denied-gig", "denied-gig"] })
    }
}

// MARK: - Steps

@MainActor
extension SegueGigModeE2ETests {
    func launch(_ library: LiveLibrary, extra: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        self.app = app
        E2E.launch(app, arguments: library.arguments(extra: extra))
        return app
    }

    /// Setlists > the Friday setlist > Start Show, up to the checklist.
    func openChecklist(_ app: XCUIApplication) {
        element(app, LiveAXID.sidebarSetlists).click(in: app)
        let row = element(app, LiveAXID.setlistRow)
        XCTAssertTrue(row.appears(timeout: 10))
        row.click(in: app)
        let button = element(app, LiveAXID.setlistStartShow)
        XCTAssertTrue(button.appears(timeout: 10))
        button.click(in: app)
        XCTAssertTrue(element(app, LiveAXID.checklistStart).appears(timeout: 10))
    }

    func startFromChecklist(_ app: XCUIApplication) {
        element(app, LiveAXID.checklistStart).click(in: app)
        XCTAssertTrue(app.staticTexts[LiveAXID.liveTitle].appears(timeout: 10))
    }

    /// Cmd-. then Return in the confirmation; the stage goes away.
    func endShow(_ app: XCUIApplication) {
        app.typeKey(".", modifierFlags: .command, in: app)
        XCTAssertTrue(element(app, LiveAXID.liveEndDialog).appears(timeout: 5))
        app.typeKey(.return, modifierFlags: [], in: app)
        XCTAssertTrue(app.staticTexts[LiveAXID.liveTitle].disappears(timeout: 10))
    }

    /// Settings (Cmd-,) on the Live pane.
    func openLiveSettings(_ app: XCUIApplication) {
        app.typeKey(",", modifierFlags: .command, in: app)
        // Settings reopens on the last tab it showed: pick Live.
        let tab = app.toolbars.buttons["Live"].firstMatch
        XCTAssertTrue(tab.appears(timeout: 10))
        tab.click(in: app)
        XCTAssertTrue(
            app.textFields[GigAXID.settingsStartShortcut].firstMatch.appears(timeout: 10),
        )
    }

    func type(_ text: String, into id: String, _ app: XCUIApplication) {
        let field = app.textFields[id].firstMatch
        XCTAssertTrue(field.appears(timeout: 10))
        field.click(in: app)
        field.typeText(text)
        XCTAssertTrue(waitForValue(field, text), "\(id) did not take “\(text)”")
    }

    /// The checklist's "Focus on" row.
    func focusRow(_ app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(
            NSPredicate(
                format: "identifier == %@ AND label == %@",
                LiveAXID.checklistRow,
                "Focus on",
            ),
        ).firstMatch
    }

    /// Waits until the Focus row's E2E state marker reads `state` ("done" / "not done").
    func waitForFocus(_ app: XCUIApplication, _ state: String) -> Bool {
        let marker = app.descendants(matching: .any).matching(
            NSPredicate(
                format: "identifier == %@ AND label == %@",
                GigAXID.checklistRowState,
                "Focus on: \(state)",
            ),
        ).firstMatch
        return marker.appears(timeout: 10)
    }

    func detail(_ row: XCUIElement, containing text: String) -> XCUIElement {
        row.descendants(matching: .staticText).matching(
            NSPredicate(format: "label CONTAINS %@ OR value CONTAINS %@", text, text),
        ).firstMatch
    }

    func element(_ app: XCUIApplication, _ identifier: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    /// A static text's label or value.
    func text(_ element: XCUIElement) -> String {
        [element.label, element.value as? String ?? ""].joined(separator: " ")
    }

    func waitForValue(_ element: XCUIElement, _ value: String) -> Bool {
        waitFor { element.exists && element.value as? String == value }
    }

    /// Polls `condition` fast (a predicate over a computed value is not re-evaluated
    /// reliably for SwiftUI elements).
    func waitFor(timeout: TimeInterval = 10, _ condition: () -> Bool) -> Bool {
        E2E.waitUntil(timeout: timeout, condition)
    }

    func screenshot(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "gig-mode-\(name)"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}

/// Identifiers this suite needs beyond `LiveAXID` (mirrors `AccessibilityID` in SegueUI).
enum GigAXID {
    static let settingsStartShortcut = "segue.settings.live.startShortcut"
    static let settingsEndShortcut = "segue.settings.live.endShortcut"
    static let checklistRowState = "segue.live.checklist.row.state"
    static let checklistFocusDone = "segue.live.checklist.focus.done"
    static let checklistFocusRetry = "segue.live.checklist.focus.retry"
    static let settingsShortcutTestResult = "segue.settings.live.shortcutTestResult"
    static let settingsAutomationSettings = "segue.settings.live.automationSettings"
}
