import XCTest

/// Help > Report a Problem through the real UI (WS3 spec 14.3-4/5): the song file is off by
/// default, the preview shows everything and the bytes sent are the previewed ones (the
/// Recording sender logs their SHA-256); offline, the email and save fallbacks appear.
final class SegueReportProblemE2ETests: XCTestCase, ServicesE2E {
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

    // MARK: 14.3-4 The preview is what is sent

    @MainActor
    func testReportPreviewMatchesSent() throws {
        let library = try XCTUnwrap(library)
        let app = launchServices(library, extra: ["-SegueAppearance", "light"])
        openSong(app, titled: "Pyaar Ki Raah")
        let send = openReport(app)
        XCTAssertFalse(send.isEnabled, "Send is enabled with no description")
        let song = element(app, ServicesAXID.reportAttachSong)
        XCTAssertEqual(song.value as? Int, 0, "the song file is attached by default")
        XCTAssertEqual(element(app, ServicesAXID.reportAttachLogs).value as? Int, 1)
        type("Segue froze when I pressed the next song key on stage.", app)
        XCTAssertTrue(waitFor { send.isEnabled })
        screenshot(app, "report-form-light")

        // Preview without the song: logs and system info, none of the song's text.
        element(app, ServicesAXID.reportPreviewButton).click(in: app)
        XCTAssertTrue(element(app, ServicesAXID.reportPreview).appears(timeout: 5))
        XCTAssertTrue(attachment(app, "segue-0.log").exists, "no log in the preview")
        XCTAssertFalse(attachment(app, "pyaar-ki-raah.cho").exists)
        XCTAssertTrue(app.staticTexts["Mac model"].exists)
        XCTAssertFalse(previewText(app, containing: "Chalte").exists)
        screenshot(app, "report-preview-light")

        // Back, tick the song: the new preview carries its file, lyrics and sidecar.
        element(app, ServicesAXID.reportBack).click(in: app)
        // A short window shows the form scrolled: bring the attachments into view.
        app.textViews[ServicesAXID.reportMessage].firstMatch.scroll(byDeltaX: 0, deltaY: -400)
        song.click(in: app)
        XCTAssertTrue(waitFor { song.value as? Int == 1 })
        element(app, ServicesAXID.reportPreviewButton).click(in: app)
        let songFile = attachment(app, "pyaar-ki-raah.cho")
        XCTAssertTrue(songFile.appears(timeout: 5))
        XCTAssertTrue(attachment(app, "pyaar-ki-raah.segue.json").exists)
        let preview = element(app, ServicesAXID.reportPreview)
        preview.scroll(byDeltaX: 0, deltaY: -2000)
        songFile.click(in: app)
        preview.scroll(byDeltaX: 0, deltaY: -2000)
        XCTAssertTrue(previewText(app, containing: "Chalte chalte").appears(timeout: 5))
        let hash = element(app, ServicesAXID.reportPreviewHash).label
        XCTAssertEqual(hash.count, 64)

        element(app, ServicesAXID.reportSend).click(in: app)
        XCTAssertTrue(element(app, ServicesAXID.reportSent).appears(timeout: 10))
        screenshot(app, "report-sent-light")
        let sent = library.servicesEntries().filter { $0["kind"] as? String == "feedback" }
        XCTAssertEqual(sent.count, 1)
        XCTAssertEqual(sent.first?["sha256"] as? String, hash, "sent bytes differ from preview")
        element(app, ServicesAXID.reportDone).click(in: app)
        XCTAssertTrue(element(app, ServicesAXID.reportSheet).disappears(timeout: 5))
    }

    // MARK: 14.3-5 Offline: email or save instead

    @MainActor
    func testReportOfflineFallback() throws {
        let library = try XCTUnwrap(library)
        let mailLog = library.root.appending(path: "mail.jsonl")
        let app = launchServices(library, extra: [
            "-SegueFeedbackResult", "offline",
            "-SegueMailLog", mailLog.path(percentEncoded: false),
            "-SegueAppearance", "dark",
        ])
        let send = openReport(app)
        type("The library list went blank after an import.", app)
        XCTAssertTrue(waitFor { send.isEnabled })
        screenshot(app, "report-form-dark")
        // Send from the form previews first: nothing goes out unseen.
        send.click(in: app)
        XCTAssertTrue(element(app, ServicesAXID.reportPreview).appears(timeout: 5))
        XCTAssertFalse(library.kinds().contains("feedback"), "sent before the preview")
        screenshot(app, "report-preview-dark")
        element(app, ServicesAXID.reportSend).click(in: app)

        XCTAssertTrue(element(app, ServicesAXID.reportFailure).appears(timeout: 10))
        for id in [
            ServicesAXID.reportEmailInstead, ServicesAXID.reportSaveReport,
            ServicesAXID.reportTryAgain,
        ] {
            XCTAssertTrue(element(app, id).exists, "\(id) missing")
        }
        screenshot(app, "report-offline-dark")

        element(app, ServicesAXID.reportEmailInstead).click(in: app)
        XCTAssertTrue(waitFor { (try? Data(contentsOf: mailLog)) != nil })
        let line = try XCTUnwrap(String(contentsOf: mailLog, encoding: .utf8)
            .split(separator: "\n").first)
        let draft = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any],
        )
        XCTAssertEqual(draft["to"] as? String, ServicesLinks.supportAddress)
        let subject = draft["subject"] as? String ?? ""
        XCTAssertTrue(subject.hasPrefix("Segue ") && subject.hasSuffix(" problem"), subject)
        XCTAssertTrue((draft["attachments"] as? [String] ?? []).contains("segue-0.log"))
        XCTAssertEqual(draft["attachmentsExist"] as? Bool, true)
        XCTAssertFalse(library.kinds().contains("feedback"), "an offline report was recorded")
    }
}

@MainActor
extension SegueReportProblemE2ETests {
    /// Help > Report a Problem…; returns the Send button.
    func openReport(_ app: XCUIApplication) -> XCUIElement {
        XCTAssertTrue(element(app, LiveAXID.songRow).appears(timeout: 15))
        helpMenu(app, "Report a Problem…")
        XCTAssertTrue(element(app, ServicesAXID.reportSheet).appears(timeout: 10))
        let send = element(app, ServicesAXID.reportSend)
        XCTAssertTrue(send.appears(timeout: 5))
        return send
    }

    func type(_ text: String, _ app: XCUIApplication) {
        let field = app.textViews[ServicesAXID.reportMessage].firstMatch
        XCTAssertTrue(field.appears(timeout: 5))
        field.click(in: app)
        field.typeText(text, in: app)
    }

    func attachment(_ app: XCUIApplication, _ name: String) -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(
            format: "identifier == %@ AND label == %@",
            ServicesAXID.reportPreviewAttachment,
            name,
        )).firstMatch
    }

    func previewText(_ app: XCUIApplication, containing text: String) -> XCUIElement {
        element(app, ServicesAXID.reportPreview).descendants(matching: .staticText)
            .matching(NSPredicate(format: "label CONTAINS %@ OR value CONTAINS %@", text, text))
            .firstMatch
    }
}
