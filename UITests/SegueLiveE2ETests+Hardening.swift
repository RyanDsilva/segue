import AppKit
import XCTest

/// Live mode E2E for the phase 2 review fixes that only the real app shows: Cmd-W / Cmd-Q
/// on stage (review finding 10) and the single-instance guard (finding 9).
@MainActor
extension SegueLiveE2ETests {
    // MARK: Review finding 10: Cmd-W and Cmd-Q on stage go through the end confirmation

    @objc func testCloseAndQuitOnStageAskFirstThenEndAndQuit() throws {
        let library = try XCTUnwrap(library)
        let app = launch(library, extra: LiveLibrary.gigModeShortcuts)
        startShow(app, rehearse: false)
        let dialog = element(app, LiveAXID.liveEndDialog)
        key(app, "w", [.command])
        XCTAssertTrue(dialog.appears(timeout: 5))
        key(app, .escape)
        XCTAssertTrue(dialog.disappears(timeout: 5))
        XCTAssertTrue(app.staticTexts[LiveAXID.liveTitle].exists, "Cmd-W closed the stage")

        key(app, "q", [.command])
        XCTAssertTrue(dialog.appears(timeout: 5))
        XCTAssertTrue(app.buttons["End and Quit (Return)"].exists)
        screenshot(app, "13-quit-confirm")
        XCTAssertEqual(app.state, .runningForeground)
        E2E.quitting { key(app, .return) }
        XCTAssertTrue(app.reaches(.notRunning, timeout: 20), "Segue did not quit")
        // Ended properly: in the gig log, with the end Shortcut run.
        let show = try XCTUnwrap(library.shows().first)
        XCTAssertNotNil(show["endedAt"] as? String)
        XCTAssertEqual(library.shortcutsRun(), ["Gig Mode On", "Gig Mode Off"])
    }

    // MARK: Review finding 9: one Segue at a time

    @objc func testSecondLaunchHandsOverToTheRunningInstance() throws {
        let library = try XCTUnwrap(library)
        let app = launch(library)
        XCTAssertTrue(element(app, LiveAXID.sidebarSetlists).appears(timeout: 15))
        let bundleID = "dev.ryandsilva.segue.personal"
        let first = try XCTUnwrap(
            NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first,
        )
        let bundleURL = try XCTUnwrap(first.bundleURL)
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.createsNewApplicationInstance = true
        configuration.activates = false
        configuration.arguments = library.arguments(reset: false)
        let opened = expectation(description: "second instance launched")
        nonisolated(unsafe) var second: NSRunningApplication?
        NSWorkspace.shared.openApplication(at: bundleURL, configuration: configuration) { app, _ in
            second = app
            opened.fulfill()
        }
        wait(for: [opened], timeout: 20)
        let launched = try XCTUnwrap(second, "the second instance did not launch")
        XCTAssertNotEqual(launched.processIdentifier, first.processIdentifier)
        // Polled through the run loop: `isTerminated` is updated there. `kill(pid, 0)`
        // also says when the process is gone.
        let pid = launched.processIdentifier
        let deadline = Date().addingTimeInterval(15)
        while kill(pid, 0) == 0, Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }
        XCTAssertNotEqual(kill(pid, 0), 0, "the second instance kept running")
        XCTAssertFalse(first.isTerminated)
        XCTAssertEqual(
            NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).count,
            1,
        )
        XCTAssertNotEqual(app.state, .notRunning)
    }
}
