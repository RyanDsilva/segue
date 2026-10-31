import XCTest

/// The stage's `?` key help (WS2a 6.3 test 17) and page-turner pedals (R45), on the live
/// fixture library (Long Way Home is long enough to scroll; Copper Sky fits).
@MainActor
extension SegueLiveE2ETests {
    func testStageKeysOverlay() throws {
        let library = try XCTUnwrap(library)
        let app = launch(library)
        startShow(app, rehearse: false)
        let title = app.staticTexts[LiveAXID.liveTitle]
        XCTAssertTrue(waitForValue(title, "Harbor Lights"))

        key(app, "?")
        let overlay = element(app, LiveAXID.keysOverlay)
        XCTAssertTrue(overlay.appears(timeout: 5), "? did not show the key help")
        let rows = app.descendants(matching: .any).matching(identifier: LiveAXID.keysOverlayRow)
        // Every `LiveCommand` row once: 22, plus the metronome's M and Shift-M (P3-14), minus
        // the retired collapse toggle (R147), plus 1-9 jumps and L loop (R148), B bass notes
        // (R152), P play along (P8-6 10.4) and T fills as tab (P8-7 14.2).
        XCTAssertEqual(rows.count, 28, "every command once")
        screenshot(app, "keys-overlay")
        key(app, .escape)
        XCTAssertTrue(overlay.disappears(timeout: 5), "Esc did not close it")

        // Any other bound key closes it and still runs.
        key(app, "?")
        XCTAssertTrue(overlay.appears(timeout: 5))
        key(app, .rightArrow)
        XCTAssertTrue(overlay.disappears(timeout: 5))
        XCTAssertTrue(waitForValue(title, "Paper Boats"))
    }

    func testStageKeysOverlayFollowsBindings() throws {
        let library = try XCTUnwrap(library)
        let bindings = library.root.appending(path: "bindings.json")
        try Data(
            #"{"schemaVersion": 1, "bindings": [{"trigger": {"key": "n"}, "command": "next"}]}"#
                .utf8,
        ).write(to: bindings)
        let app = launch(
            library,
            extra: ["-SegueBindingsPath", bindings.path(percentEncoded: false)],
        )
        startShow(app, rehearse: false)

        key(app, "?")
        let next = app.descendants(matching: .any).matching(identifier: LiveAXID.keysOverlayRow)
            .matching(NSPredicate(format: "value BEGINSWITH %@", "Next Song:")).firstMatch
        let labels = { app.descendants(matching: .any).matching(identifier: LiveAXID.keysOverlayRow)
            .allElementsBoundByIndex.map { $0.value as? String ?? "" }
        }
        XCTAssertTrue(next.appears(timeout: 5), "\(labels())")
        let spoken = next.value as? String ?? ""
        XCTAssertTrue(spoken.hasSuffix(", N"), spoken)
        screenshot(app, "keys-overlay-custom")
    }

    func testPageTurnerCrossesSongs() throws {
        let library = try XCTUnwrap(library)
        let app = launch(library)
        startShow(app, rehearse: false)
        let title = app.staticTexts[LiveAXID.liveTitle]
        for _ in 0 ..< 4 {
            key(app, .rightArrow)
        }
        XCTAssertTrue(waitForValue(title, "Long Way Home"))
        let body = element(app, LiveAXID.liveBody)

        // Page Down pages through the long song; only once it is at its bottom does the
        // next Page Down move on, to the next song at its top.
        var presses = 0
        var lastPosition = 0.0
        while title.value as? String == "Long Way Home", presses < 60 {
            lastPosition = scrollPosition(body) ?? 0
            key(app, .pageDown)
            presses += 1
            // Each press scrolls this song or moves on to the next one. A last page stop
            // within a rounding step of the bottom moves nothing visible ("scroll 1.00"
            // either way), so this waits for a change without asserting one; the loop
            // bound and the checks below catch a Page Down that never moves on.
            let before = lastPosition
            E2E.waitUntil(timeout: 1) {
                title.value as? String != "Long Way Home"
                    || (self.scrollPosition(body) ?? before) != before
            }
        }
        XCTAssertTrue(waitForValue(title, "Copper Sky"))
        XCTAssertGreaterThan(presses, 2, "the song should take several pages")
        XCTAssertGreaterThan(lastPosition, 0.99, "it moved on before the bottom")
        XCTAssertTrue(waitFor(body) { (self.scrollPosition($0) ?? 1) < 0.01 })
        screenshot(app, "page-turner-next")

        // Page Up at the top goes back to the previous song, at its bottom.
        key(app, .pageUp)
        XCTAssertTrue(waitForValue(title, "Long Way Home"))
        XCTAssertTrue(waitFor(body) { (self.scrollPosition($0) ?? 0) >= 0.999 })
        screenshot(app, "page-turner-landed")
        // Page Up from the bottom scrolls up within the song (the last page stop can sit
        // within a rounding step of the bottom, so allow a couple of pages).
        var ups = 0
        while (scrollPosition(body) ?? 0) > 0.95, ups < 3 {
            let before = scrollPosition(body) ?? 0
            key(app, .pageUp)
            ups += 1
            // As above: a stop within a rounding step shows no change, so no assertion here.
            _ = waitFor(body, timeout: 1) { (self.scrollPosition($0) ?? before) < before }
        }
        XCTAssertLessThan(scrollPosition(body) ?? 1, 0.95, body.label)
        XCTAssertEqual(title.value as? String, "Long Way Home")
    }
}
