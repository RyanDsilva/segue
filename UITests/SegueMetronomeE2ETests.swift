import XCTest

/// The stage metronome through the real UI (P3-14, R90, R108, R118), on a fresh Welcome
/// library: rehearse the Welcome Set with the checklist's Metronome switch on, see the pulse
/// in the stage corner, press M and it hides, press M and it is back.
final class SegueMetronomeE2ETests: XCTestCase {
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
    func testRehearsalWithTheMetronomeOnAndMToggles() throws {
        let library = try XCTUnwrap(library)
        let app = XCUIApplication()
        self.app = app
        E2E.launch(app, arguments: library.arguments(["-SegueSeedWelcome", "YES"]))

        element(app, MetronomeAXID.sidebarSetlists).click(in: app)
        let row = element(app, MetronomeAXID.setlistRow)
        row.click(in: app)
        element(app, MetronomeAXID.rehearse).click(in: app)

        // The checklist: Metronome off by default, the Click switch offered (and off).
        let metronome = element(app, MetronomeAXID.checklistMetronome)
        let click = element(app, MetronomeAXID.checklistClick)
        XCTAssertEqual(Self.isOn(metronome), false)
        XCTAssertEqual(Self.isOn(click), false)
        toggle(metronome)
        XCTAssertTrue(E2E.waitUntil { Self.isOn(metronome) == true }, "the switch stayed off")
        attach(app, "metronome-checklist")
        element(app, MetronomeAXID.checklistStart).click(in: app)

        let title = app.staticTexts[MetronomeAXID.liveTitle]
        XCTAssertTrue(title.appears(timeout: 10))
        let pulse = app.descendants(matching: .any).matching(identifier: MetronomeAXID.pulse)
            .firstMatch
        XCTAssertTrue(pulse.appears(timeout: 5), "no metronome on stage")
        XCTAssertEqual(pulse.label, "Metronome, 96 beats per minute")
        attach(app, "metronome-stage")

        app.typeKey("m", modifierFlags: [], in: app)
        XCTAssertTrue(pulse.disappears(timeout: 5), "M did not hide the metronome")
        app.typeKey("m", modifierFlags: [], in: app)
        XCTAssertTrue(pulse.appears(timeout: 5), "M did not bring the metronome back")

        app.typeKey(".", modifierFlags: .command, in: app)
        XCTAssertTrue(element(app, MetronomeAXID.liveEndDialog).appears(timeout: 5))
        app.typeKey(.return, modifierFlags: [], in: app)
        XCTAssertTrue(title.disappears(timeout: 10))
    }

    // MARK: - Helpers

    /// A switch's state: its value is 1 or 0 (as a number or a string).
    private static func isOn(_ element: XCUIElement) -> Bool? {
        switch element.value {
        case let number as Int: number == 1
        case let string as String: string == "1"
        default: nil
        }
    }

    /// Clicks the switch itself: it sits at the row's trailing edge (14pt padding).
    @MainActor
    private func toggle(_ row: XCUIElement) {
        if row.elementType == .switch || row.elementType == .checkBox {
            row.click()
            return
        }
        let control = row.descendants(matching: .switch).firstMatch
        if control.exists {
            control.click()
        } else {
            row.coordinate(withNormalizedOffset: CGVector(dx: 1, dy: 0.5))
                .withOffset(CGVector(dx: -30, dy: 0)).click()
        }
    }

    @MainActor
    private func element(_ app: XCUIApplication, _ identifier: String) -> XCUIElement {
        let element = app.descendants(matching: .any).matching(identifier: identifier).firstMatch
        XCTAssertTrue(element.appears(timeout: 10), "no \(identifier)")
        return element
    }

    @MainActor
    private func attach(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}

/// Identifiers the metronome E2E uses (mirrors `AccessibilityID` in SegueUI).
enum MetronomeAXID {
    static let sidebarSetlists = "segue.sidebar.setlists"
    static let setlistRow = "segue.setlists.row"
    static let rehearse = "segue.setlist.rehearse"
    static let checklistStart = "segue.live.checklist.start"
    static let checklistMetronome = "segue.live.checklist.metronome"
    static let checklistClick = "segue.live.checklist.metronomeClick"
    static let liveTitle = "segue.live.title"
    static let liveEndDialog = "segue.live.endDialog"
    static let pulse = "segue.live.metronome"
}
