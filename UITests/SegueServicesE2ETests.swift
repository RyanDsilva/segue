import XCTest

/// Consent, Settings > Privacy and event emission through the real UI (WS3 spec 14.3), with
/// the Recording adapters (`-SegueServicesLog`): nothing is sent before consent, the two
/// choices are equal, revoking stops sending at once, and no user content reaches a signal.
final class SegueServicesE2ETests: XCTestCase, ServicesE2E {
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

    // MARK: 14.3-1 First run asks both questions, equally

    @MainActor
    func testConsentFirstRunAsksBothEqually() throws {
        let library = try XCTUnwrap(library)
        let app = launchServices(
            library,
            extra: ["-SegueConsent", "undecided", "-AppleInterfaceStyle", "Light"],
        )
        let title = element(app, ServicesAXID.consentSheet)
        XCTAssertTrue(title.appears(timeout: 15), "no consent prompt on first run")

        let buttons = ["analytics", "crashReports"].flatMap { toggle in
            [
                element(app, ServicesAXID.consentDecline(toggle)),
                element(app, ServicesAXID.consentAccept(toggle)),
            ]
        }
        for button in buttons {
            XCTAssertTrue(button.appears(timeout: 5))
            XCTAssertEqual(button.value as? String, "not selected", "a choice is preselected")
        }
        let first = buttons[0].frame
        for button in buttons.dropFirst() {
            XCTAssertEqual(button.frame.width, first.width, accuracy: 1, "unequal widths")
            XCTAssertEqual(button.frame.height, first.height, accuracy: 1, "unequal heights")
        }
        let next = element(app, ServicesAXID.consentContinue)
        XCTAssertFalse(next.isEnabled, "Continue is enabled before both are answered")
        screenshot(app, "consent-light")

        // Esc does nothing.
        app.typeKey(.escape, modifierFlags: [], in: app)
        XCTAssertFalse(waitFor(timeout: 1) { !title.exists }, "Esc closed the prompt")

        element(app, ServicesAXID.consentAccept("analytics")).click(in: app)
        XCTAssertFalse(next.isEnabled, "Continue is enabled with one question answered")
        element(app, ServicesAXID.consentDecline("crashReports")).click(in: app)
        XCTAssertTrue(waitFor { next.isEnabled })
        XCTAssertTrue(
            element(app, ServicesAXID.consentAccept("analytics")).hasValue("selected"),
        )
        screenshot(app, "consent-answered-light")
        next.click(in: app)
        XCTAssertTrue(title.disappears(timeout: 10))

        XCTAssertTrue(waitFor { library.signals().contains("Segue.Privacy.analyticsEnabled") })
        XCTAssertEqual(
            library.signals(named: "Segue.Privacy.analyticsEnabled"),
            [["segue.source": "prompt"]],
        )
        XCTAssertFalse(library.kinds().contains("crash.start"), "crash reporting started")

        // Asked once: a relaunch keeps the answers and does not ask again.
        app.terminate()
        let relaunched = launchServices(library, reset: false)
        XCTAssertTrue(element(relaunched, LiveAXID.songRow).appears(timeout: 15))
        XCTAssertFalse(
            waitFor(timeout: 2) { self.element(relaunched, ServicesAXID.consentSheet).exists },
            "the prompt came back after it was answered",
        )
    }

    // MARK: Both appearances (pixel pass)

    @MainActor
    func testConsentAndPrivacyInDarkAppearance() throws {
        let library = try XCTUnwrap(library)
        let app = launchServices(
            library,
            extra: ["-SegueConsent", "undecided", "-AppleInterfaceStyle", "Dark"],
        )
        XCTAssertTrue(element(app, ServicesAXID.consentSheet).appears(timeout: 15))
        screenshot(app, "consent-dark")
        answerConsent(app, analytics: true, crash: true)
        openPrivacySettings(app)
        screenshot(app, "privacy-dark")
    }
}
