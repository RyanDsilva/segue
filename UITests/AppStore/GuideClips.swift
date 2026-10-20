import AppKit
import XCTest

/// The user guide's how-to clips (WS6 section 6), each a paced storyboard that
/// `make docs-clips` records with `screencapture -v` around one test (dark appearance). The
/// holds are deliberate: pacing is the point. Never run by `make e2e` or the gate.
final class GuideClips: GuideShotCase {
    /// paste-a-song: copy, Option-Command-V, the review, Command-Return.
    @MainActor
    func testPasteASong() {
        let app = launch()
        _ = element(app, GuideAXID.songRow)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(GuideFixtures.chordSitePaste, forType: .string)
        mark("clip-start")
        hold(1.5)
        app.typeKey("v", modifierFlags: [.command, .option], in: app)
        _ = element(app, GuideAXID.pasteSheet)
        // The recorded AI pass settles, then a beat to read the marks.
        let refining = app.descendants(matching: .any)[GuideAXID.pasteRefining]
        XCTAssertTrue(refining.disappears(timeout: 20))
        _ = aiSectionLabel(app)
        hold(3)
        app.typeKey(.return, modifierFlags: .command, in: app)
        hold(2.5)
        mark("clip-end")
    }

    /// build-a-set: tick two songs in Pick (the total grows), Command-2, move a song down
    /// with Option-Down, Insert Break after it.
    @MainActor
    func testBuildASet() {
        let app = launch()
        openSetlist(app, "Welcome Set")
        app.typeKey("1", modifierFlags: .command, in: app)
        let rows = app.descendants(matching: .any).matching(identifier: GuideAXID.builderLibraryRow)
        func row(_ title: String) -> XCUIElement {
            rows.matching(NSPredicate(format: "label BEGINSWITH %@", title)).firstMatch
        }
        XCTAssertTrue(row("Lanterns on Pier Nine").appears(timeout: 10))
        mark("clip-start")
        hold(1)
        row("Lanterns on Pier Nine").click(in: app)
        hold(1)
        row("Last Tram to Wexley").click(in: app)
        hold(1.5)
        app.typeKey("2", modifierFlags: .command, in: app)
        hold(1.2)
        let kitaabon = app.staticTexts.matching(identifier: GuideAXID.entryTitle)
            .matching(NSPredicate(
                format: "label CONTAINS %@ OR value CONTAINS %@",
                "Kitaabon",
                "Kitaabon",
            )).firstMatch
        XCTAssertTrue(kitaabon.appears(timeout: 10))
        XCUIElement.perform(withKeyModifiers: .command) { kitaabon.click() }
        hold(1)
        app.typeKey(.downArrow, modifierFlags: .option, in: app)
        hold(1.2)
        app.typeKey("b", modifierFlags: [.command, .shift], in: app)
        hold(2.5)
        mark("clip-end")
    }

    /// go-on-stage: Start Show, the checklist, the stage, the next song, a request.
    @MainActor
    func testGoOnStage() {
        let app = launch()
        openSetlist(app, "JamFest Opener")
        mark("clip-start")
        hold(1)
        element(app, GuideAXID.setlistStartShow).click(in: app)
        hold(2)
        element(app, GuideAXID.checklistStart).click(in: app)
        XCTAssertTrue(app.staticTexts[GuideAXID.liveTitle].appears(timeout: 10))
        hold(2.5)
        app.typeKey(.rightArrow, modifierFlags: [], in: app)
        hold(2.5)
        app.typeKey("k", modifierFlags: .command, in: app)
        let field = app.textFields[GuideAXID.liveSearchField]
        XCTAssertTrue(field.appears(timeout: 10))
        hold(0.6)
        field.typeText("kitabon", in: app)
        _ = element(app, GuideAXID.liveSearchResult)
        hold(1.2)
        app.typeKey(.return, modifierFlags: [], in: app)
        hold(2.5)
        mark("clip-end")
        app.typeKey(".", modifierFlags: .command, in: app)
        app.typeKey(.return, modifierFlags: [], in: app)
    }
}
