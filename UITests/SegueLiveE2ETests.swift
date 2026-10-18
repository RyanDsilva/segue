import XCTest

/// Live mode E2E (phase 2 spec, E2E 1-9 plus the rehearsal run), driven through the real UI
/// on a freshly seeded temp library each test: the setlist builder's Start Show / Rehearse,
/// the pre-show checklist, the stage keys, the overlays, the gig log and the reorder review.
/// Shortcuts are recorded by the fake runner (`-SegueShortcutLog`), never opened.
final class SegueLiveE2ETests: XCTestCase {
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

    // MARK: E2E 1, 8, 9: Friday gig with a romanized Hindi request and the Shortcut hooks

    @MainActor
    func testFridayGig() throws {
        let library = try XCTUnwrap(library)
        let app = launch(library, extra: LiveLibrary.gigModeShortcuts)
        startShow(app, rehearse: false)
        XCTAssertEqual(library.shortcutsRun(), ["Gig Mode On"])
        let title = app.staticTexts[LiveAXID.liveTitle]
        XCTAssertEqual(title.value as? String, "Harbor Lights")
        XCTAssertEqual(app.staticTexts[LiveAXID.liveUpNext].value as? String, "Paper Boats")
        screenshot(app, "01-stage-first-song")

        // Advance through 3 songs, skip song 4.
        for expected in ["Paper Boats", "Salt Road", "Northern Line"] {
            key(app, .rightArrow)
            XCTAssertTrue(waitForValue(title, expected), "expected \(expected)")
        }
        XCTAssertEqual(app.staticTexts[LiveAXID.livePosition].value as? String, "4 of 10")
        screenshot(app, "02-stage-song-4")
        key(app, "x")
        XCTAssertTrue(waitForValue(title, "Long Way Home"))

        requestPyaar(app)
        playRequestAndFinish(app)
        endShow(app)
        // Shortcut hooks fired at start and end, and live mode kept focus throughout.
        XCTAssertEqual(library.shortcutsRun(), ["Gig Mode On", "Gig Mode Off"])

        // The request was inserted, so the review appears; Discard keeps the setlist as is.
        let before = try Data(contentsOf: library.setlistFile)
        let discard = element(app, LiveAXID.reorderDiscard)
        XCTAssertTrue(discard.waitForExistence(timeout: 10))
        screenshot(app, "07-reorder-review")
        discard.click(in: app)
        XCTAssertTrue(discard.waitForNonExistence(timeout: 5))
        XCTAssertEqual(try Data(contentsOf: library.setlistFile), before)

        // The show file: 10 played in order (the request after song 4's skip), 1 skipped.
        let show = try XCTUnwrap(library.shows().first)
        XCTAssertNotNil(show["endedAt"] as? String)
        XCTAssertEqual(LiveLibrary.items(show, state: "played"), [
            "Harbor Lights", "Paper Boats", "Salt Road", "Pyaar Ki Raah", "Long Way Home",
            "Copper Sky", "Lantern Song", "River Glass", "Night Bus", "Last Light",
        ])
        XCTAssertEqual(LiveLibrary.items(show, state: "skipped"), ["Northern Line"])
        assertGigLog(app)
    }

    // MARK: E2E 2: crash resume

    @MainActor
    func testCrashResumeLandsOnTheSameSongAndScroll() throws {
        let library = try XCTUnwrap(library)
        let app = launch(library)
        startShow(app, rehearse: false)
        let title = app.staticTexts[LiveAXID.liveTitle]
        for _ in 0 ..< 4 {
            key(app, .rightArrow)
        }
        XCTAssertTrue(waitForValue(title, "Long Way Home"))
        key(app, .pageDown)
        key(app, .pageDown)
        let body = element(app, LiveAXID.liveBody)
        XCTAssertTrue(waitFor(body) { (self.scrollPosition($0) ?? 0) > 0 })
        let scrolled = try XCTUnwrap(scrollPosition(body))
        XCTAssertGreaterThan(scrolled, 0.05)
        // Past the 1 s scroll debounce, then kill.
        Thread.sleep(forTimeInterval: 2)
        screenshot(app, "10-before-crash")
        app.terminate()

        let relaunched = XCUIApplication()
        self.app = relaunched
        E2E.launch(relaunched, arguments: library.arguments(reset: false))
        // The alert is a sheet on the main window (not the Touch Bar's "Resume").
        let resumeButton = relaunched.sheets.buttons["Resume"].firstMatch
        XCTAssertTrue(resumeButton.waitForExistence(timeout: 15))
        screenshot(relaunched, "11-resume-prompt")
        resumeButton.click(in: relaunched)
        let resumedTitle = relaunched.staticTexts[LiveAXID.liveTitle]
        XCTAssertTrue(resumedTitle.waitForExistence(timeout: 10))
        XCTAssertEqual(resumedTitle.value as? String, "Long Way Home")
        let resumedBody = element(relaunched, LiveAXID.liveBody)
        XCTAssertTrue(resumedBody.waitForExistence(timeout: 5))
        XCTAssertEqual(try XCTUnwrap(scrollPosition(resumedBody)), scrolled, accuracy: 0.01)
        screenshot(relaunched, "12-resumed")
        endShow(relaunched)
    }

    // MARK: E2E 5, 6: play now and live reorder, saved at the end

    @MainActor
    func testPlayNowAndLiveReorderSavedToTheSetlist() throws {
        let library = try XCTUnwrap(library)
        let app = launch(library)
        startShow(app, rehearse: false)
        let title = app.staticTexts[LiveAXID.liveTitle]
        key(app, .rightArrow)
        key(app, .rightArrow)
        XCTAssertTrue(waitForValue(title, "Salt Road"))

        // Mid-song 3, Cmd-K "Play now" on song 7: it becomes current, song 3 stays pending.
        key(app, "/")
        let field = app.textFields[LiveAXID.liveSearchField]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.typeText("lantern", in: app)
        XCTAssertTrue(element(app, LiveAXID.liveSearchResult).waitForExistence(timeout: 5))
        key(app, .return)
        XCTAssertTrue(waitForValue(title, "Lantern Song"))

        // S: the set order shows song 3 pending; "Next" on song 9 makes it up next.
        key(app, "s")
        XCTAssertTrue(element(app, LiveAXID.liveDrawer).waitForExistence(timeout: 5))
        let rows = app.descendants(matching: .any).matching(identifier: LiveAXID.liveDrawerRow)
        XCTAssertTrue(rows.element(boundBy: 2).label.contains("Salt Road, pending"))
        let nightBus = rows.element(boundBy: 8)
        XCTAssertTrue(nightBus.label.contains("Night Bus"))
        nightBus.descendants(matching: .button).matching(identifier: LiveAXID.liveDrawerPlayNext)
            .firstMatch.click(in: app)
        XCTAssertTrue(waitForValue(app.staticTexts[LiveAXID.liveUpNext], "Night Bus"))
        screenshot(app, "20-set-order-drawer")
        key(app, "s")
        key(app, .rightArrow)
        XCTAssertTrue(waitForValue(title, "Night Bus"))

        endShow(app)
        let save = element(app, LiveAXID.reorderSave)
        XCTAssertTrue(save.waitForExistence(timeout: 10))
        screenshot(app, "21-reorder-review")
        save.click(in: app)
        XCTAssertTrue(save.waitForNonExistence(timeout: 5))
        let order = try library.setlistTitles()
        XCTAssertEqual(order.count, 10)
        XCTAssertLessThan(
            try XCTUnwrap(order.firstIndex(of: "Night Bus")),
            try XCTUnwrap(order.firstIndex(of: "River Glass")),
        )
    }

    // MARK: Rehearsal run, E2E 3 auto-scroll

    @MainActor
    func testRehearsalTimesSongsAndAutoScrollReachesTheEnd() throws {
        let library = try XCTUnwrap(library)
        // Auto-scroll runs 30x faster: a 3:00 song scrolls in about 6 s.
        // The Shortcuts are set, so this proves the rehearsal rule, not the empty default.
        let app = launch(
            library,
            extra: ["-SegueLiveTimeScale", "30"] + LiveLibrary.gigModeShortcuts,
        )
        startShow(app, rehearse: true)
        XCTAssertTrue(element(app, LiveAXID.liveRehearsal).waitForExistence(timeout: 5))
        XCTAssertEqual(library.shortcutsRun(), [], "rehearsals skip the Shortcuts by default")
        let title = app.staticTexts[LiveAXID.liveTitle]
        for _ in 0 ..< 4 {
            key(app, .rightArrow)
        }
        XCTAssertTrue(waitForValue(title, "Long Way Home"))
        let body = element(app, LiveAXID.liveBody)
        XCTAssertTrue(body.waitForExistence(timeout: 5))
        Thread.sleep(forTimeInterval: 1)
        XCTAssertEqual(scrollPosition(body), 0, "auto-scroll never moves before it is started")
        key(app, "a")
        Thread.sleep(forTimeInterval: 3)
        let mid = try XCTUnwrap(scrollPosition(body))
        XCTAssertGreaterThan(mid, 0)
        key(app, "a")
        Thread.sleep(forTimeInterval: 1)
        let paused = try XCTUnwrap(scrollPosition(body))
        Thread.sleep(forTimeInterval: 1.5)
        XCTAssertEqual(try XCTUnwrap(scrollPosition(body)), paused, accuracy: 0.001)
        screenshot(app, "30-rehearsal-paused")
        key(app, "a")
        XCTAssertTrue(waitFor(body, timeout: 20) { self.scrollPosition($0) == 1 })
        XCTAssertTrue(waitForValue(app.staticTexts[LiveAXID.liveScrollStatus], "Scroll at end"))
        key(app, .rightArrow)
        XCTAssertTrue(waitForValue(title, "Copper Sky"))
        endShow(app)

        // No gig log entry and no review; the timings file exists.
        XCTAssertFalse(element(app, LiveAXID.reorderSheet).waitForExistence(timeout: 2))
        XCTAssertTrue(try library.shows().allSatisfy { $0["kind"] as? String != "gig" })
        let timings = library.root.appending(path: "timings", directoryHint: .isDirectory)
        let files = try FileManager.default.contentsOfDirectory(atPath: timings.path)
        XCTAssertTrue(files.contains { $0.hasSuffix(".rehearsal.json") }, "\(files)")
    }

    // MARK: E2E 4, 7: zoom memory and the minimum lyric size

    @MainActor
    func testZoomMemoryAndMinimumLyricSize() throws {
        let library = try XCTUnwrap(library)
        let app = launch(library)
        setMinimumLyricSize(app, to: 30)
        startShow(app, rehearse: false)
        let title = app.staticTexts[LiveAXID.liveTitle]
        let body = element(app, LiveAXID.liveBody)
        XCTAssertTrue(body.waitForExistence(timeout: 5))
        let fitted = try XCTUnwrap(lyricSize(body))
        XCTAssertGreaterThanOrEqual(fitted, 30)

        // Zoom song A; song B is unaffected; A keeps its zoom on return.
        key(app, "=", [.command])
        XCTAssertTrue(waitFor(body) { self.lyricSize($0) != fitted })
        let zoomed = try XCTUnwrap(lyricSize(body))
        key(app, .rightArrow)
        XCTAssertTrue(waitForValue(title, "Paper Boats"))
        key(app, .leftArrow)
        XCTAssertTrue(waitForValue(title, "Harbor Lights"))
        XCTAssertTrue(waitFor(body) { self.lyricSize($0) == zoomed })
        screenshot(app, "40-zoomed")

        // C cycles the song's columns (Auto -> 1 -> 2): a brief indicator, an immediate
        // re-layout, and the choice is remembered for the song.
        key(app, "c")
        let indicator = app.staticTexts[LiveAXID.liveIndicator]
        XCTAssertTrue(waitForValue(indicator, "Columns: 1"))
        XCTAssertTrue(waitFor(body) { $0.label.hasSuffix("columns 1") })
        key(app, "c")
        XCTAssertTrue(waitForValue(indicator, "Columns: 2"))
        XCTAssertTrue(waitFor(body) { $0.label.hasSuffix("columns 2") })
        screenshot(app, "42-columns-2")
        key(app, .rightArrow)
        XCTAssertTrue(waitForValue(title, "Paper Boats"))
        key(app, .leftArrow)
        XCTAssertTrue(waitForValue(title, "Harbor Lights"))
        XCTAssertTrue(waitFor(body) { $0.label.hasSuffix("columns 2") })
        XCTAssertTrue(indicator.waitForNonExistence(timeout: 5), "the indicator goes away")

        // The 56-line song does not fit at 30pt: it renders at 30 and scrolls.
        for _ in 0 ..< 4 {
            key(app, .rightArrow)
        }
        XCTAssertTrue(waitForValue(title, "Long Way Home"))
        XCTAssertTrue(waitFor(body) {
            $0.label.contains("lyric 30 scrolls at minimum")
        })
        screenshot(app, "41-min-font-scrolls")
        endShow(app)
    }
}

// MARK: - Friday gig steps

@MainActor
extension SegueLiveE2ETests {
    /// Cmd-K "pyar": the romanized spelling finds "Pyaar Ki Raah"; Cmd-Return queues it.
    private func requestPyaar(_ app: XCUIApplication) {
        key(app, "k", [.command])
        let field = app.textFields[LiveAXID.liveSearchField]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.typeText("pyar", in: app)
        let result = element(app, LiveAXID.liveSearchResult)
        XCTAssertTrue(result.waitForExistence(timeout: 5))
        XCTAssertTrue(result.label.contains("Pyaar Ki Raah"), result.label)
        screenshot(app, "03-search-pyar")
        // Cmd-Return asks for an optional note; Return adds the request with it.
        key(app, .return, [.command])
        let note = app.textFields[LiveAXID.liveSearchNote]
        XCTAssertTrue(note.waitForExistence(timeout: 5))
        note.typeText("table 4", in: app)
        screenshot(app, "03b-request-note")
        key(app, .return)
        XCTAssertTrue(element(app, LiveAXID.liveSearch).waitForNonExistence(timeout: 5))
        XCTAssertTrue(waitForValue(app.staticTexts[LiveAXID.liveUpNext], "Pyaar Ki Raah"))
        XCTAssertEqual(app.staticTexts[LiveAXID.liveUpNextLabel].value as? String, "Request")
        XCTAssertTrue(element(app, LiveAXID.liveRequestCount).exists)
        screenshot(app, "04-request-queued")
    }

    /// Q shows the queue; R plays the request; Next returns to the interrupted song, then
    /// the rest of the set.
    private func playRequestAndFinish(_ app: XCUIApplication) {
        let title = app.staticTexts[LiveAXID.liveTitle]
        key(app, "q")
        let row = element(app, LiveAXID.liveRequestRow)
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        let note = NSPredicate(
            format: "label CONTAINS %@ OR value CONTAINS %@",
            "table 4",
            "table 4",
        )
        XCTAssertTrue(
            row.descendants(matching: .staticText).matching(note).firstMatch.exists,
            "the request keeps its note",
        )
        screenshot(app, "05-request-panel")
        key(app, "q")
        key(app, "r")
        XCTAssertTrue(waitForValue(title, "Pyaar Ki Raah"))
        screenshot(app, "06-request-playing")
        key(app, .rightArrow)
        XCTAssertTrue(waitForValue(title, "Long Way Home"))
        for expected in ["Copper Sky", "Lantern Song", "River Glass", "Night Bus", "Last Light"] {
            key(app, .rightArrow)
            XCTAssertTrue(waitForValue(title, expected), "expected \(expected)")
        }
    }
}

// MARK: - Steps

extension SegueLiveE2ETests {
    @MainActor
    func launch(_ library: LiveLibrary, extra: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        self.app = app
        E2E.launch(app, arguments: library.arguments(extra: extra))
        return app
    }

    /// Setlists > the Friday setlist > Start Show (or Rehearse) > the checklist's Start.
    @MainActor
    func startShow(_ app: XCUIApplication, rehearse: Bool) {
        element(app, LiveAXID.sidebarSetlists).click(in: app)
        let row = element(app, LiveAXID.setlistRow)
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        row.click(in: app)
        let button = element(app, rehearse ? LiveAXID.setlistRehearse : LiveAXID.setlistStartShow)
        XCTAssertTrue(button.waitForExistence(timeout: 10))
        button.click(in: app)
        let start = element(app, LiveAXID.checklistStart)
        XCTAssertTrue(start.waitForExistence(timeout: 10))
        screenshot(app, rehearse ? "00-checklist-rehearsal" : "00-checklist")
        start.click(in: app)
        XCTAssertTrue(app.staticTexts[LiveAXID.liveTitle].waitForExistence(timeout: 10))
    }

    /// Cmd-. then Return in the confirmation; the stage goes away.
    @MainActor
    private func endShow(_ app: XCUIApplication) {
        key(app, ".", [.command])
        XCTAssertTrue(element(app, LiveAXID.liveEndDialog).waitForExistence(timeout: 5))
        screenshot(app, "end-confirm")
        key(app, .return)
        XCTAssertTrue(app.staticTexts[LiveAXID.liveTitle].waitForNonExistence(timeout: 10))
    }

    /// Settings (Cmd-,) > Live > minimum lyric size.
    @MainActor
    private func setMinimumLyricSize(_ app: XCUIApplication, to size: Int) {
        app.typeKey(",", modifierFlags: .command, in: app)
        let stepper = app.steppers[LiveAXID.settingsMinLyricSize].firstMatch
        XCTAssertTrue(stepper.waitForExistence(timeout: 10))
        let increment = stepper.incrementArrows.firstMatch
        for _ in 0 ..< max(0, size - 22) {
            increment.click(in: app)
        }
        XCTAssertTrue(app.staticTexts["\(size) pt"].waitForExistence(timeout: 5))
        app.typeKey("w", modifierFlags: .command, in: app)
    }

    /// Gig log: the newest entry lists the played and skipped songs (unit D's view).
    @MainActor
    private func assertGigLog(_ app: XCUIApplication) {
        element(app, LiveAXID.sidebarGigLog).click(in: app)
        let entry = element(app, LiveAXID.gigLogRow)
        XCTAssertTrue(entry.waitForExistence(timeout: 10))
        entry.click(in: app)
        let played = app.descendants(matching: .any).matching(identifier: LiveAXID.gigPlayedRow)
        XCTAssertTrue(played.firstMatch.waitForExistence(timeout: 5))
        XCTAssertEqual(played.count, 10)
        XCTAssertEqual(
            app.descendants(matching: .any).matching(identifier: LiveAXID.gigSkippedRow).count,
            1,
        )
        screenshot(app, "08-gig-log")
    }

    // MARK: Helpers

    @MainActor
    @nonobjc func key(
        _ app: XCUIApplication,
        _ key: XCUIKeyboardKey,
        _ modifiers: XCUIElement.KeyModifierFlags = [],
    ) {
        app.typeKey(key, modifierFlags: modifiers, in: app)
    }

    @MainActor
    @nonobjc func key(
        _ app: XCUIApplication,
        _ key: String,
        _ modifiers: XCUIElement.KeyModifierFlags = [],
    ) {
        app.typeKey(key, modifierFlags: modifiers, in: app)
    }

    @MainActor
    func element(_ app: XCUIApplication, _ identifier: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    /// "scroll 0.42" from the body's accessibility value.
    @MainActor
    func scrollPosition(_ body: XCUIElement) -> Double? {
        number(after: "scroll ", in: body)
    }

    @MainActor
    private func lyricSize(_ body: XCUIElement) -> Double? {
        number(after: "lyric ", in: body)
    }

    @MainActor
    func number(after prefix: String, in element: XCUIElement) -> Double? {
        let value = element.label
        guard let range = value.range(of: prefix)
        else { return nil }
        return Double(value[range.upperBound...].prefix { !$0.isWhitespace })
    }

    @MainActor
    func waitForValue(_ element: XCUIElement, _ value: String) -> Bool {
        waitFor(element) { $0.value as? String == value }
    }

    /// Polls `condition` on `element` (a predicate over a computed value is not
    /// re-evaluated reliably for SwiftUI elements).
    @MainActor
    func waitFor(
        _ element: XCUIElement,
        timeout: TimeInterval = 10,
        _ condition: (XCUIElement) -> Bool,
    ) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if element.exists, condition(element) {
                return true
            }
            Thread.sleep(forTimeInterval: 0.1)
        }
        return false
    }

    @MainActor
    func screenshot(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "live-\(name)"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    /// On failure, attach what the app looked like.
    override func record(_ issue: XCTIssue) {
        nonisolated(unsafe) var issue = issue
        let app = app
        if let app {
            MainActor.assumeIsolated {
                issue.add(XCTAttachment(screenshot: app.screenshot()))
                issue.add(XCTAttachment(string: app.debugDescription))
            }
        }
        super.record(issue)
    }
}
