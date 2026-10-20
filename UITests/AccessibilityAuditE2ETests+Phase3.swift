import AppKit
import XCTest

/// Apple's automated audit on the phase 3 screens (P3-9 step 5, R79), on a fresh Welcome
/// library in light appearance: the song card and Section Notes sheet, the visual editor's
/// section band, the paste review sheet, Settings > AI, the set builder in Pick and Arrange
/// with the assistant's chips and a row's score breakdown, the Arrange Sections sheet, and the
/// rehearsal checklist and stage with the metronome. Same rules as the main screens
/// (`ignoredIssue`); the manual VoiceOver, Voice Control and Full Keyboard Access walks are in
/// docs/release/walkthrough.md.
@MainActor
extension AccessibilityAuditE2ETests {
    func testPhase3ScreensLight() throws {
        let welcome = try WelcomeLibrary()
        welcomeRoot = welcome.root
        let app = XCUIApplication()
        self.app = app
        E2E.launch(app, arguments: welcome.arguments([
            "-SegueSeedWelcome", "YES", "-SegueAppearance", "light",
        ]))
        auditSongCardNotesAndBand(app)
        auditPasteReview(app)
        auditAISettings(app)
        auditBuilderAssistantAndArrangement(app)
        auditRehearsalWithMetronome(app)
    }

    /// Kettle On's song card and Section Notes sheet; the visual editor with its bands.
    private func auditSongCardNotesAndBand(_ app: XCUIApplication) {
        let kettle = app.descendants(matching: .any).matching(identifier: AuditAXID.songRow)
            .matching(NSPredicate(format: "label BEGINSWITH %@", "Kettle On")).firstMatch
        XCTAssertTrue(kettle.appears(timeout: 15), "no Welcome songs")
        kettle.click(in: app)
        XCTAssertTrue(element(app, SongCardAXID.help).appears(timeout: 10), "no song card")
        audit(app, "p3-song-card")
        element(app, SongCardAXID.token("tempo")).click(in: app)
        XCTAssertTrue(element(app, SongCardAXID.tempo).appears(timeout: 5), "no tempo field")
        audit(app, "p3-song-card-tempo")
        app.typeKey(.escape, modifierFlags: [], in: app)
        element(app, NotesAXID.open).click(in: app)
        XCTAssertTrue(element(app, NotesAXID.done).appears(timeout: 5), "no Section Notes")
        audit(app, "p3-section-notes")
        element(app, NotesAXID.done).click(in: app)
        XCTAssertTrue(element(app, NotesAXID.done).disappears(timeout: 5))
        element(app, AuditAXID.editSong).click(in: app)
        element(app, AuditAXID.editorModeVisual).click(in: app)
        XCTAssertTrue(element(app, NotesAXID.band).appears(timeout: 10), "no section band")
        audit(app, "p3-editor-section-band")
        element(app, AuditAXID.editorDone).click(in: app)
    }

    /// New Song from Clipboard on a chord sheet: the review sheet, then Cancel.
    private func auditPasteReview(_ app: XCUIApplication) {
        let board = NSPasteboard.general
        board.clearContents()
        board.setString(SeguePasteE2ETests.sheet, forType: .string)
        app.typeKey("v", modifierFlags: [.command, .option], in: app)
        let sheet = element(app, PasteAXID.sheet)
        XCTAssertTrue(sheet.appears(timeout: 10), "no review sheet")
        XCTAssertTrue(element(app, PasteAXID.result).appears(timeout: 10))
        audit(app, "p3-paste-review")
        element(app, PasteAXID.cancel).click(in: app)
        XCTAssertTrue(sheet.disappears(timeout: 10))
    }

    /// Settings > AI with no model: Apple Intelligence status, the toggle, the model card.
    private func auditAISettings(_ app: XCUIApplication) {
        app.typeKey(",", modifierFlags: .command, in: app)
        let tab = app.toolbars.buttons["AI"].firstMatch
        XCTAssertTrue(tab.appears(timeout: 10), "no AI pane")
        tab.click(in: app)
        XCTAssertTrue(element(app, AISettingsAXID.useAI).appears(timeout: 5))
        audit(app, "p3-settings-ai")
        app.typeKey("w", modifierFlags: .command, in: app)
    }

    /// Welcome Set: Pick, Arrange with a request's chips and Build, a breakdown, then the
    /// first row's Arrange Sections sheet.
    private func auditBuilderAssistantAndArrangement(_ app: XCUIApplication) {
        element(app, AuditAXID.sidebarSetlists).click(in: app)
        let setlist = element(app, AuditAXID.setlistRow)
        XCTAssertTrue(setlist.appears(timeout: 10))
        setlist.click(in: app)
        XCTAssertTrue(element(app, AuditAXID.setlistEntry).appears(timeout: 10))
        app.typeKey("1", modifierFlags: .command, in: app)
        XCTAssertTrue(element(app, SetlistAXID.builderLibrary).appears(timeout: 10), "no Pick")
        audit(app, "p3-builder-pick")
        app.typeKey("2", modifierFlags: .command, in: app)
        let field = app.textFields[AssistantAXID.field]
        XCTAssertTrue(field.appears(timeout: 10), "no assistant bar in Arrange")
        audit(app, "p3-builder-arrange")
        field.click(in: app)
        field.typeText("15 min, songs I know well", in: app)
        XCTAssertTrue(element(app, AssistantAXID.chip).appears(timeout: 5), "no chips")
        app.buttons[AssistantAXID.build].click(in: app)
        XCTAssertTrue(element(app, AuditAXID.setlistEntry).appears(timeout: 10))
        audit(app, "p3-assistant-built")
        let first = app.descendants(matching: .any).matching(identifier: AuditAXID.setlistEntry)
            .element(boundBy: 0)
        XCUIElement.perform(withKeyModifiers: .command) {
            first.staticTexts[SetlistAXID.entryTitle].click()
        }
        app.typeKey(.space, modifierFlags: [], in: app)
        if element(app, AssistantAXID.breakdown).appears(timeout: 5) {
            audit(app, "p3-assistant-breakdown")
            app.typeKey(.escape, modifierFlags: [], in: app)
        } else {
            XCTFail("Space opened no breakdown")
        }
        first.staticTexts[SetlistAXID.entryTitle].click(in: app)
        element(app, ArrangementAXID.open).click(in: app)
        let sheet = element(app, ArrangementAXID.sheet)
        XCTAssertTrue(sheet.appears(timeout: 10), "Arrange Sections never opened")
        audit(app, "p3-arrange-sections")
        element(app, ArrangementAXID.done).click(in: app)
        XCTAssertTrue(sheet.disappears(timeout: 5))
    }

    /// Rehearse: the checklist with the metronome rows, then the stage with the metronome on.
    private func auditRehearsalWithMetronome(_ app: XCUIApplication) {
        element(app, MetronomeAXID.rehearse).click(in: app)
        let metronome = element(app, MetronomeAXID.checklistMetronome)
        XCTAssertTrue(metronome.appears(timeout: 10), "no metronome row in the checklist")
        audit(app, "p3-rehearsal-checklist")
        element(app, AuditAXID.checklistStart).click(in: app)
        let title = app.staticTexts[AuditAXID.liveTitle]
        XCTAssertTrue(title.appears(timeout: 10))
        let pulse = element(app, MetronomeAXID.pulse)
        // The metronome shows only for a song with a tempo; M toggles it for this show.
        if !pulse.appears(timeout: 3) {
            app.typeKey("m", modifierFlags: [], in: app)
        }
        XCTAssertTrue(pulse.appears(timeout: 5), "no metronome on stage")
        audit(app, "p3-stage-metronome")
        app.typeKey(".", modifierFlags: .command, in: app)
        XCTAssertTrue(element(app, AuditAXID.liveEndDialog).appears(timeout: 5))
        app.typeKey(.return, modifierFlags: [], in: app)
        XCTAssertTrue(title.disappears(timeout: 10))
    }
}
