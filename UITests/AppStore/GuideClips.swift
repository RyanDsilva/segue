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
        hold(4)
        app.typeKey(.return, modifierFlags: .command, in: app)
        hold(2.5)
        mark("clip-end")
    }

    /// build-a-set: Pick with Space, Command-2, Option-Down, Insert Break.
    @MainActor
    func testBuildASet() {
        let app = launch()
        element(app, GuideAXID.setlistRow).click(in: app)
        mark("clip-start")
        hold(1)
        app.typeKey("1", modifierFlags: .command, in: app)
        hold(1.5)
        app.typeKey("2", modifierFlags: .command, in: app)
        hold(1)
        app.typeKey(.downArrow, modifierFlags: .option, in: app)
        hold(1.2)
        app.typeKey("b", modifierFlags: [.command, .shift], in: app)
        hold(2.5)
        mark("clip-end")
    }

    /// go-on-stage: Start Show, the checklist, the stage, the next song.
    @MainActor
    func testGoOnStage() {
        let app = launch()
        element(app, GuideAXID.setlistRow).click(in: app)
        mark("clip-start")
        hold(1)
        element(app, GuideAXID.setlistStartShow).click(in: app)
        hold(2)
        element(app, GuideAXID.checklistStart).click(in: app)
        XCTAssertTrue(app.staticTexts[GuideAXID.liveTitle].appears(timeout: 10))
        hold(2.5)
        app.typeKey(.rightArrow, modifierFlags: [], in: app)
        hold(2.5)
        app.typeKey(.pageDown, modifierFlags: [], in: app)
        hold(2)
        mark("clip-end")
        app.typeKey(".", modifierFlags: .command, in: app)
        app.typeKey(.return, modifierFlags: [], in: app)
    }
}
