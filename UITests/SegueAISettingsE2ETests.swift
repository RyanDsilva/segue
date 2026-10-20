import XCTest

/// Settings > AI through the real UI (P3-3, spec 14): with no model the card shows the size and
/// the license before anything else, nothing downloads without a click (the test launch's model
/// store is scripted and never touches the network), a click walks to Downloaded, Delete asks
/// first and removes it, and the Use AI toggle switches. The pane's states in light and dark
/// are `AISettingsTests` (in process).
final class SegueAISettingsE2ETests: XCTestCase {
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
    func testModelCardDownloadsOnlyOnAClick() throws {
        let library = try XCTUnwrap(library)
        let app = XCUIApplication()
        self.app = app
        E2E.launch(app, arguments: library.arguments([
            "-SegueSeedWelcome", "YES", "-SegueAppearance", "dark",
        ]))
        XCTAssertTrue(element(app, AISettingsAXID.sidebarLibrary).appears(timeout: 15))

        app.typeKey(",", modifierFlags: .command, in: app)
        XCTAssertTrue(app.toolbars.buttons["AI"].firstMatch.appears(timeout: 10), "no AI pane")
        app.toolbars.buttons["AI"].firstMatch.click(in: app)
        XCTAssertTrue(app.windows["AI"].firstMatch.appears(timeout: 5))

        // Size, memory and license are shown first; the state stays Not downloaded.
        let size = element(app, AISettingsAXID.size)
        XCTAssertTrue(size.appears(timeout: 10), "no model card")
        XCTAssertEqual(text(size), "2.27 GB")
        XCTAssertTrue(text(element(app, AISettingsAXID.memory)).contains("3 GB"))
        XCTAssertTrue(element(app, AISettingsAXID.license).exists, "no license link")
        let state = element(app, AISettingsAXID.state)
        XCTAssertEqual(text(state), "Not downloaded")
        attach(app, "settings-ai-no-model-dark")
        E2E.waitUntil(timeout: 2) { false }
        XCTAssertEqual(text(state), "Not downloaded", "a download started without a click")

        // One click: progress, then Downloaded.
        element(app, AISettingsAXID.download).click(in: app)
        XCTAssertTrue(
            E2E.waitUntil(timeout: 10) { self.text(state) == "Downloaded" },
            "state: \(text(state))",
        )
        attach(app, "settings-ai-installed-dark")

        // Delete asks first, then removes it.
        element(app, AISettingsAXID.delete).click(in: app)
        let confirm = element(app, AISettingsAXID.deleteConfirm)
        XCTAssertTrue(confirm.appears(timeout: 5), "no delete confirmation")
        confirm.click(in: app)
        XCTAssertTrue(E2E.waitUntil(timeout: 5) { self.text(state) == "Not downloaded" })

        // The one toggle.
        let toggle = element(app, AISettingsAXID.useAI)
        XCTAssertEqual(toggle.value as? Int, 1, "Use AI is not on by default")
        toggle.click(in: app)
        XCTAssertTrue(E2E.waitUntil { (toggle.value as? Int) == 0 })
        toggle.click(in: app)
        XCTAssertTrue(E2E.waitUntil { (toggle.value as? Int) == 1 })
    }

    @MainActor
    private func element(_ app: XCUIApplication, _ identifier: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    @MainActor
    private func text(_ element: XCUIElement) -> String {
        [element.value as? String, element.label].compactMap(\.self).first { !$0.isEmpty } ?? ""
    }

    @MainActor
    private func attach(_ app: XCUIApplication, _ name: String) {
        E2E.waitUntil(timeout: 0.4) { false }
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}

/// Identifiers the AI settings E2E uses (mirrors `AccessibilityID+AISettings` in SegueUI).
enum AISettingsAXID {
    static let sidebarLibrary = "segue.sidebar.library"
    static let useAI = "segue.settings.ai.useAI"
    static let size = "segue.settings.ai.model.size"
    static let memory = "segue.settings.ai.model.memory"
    static let license = "segue.settings.ai.model.license"
    static let state = "segue.settings.ai.model.state"
    static let download = "segue.settings.ai.model.download"
    static let delete = "segue.settings.ai.model.delete"
    static let deleteConfirm = "segue.settings.ai.model.delete.confirm"
}
