import AppKit
import XCTest

/// The App Store preview storyboard (docs/release/specs/WS5-store-listing.md 9.2), recorded by
/// `make preview` with `screencapture -v` around this one test: the builder and then the
/// stage in a 1440x810 pt (16:9) window at the top-left of the visible area, keyboard only,
/// dark. The holds are the pacing; `clip-start` / `clip-end` mark the cut. Never run by
/// `make e2e` or the gate.
final class AppStorePreviewTests: StoreShotCase {
    override static var windowSize: CGSize {
        CGSize(width: 1440, height: 810)
    }

    override var appearance: String {
        "dark"
    }

    @MainActor
    func testPreviewStoryboard() {
        let app = launch()
        _ = element(app, GuideAXID.songRow)
        openSetlist(app, "JamFest Opener")
        app.typeKey("2", modifierFlags: .command, in: app)
        _ = element(app, GuideAXID.setlistTotal)
        // The pointer leaves the window before recording starts; the rest is keyboard.
        mainWindow(app).coordinate(withNormalizedOffset: .zero)
            .withOffset(CGVector(dx: -40, dy: -40)).hover()
        hold(1)

        // Each scene-<caption id> marker starts that caption (store/screenshots.json).
        mark("clip-start")
        mark("scene-1-build")
        hold(1.6)
        app.typeKey(.return, modifierFlags: .command, in: app)
        let start = app.descendants(matching: .any)[GuideAXID.checklistStart]
        if start.appears(timeout: 5) {
            hold(0.5)
            app.typeKey(.return, modifierFlags: [], in: app)
        }
        XCTAssertTrue(app.staticTexts[GuideAXID.liveTitle].appears(timeout: 10))
        mark("scene-2-fits")
        // Song 3, Ferry Lights: two columns, fitted to the screen, with Up next.
        app.typeKey(.rightArrow, modifierFlags: [], in: app)
        app.typeKey(.rightArrow, modifierFlags: [], in: app)
        advance(app, to: "Ferry Lights Over Calder Bay")
        hold(4.2)
        mark("scene-3-request")
        queueRequest(app)
        // The request, romanized Hindi.
        app.typeKey("r", modifierFlags: [], in: app)
        mark("scene-4-hindi")
        hold(3.8)
        mark("scene-5-cue")
        app.typeKey("?", modifierFlags: [], in: app)
        hold(1.3)
        app.typeKey(.escape, modifierFlags: [], in: app)
        hold(1)
        mark("clip-end")
        endShow(app)
    }

    /// Quick search on stage: `kitabon` typed at a human pace, queued as a request.
    @MainActor
    func queueRequest(_ app: XCUIApplication) {
        app.typeKey("k", modifierFlags: .command, in: app)
        let field = app.textFields[GuideAXID.liveSearchField]
        XCTAssertTrue(field.appears(timeout: 10))
        hold(0.3)
        for character in "kitabon" {
            field.typeText(String(character))
            hold(0.08)
        }
        _ = element(app, GuideAXID.liveSearchResult)
        hold(1)
        app.typeKey(.return, modifierFlags: .command, in: app)
        let note = app.textFields[GuideAXID.liveSearchNote]
        if note.appears(timeout: 2) {
            app.typeKey(.return, modifierFlags: [], in: app)
        }
        _ = element(app, GuideAXID.liveRequestCount)
        hold(1)
    }
}
