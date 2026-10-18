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
            extra: ["-SegueConsent", "undecided", "-SegueAppearance", "light"],
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
            extra: ["-SegueConsent", "undecided", "-SegueAppearance", "dark"],
        )
        XCTAssertTrue(element(app, ServicesAXID.consentSheet).appears(timeout: 15))
        screenshot(app, "consent-dark")
        answerConsent(app, analytics: true, crash: true)
        openPrivacySettings(app)
        screenshot(app, "privacy-dark")
    }

    // MARK: 14.3-2 Nothing is sent before consent

    @MainActor
    func testNothingSentBeforeConsent() throws {
        let library = try XCTUnwrap(library)
        let app = launchServices(library, extra: ["-SegueConsent", "undecided"])
        XCTAssertTrue(element(app, ServicesAXID.consentSheet).appears(timeout: 15))
        // Unanswered: no signal, breadcrumb or crash-reporter start, however long it waits.
        XCTAssertFalse(waitFor(timeout: 3) { !library.servicesEntries().isEmpty })
        app.terminate()

        // Asked once until answered: the prompt is back, and still nothing was sent.
        let relaunched = launchServices(
            library,
            reset: false,
            extra: ["-SegueConsent", "asStored"],
        )
        XCTAssertTrue(element(relaunched, ServicesAXID.consentSheet).appears(timeout: 15))
        XCTAssertFalse(waitFor(timeout: 2) { !library.servicesEntries().isEmpty })
        XCTAssertEqual(library.servicesEntries().count, 0, library.servicesText())
    }

    // MARK: 14.3-3 Revoking stops sending at once

    @MainActor
    func testRevokeStopsSending() throws {
        let library = try XCTUnwrap(library)
        let app = launchServices(
            library,
            extra: ["-SegueConsent", "granted", "-SegueAppearance", "light"],
        )
        openEditor(app, titled: "Harbor Lights")
        element(app, ServicesAXID.editorTransposeUp).click(in: app)
        XCTAssertTrue(waitFor { self.features(library).contains("transpose") })
        XCTAssertTrue(library.kinds().contains("crash.start"))

        openPrivacySettings(app)
        let analytics = element(app, ServicesAXID.privacyToggle("analytics"))
        XCTAssertEqual(analytics.value as? Int, 1, "analytics should be on")
        analytics.click(in: app)
        XCTAssertTrue(element(app, ServicesAXID.privacyCaption("analytics")).appears(timeout: 5))
        XCTAssertTrue(waitFor { library.kinds().contains("analytics.shutDown") })

        let crash = element(app, ServicesAXID.privacyToggle("crashReports"))
        crash.click(in: app)
        XCTAssertTrue(element(app, ServicesAXID.privacyCaption("crashReports")).appears(timeout: 5))
        XCTAssertTrue(element(app, ServicesAXID.privacyDiagnosticsID).exists)
        XCTAssertTrue(element(app, ServicesAXID.privacyCopyID).exists)
        XCTAssertTrue(waitFor { library.kinds().contains("crash.shutDown") })
        screenshot(app, "privacy-revoked-light")

        crash.click(in: app)
        XCTAssertTrue(element(app, ServicesAXID.privacyRestartCaption).appears(timeout: 5))
        screenshot(app, "privacy-restart-light")
        app.typeKey("w", modifierFlags: .command, in: app)

        // A feature never used today: it would be sent if analytics were still on.
        let before = library.signals().count
        element(app, ServicesAXID.editorNashville).click(in: app)
        XCTAssertFalse(
            waitFor(timeout: 2) { library.signals().count > before },
            "a signal was recorded after analytics were turned off",
        )
    }

    // MARK: 14.3-7 No user content in signals

    @MainActor
    func testNoUserContentInSignals() throws {
        let library = try XCTUnwrap(library)
        let app = launchServices(library, extra: ["-SegueConsent", "granted"])
        XCTAssertTrue(element(app, LiveAXID.songRow).appears(timeout: 15))

        // A romanized-Hindi spelling variant of a fixture title.
        let query = "pyar ki rah"
        let search = app.searchFields[ServicesAXID.librarySearch]
        XCTAssertTrue(search.appears(timeout: 5))
        search.click(in: app)
        search.typeText(query, in: app)
        XCTAssertTrue(waitFor { !library.signals(named: "Segue.Search.performed").isEmpty })
        let tiers = library.signals(named: "Segue.Search.performed").compactMap {
            $0["segue.matchTier"]
        }
        XCTAssertTrue(
            tiers.contains { ["spellingVariant", "looseVariant"].contains($0) },
            "\(tiers)",
        )

        // The chord palette in the visual editor.
        openEditor(app, titled: "Pyaar Ki Raah")
        let chip = element(app, ServicesAXID.editorPaletteChord)
        XCTAssertTrue(chip.appears(timeout: 10))
        chip.click(in: app)
        XCTAssertTrue(waitFor { !library.signals(named: "Segue.Editor.chordPalette").isEmpty })
        element(app, ServicesAXID.editorDone).click(in: app)

        rehearseFixtureSetlist(app)
        XCTAssertTrue(waitFor { !library.signals(named: "Segue.Show.ended").isEmpty })

        // Nothing the user wrote, searched for or named is anywhere in what was recorded.
        let recorded = Self.words(library.servicesText() + library.diagnosticLogText())
        var secrets = Self.words(query)
        for title in library.setTitles + library.extraTitles {
            secrets.formUnion(Self.words(title))
        }
        secrets.formUnion(Self.words(LiveLibrary.pyaar.replacing(
            /\{[a-z_]+:?|\[[^\]]*\]/,
            with: " ",
        )))
        secrets.formUnion(Self.words(library.setlistName))
        secrets.formUnion(Self.words(library.path))
        secrets.subtract(["segue", "private", "verse", "chorus", "show", "line"])
        let leaked = secrets.filter { $0.count >= 4 }.intersection(recorded)
        XCTAssertTrue(leaked.isEmpty, "user words reached services: \(leaked.sorted())")
    }
}

extension SegueServicesE2ETests {
    /// Setlists > the fixture setlist > Rehearse, one song on, then End Show.
    @MainActor
    func rehearseFixtureSetlist(_ app: XCUIApplication) {
        element(app, LiveAXID.sidebarSetlists).click(in: app)
        let setlist = element(app, LiveAXID.setlistRow)
        XCTAssertTrue(setlist.appears(timeout: 10))
        setlist.click(in: app)
        element(app, LiveAXID.setlistRehearse).click(in: app)
        let start = element(app, LiveAXID.checklistStart)
        if start.appears(timeout: 5) {
            start.click(in: app)
        }
        XCTAssertTrue(app.staticTexts[LiveAXID.liveTitle].appears(timeout: 10))
        app.typeKey(.rightArrow, modifierFlags: [], in: app)
        app.typeKey(".", modifierFlags: .command, in: app)
        XCTAssertTrue(element(app, LiveAXID.liveEndDialog).appears(timeout: 5))
        app.typeKey(.return, modifierFlags: [], in: app)
    }

    /// The `segue.feature` values recorded so far.
    @MainActor
    func features(_ library: LiveLibrary) -> [String] {
        library.signals(named: "Segue.Feature.used").compactMap { $0["segue.feature"] }
    }

    /// Lowercased letter runs.
    static func words(_ text: String) -> Set<String> {
        Set(text.split(whereSeparator: { !$0.isLetter }).map { $0.lowercased() })
    }
}
