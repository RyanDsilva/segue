import XCTest

/// TipKit tips through the real UI (WS2b 4.4). `-SegueTips show` applies the real rules with
/// no daily limit on a fresh tip datastore: the search tip appears on a library of 5 or more
/// songs and the first search retires it; the stage never shows a tip; a test run without
/// the flag shows none.
final class SegueTipsE2ETests: XCTestCase {
    private var library: LiveLibrary?
    private var app: XCUIApplication?

    override func setUpWithError() throws {
        continueAfterFailure = false
        library = try LiveLibrary()
    }

    override func tearDownWithError() throws {
        E2E.terminate(app)
        library?.remove()
    }

    private static let searchTip = "Search by any line you remember"

    @MainActor
    func testSearchTipAndNoTipsOnStage() throws {
        let library = try XCTUnwrap(library)
        let app = launch(library.arguments(extra: ["-SegueTips", "show"]))
        let tip = tipText(app, Self.searchTip)
        XCTAssertTrue(tip.appears(timeout: 10), "no search tip on a 12-song library")
        attach(app, "tip-search")

        // The first search retires it.
        let search = app.descendants(matching: .any)
            .matching(identifier: "segue.library.search").firstMatch
        // The first click closes the popover; the second focuses the field.
        search.click(in: app)
        E2E.waitUntil(timeout: 0.5) { false }
        search.click(in: app)
        search.typeText("harbor", in: app)
        XCTAssertTrue(tip.disappears(timeout: 10), "the search tip stayed after a search")

        // On stage: no tip of any kind.
        app.typeKey("a", modifierFlags: .command, in: app)
        app.typeKey(.delete, modifierFlags: [], in: app)
        app.descendants(matching: .any).matching(identifier: LiveAXID.sidebarSetlists)
            .firstMatch.click(in: app)
        let row = app.descendants(matching: .any).matching(identifier: LiveAXID.setlistRow)
            .firstMatch
        XCTAssertTrue(row.appears(timeout: 10))
        row.click(in: app)
        let start = app.descendants(matching: .any)
            .matching(identifier: LiveAXID.setlistStartShow).firstMatch
        XCTAssertTrue(start.appears(timeout: 10))
        // The Start Show tip sits on the button until the first show: its popover takes the
        // first click.
        XCTAssertTrue(tipText(app, "Press ? on stage").appears(timeout: 5), "no Start Show tip")
        attach(app, "tip-start-show")
        let checklistStart = app.descendants(matching: .any)
            .matching(identifier: LiveAXID.checklistStart).firstMatch
        let liveTitle = app.staticTexts[LiveAXID.liveTitle]
        for _ in 0 ..< 3 where !checklistStart.exists && !liveTitle.exists {
            start.click(in: app)
            E2E.waitUntil(timeout: 2) { checklistStart.exists || liveTitle.exists }
        }
        if checklistStart.exists {
            checklistStart.click(in: app)
        }
        XCTAssertTrue(app.staticTexts[LiveAXID.liveTitle].appears(timeout: 10))
        let stage = app.windows.containing(.staticText, identifier: LiveAXID.liveTitle).firstMatch
        XCTAssertFalse(E2E.waitUntil(timeout: 2) { self.anyTip(stage) }, "a tip on stage")
        XCTAssertFalse(
            tipText(app, "set up Gig Mode Shortcuts").exists,
            "a tip in the main window while performing",
        )
        app.terminate()

        // A test run without the flag: no tips anywhere.
        let quiet = launch(library.arguments(reset: false))
        XCTAssertTrue(
            quiet.descendants(matching: .any).matching(identifier: LiveAXID.sidebarLibrary)
                .firstMatch.appears(timeout: 15),
        )
        XCTAssertFalse(E2E.waitUntil(timeout: 2) { self.anyTip(quiet) }, "tips in a test run")
    }
}

@MainActor
extension SegueTipsE2ETests {
    private func launch(_ arguments: [String]) -> XCUIApplication {
        let app = XCUIApplication()
        self.app = app
        E2E.launch(app, arguments: arguments)
        return app
    }

    private func tipText(_ root: XCUIElement, _ text: String) -> XCUIElement {
        // Static texts only: a value predicate over every element type times out.
        root.staticTexts
            .matching(NSPredicate(
                format: "label CONTAINS %@ OR value CONTAINS %@",
                argumentArray: [text, text],
            ))
            .firstMatch
    }

    /// Any of the five tips' messages on screen.
    private func anyTip(_ root: XCUIElement) -> Bool {
        [
            Self.searchTip, "without touching the file", "Drag a chord onto another syllable",
            "Press ? on stage", "set up Gig Mode Shortcuts",
        ].contains { tipText(root, $0).exists }
    }

    private func attach(_ app: XCUIApplication, _ name: String) {
        E2E.waitUntil(timeout: 0.4) { false }
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
