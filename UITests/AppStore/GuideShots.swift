import AppKit
import XCTest

/// The user guide's screenshots (WS6 section 5), one test per area. Run by `make docs-shots`
/// (twice: dark, then light), never by `make e2e` or the gate. Shot ids match the
/// `<Shot id>` and `<Tile shot>` uses in guide/src/content/docs.
final class GuideShots: GuideShotCase {
    /// Library, song card and search: start-library, card, card-time-it, library-search.
    @MainActor
    func testLibrary() {
        let app = launch()
        let window = mainWindow(app)
        _ = element(app, GuideAXID.songRow)
        shoot("start-library", window)

        song(app, titled: "Kettle On, Lights Low").click(in: app)
        _ = element(app, GuideAXID.songCard)
        shoot("card", window, callouts: [
            "key": element(app, GuideAXID.cardToken("key")),
            "tempo": element(app, GuideAXID.cardToken("tempo")),
            "artists": element(app, GuideAXID.songCardArtist),
        ])

        let search = element(app, GuideAXID.librarySearch)
        search.click(in: app)
        search.typeText("kitabon", in: app)
        _ = song(app, titled: "Kitaabon Wali Gali")
        shoot("library-search", window)
    }

    /// The first-run Welcome cards: welcome-cards.
    @MainActor
    func testWelcomeCards() {
        let app = launch(["-SegueOnboarding", "fresh"])
        let sheet = app.sheets.firstMatch
        XCTAssertTrue(sheet.appears(timeout: 15), "no Welcome sheet")
        _ = element(app, GuideAXID.welcomeAddSongs)
        shoot("welcome-cards", sheet)
    }

    /// The editor: editor-visual, transpose, diagrams, band, slash-menu.
    @MainActor
    func testEditor() {
        let app = launch()
        let window = mainWindow(app)
        song(app, titled: "Kettle On, Lights Low").click(in: app)
        element(app, GuideAXID.editSong).click(in: app)
        _ = element(app, GuideAXID.editorVisual)
        shoot("editor-visual", window)
        let up = element(app, GuideAXID.editorTransposeUp)
        up.click(in: app)
        up.click(in: app)
        shoot("transpose", window)
        up.click(in: app)
        // Back to the song's own key for the diagrams.
        let down = element(app, GuideAXID.editorTransposeDown)
        for _ in 0 ..< 3 {
            down.click(in: app)
        }
        element(app, GuideAXID.editorDiagramsToggle).click(in: app)
        let strip = element(app, GuideAXID.diagramStrip)
        shoot("diagrams", window, callouts: ["strip": strip])
        element(app, GuideAXID.editorDiagramsToggle).click(in: app)

        let verse = app.descendants(matching: .any)
            .matching(identifier: GuideAXID.sectionBand)
            .matching(NSPredicate(format: "label BEGINSWITH %@", "Verse")).firstMatch
        XCTAssertTrue(verse.appears(timeout: 10), "no Verse section band")
        shoot("band", window, callouts: ["verse": verse])

        element(app, GuideAXID.editorModeText).click(in: app)
        let text = app.textViews[GuideAXID.editorText]
        XCTAssertTrue(text.appears(timeout: 10), "no text editor")
        text.click(in: app)
        // Line 9 is the blank line after the directives: the menu opens near the top, whole.
        app.typeKey(.upArrow, modifierFlags: .command, in: app)
        for _ in 0 ..< 8 {
            app.typeKey(.downArrow, modifierFlags: [], in: app)
        }
        text.typeText("/", in: app)
        let menu = element(app, GuideAXID.slashMenu)
        shoot("slash-menu", window, callouts: ["menu": menu])
        app.typeKey(.escape, modifierFlags: [], in: app)
        app.typeKey("z", modifierFlags: .command, in: app)
    }

    /// Section notes: notes-sheet, notes-stage (the Welcome song's own stage note).
    @MainActor
    func testSectionNotes() {
        let app = launch()
        song(app, titled: "Kettle On, Lights Low").click(in: app)
        element(app, GuideAXID.sectionNotesOpen).click(in: app)
        element(app, GuideAXID.sectionNotesAddChorus).click(in: app)
        let note = app.textFields[GuideAXID.sectionNotesText]
        XCTAssertTrue(note.appears(timeout: 10), "no note field")
        note.click(in: app)
        note.typeText("Brushes only, build on the last line", in: app)
        let sheet = app.sheets.firstMatch
        shoot("notes-sheet", sheet)
        element(app, GuideAXID.sectionNotesDone).click(in: app)
        XCTAssertTrue(sheet.disappears(timeout: 10))

        openSetlist(app, "Welcome Set")
        element(app, GuideAXID.setlistStartShow).click(in: app)
        element(app, GuideAXID.checklistStart).click(in: app)
        XCTAssertTrue(app.staticTexts[GuideAXID.liveTitle].appears(timeout: 10))
        let cue = element(app, GuideAXID.liveCue)
        shoot("notes-stage", stageWindow(app), callouts: ["note": cue], stage: true)
        endShow(app)
    }

    /// New Song, paste and import: new-song, paste-review, paste-review-labels, import-batch.
    @MainActor
    func testNewSongAndPaste() {
        let app = launch()
        element(app, GuideAXID.newSong).click(in: app)
        let sheet = app.sheets.firstMatch
        XCTAssertTrue(sheet.appears(timeout: 10), "New Song opened no sheet")
        shoot("new-song", sheet)
        app.typeKey(.escape, modifierFlags: [], in: app)
        XCTAssertTrue(sheet.disappears(timeout: 10))

        let review = pasteFixture(app)
        let label = aiSectionLabel(app)
        shoot("paste-review", review, callouts: [
            "original": element(app, GuideAXID.pasteOriginal),
            "result": element(app, GuideAXID.pasteResult),
            "footer": element(app, GuideAXID.pasteProvider),
        ])
        // The result column from its top to just above the sheet's footer.
        let footer = element(app, GuideAXID.pasteProvider).frame
        let result = element(app, GuideAXID.pasteResult).frame
        shoot(
            "paste-review-labels",
            element(app, GuideAXID.pasteResult),
            callouts: ["label": label],
            clip: CGRect(
                x: result.minX,
                y: result.minY,
                width: result.width,
                height: max(0, footer.minY - 14 - result.minY),
            ),
        )
        element(app, GuideAXID.pasteCancel).click(in: app)
        XCTAssertTrue(review.disappears(timeout: 10))

        app.typeKey("i", modifierFlags: [.command, .shift], in: app)
        let rows = app.descendants(matching: .any).matching(identifier: GuideAXID.pasteBatchRow)
        XCTAssertTrue(E2E.waitUntil(timeout: 20) { rows.count == 3 }, "no batch of 3 files")
        app.typeKey(.tab, modifierFlags: .shift, in: app)
        shoot("import-batch", app.sheets.firstMatch)
        element(app, GuideAXID.pasteCancel).click(in: app)
    }

    /// The set builder and the assistant: builder-pick, builder-arrange, assistant-bar,
    /// assistant-why.
    @MainActor
    func testSetBuilder() {
        let app = launch()
        let window = mainWindow(app)
        openSetlist(app, "Welcome Set")
        app.typeKey("1", modifierFlags: .command, in: app)
        shoot("builder-pick", window)
        app.typeKey("2", modifierFlags: .command, in: app)
        shoot("builder-arrange", window)
        let field = app.textFields[GuideAXID.assistantField]
        XCTAssertTrue(field.appears(timeout: 10))
        field.click(in: app)
        field.typeText("20 min, songs I know well, no ballads", in: app)
        _ = element(app, GuideAXID.assistantChip)
        app.buttons[GuideAXID.assistantBuild].click(in: app)
        let status = element(app, GuideAXID.assistantStatus)
        shoot("assistant-bar", element(app, GuideAXID.assistantBar), callouts: [
            "request": field,
            "chips": element(app, GuideAXID.assistantChips),
            "total": status,
        ])
        let title = app.staticTexts.matching(identifier: GuideAXID.entryTitle).firstMatch
        XCTAssertTrue(title.appears(timeout: 20), "no set rows after Build")
        XCUIElement.perform(withKeyModifiers: .command) { title.click() }
        app.typeKey(" ", modifierFlags: [], in: app)
        let breakdown = element(app, GuideAXID.assistantBreakdown)
        shoot("assistant-why", window, callouts: ["why": breakdown])
    }

    /// The set composer (P8-5): builder-composer, a new set typed with ⌘L, the next song's
    /// ghost and key showing.
    @MainActor
    func testSetComposer() {
        let app = launch()
        let window = mainWindow(app)
        app.typeKey("n", modifierFlags: [.command, .shift], in: app)
        let name = app.textFields[GuideAXID.newSetlistName]
        XCTAssertTrue(name.appears(timeout: 10))
        name.typeText("Sangeet Night\n", in: app)
        let field = app.textFields[GuideAXID.setlistComposer]
        XCTAssertTrue(field.appears(timeout: 10))
        app.typeKey("2", modifierFlags: .command, in: app)
        app.typeKey("l", modifierFlags: .command, in: app)
        for line in ["kitabon wali in Bm", "ferry lights", "---"] {
            field.typeText(line, in: app)
            app.typeKey(.return, modifierFlags: [], in: app)
        }
        field.typeText("soundchek in A", in: app)
        // The ghost ("→ Soundcheck at Seven") is hidden from accessibility: wait for the
        // typed line, then let the row settle.
        XCTAssertTrue(
            E2E.waitUntil(timeout: 5) { (field.value as? String) == "soundchek in A" },
            "the composer never held the typed line",
        )
        _ = field.settles(timeout: 3)
        shoot("builder-composer", window)
    }

    /// Running time and breaks: timeline, missing-times, stage-break; Arrange Sections:
    /// arrange-sheet.
    @MainActor
    func testRunningTime() {
        let app = launch()
        let window = mainWindow(app)
        // Ferry Lights loses its tempo, so the set has one song with no time.
        song(app, titled: "Ferry Lights Over Calder Bay").click(in: app)
        element(app, GuideAXID.cardToken("tempo")).click(in: app)
        let tempo = app.textFields[GuideAXID.songCardTempo]
        XCTAssertTrue(tempo.appears(timeout: 10))
        tempo.click(in: app)
        app.typeKey("a", modifierFlags: .command, in: app)
        app.typeKey(.delete, modifierFlags: [], in: app)
        app.typeKey(.return, modifierFlags: [], in: app)
        app.typeKey(.escape, modifierFlags: [], in: app)

        openSetlist(app, "Welcome Set")
        app.typeKey("2", modifierFlags: .command, in: app)
        let kitaabon = app.staticTexts.matching(identifier: GuideAXID.entryTitle)
            .matching(NSPredicate(
                format: "label CONTAINS %@ OR value CONTAINS %@",
                "Kitaabon",
                "Kitaabon",
            )).firstMatch
        XCTAssertTrue(kitaabon.appears(timeout: 10))
        XCUIElement.perform(withKeyModifiers: .command) { kitaabon.click() }
        app.typeKey("b", modifierFlags: [.command, .shift], in: app)
        _ = element(app, GuideAXID.setlistBreak)
        shoot("timeline", window, callouts: ["timeline": element(app, GuideAXID.setlistTimeline)])

        element(app, GuideAXID.setlistUnknown).click(in: app)
        let missing = element(app, GuideAXID.missingTimes)
        shoot("missing-times", window, callouts: ["list": missing])
        // The popover's tempo field may hold focus (Esc only leaves the field): close it from
        // its button.
        app.typeKey(.escape, modifierFlags: [], in: app)
        if !missing.disappears(timeout: 2) {
            element(app, GuideAXID.setlistUnknown).click(in: app)
        }
        XCTAssertTrue(missing.disappears(timeout: 10))

        let first = app.staticTexts.matching(identifier: GuideAXID.entryTitle).firstMatch
        first.click(in: app)
        element(app, GuideAXID.arrangementOpen).click(in: app)
        let sheet = element(app, GuideAXID.arrangementSheet)
        shoot("arrange-sheet", app.sheets.firstMatch.exists ? app.sheets.firstMatch : sheet)
        element(app, GuideAXID.arrangementDone).click(in: app)
        XCTAssertTrue(sheet.disappears(timeout: 10))

        element(app, GuideAXID.setlistStartShow).click(in: app)
        element(app, GuideAXID.checklistStart).click(in: app)
        XCTAssertTrue(app.staticTexts[GuideAXID.liveTitle].appears(timeout: 10))
        let breakView = app.descendants(matching: .any)[GuideAXID.liveBreak]
        for _ in 0 ..< 3 where !breakView.exists {
            app.typeKey(.rightArrow, modifierFlags: [], in: app)
            _ = breakView.appears(timeout: 2)
        }
        XCTAssertTrue(breakView.exists, "the stage never reached the break")
        shoot("stage-break", stageWindow(app), stage: true)
        endShow(app)
    }

    /// On stage (dark run only): checklist (both runs), stage, metronome, stage-search.
    @MainActor
    func testStage() {
        let app = launch()
        openSetlist(app, "Welcome Set")
        element(app, GuideAXID.setlistStartShow).click(in: app)
        let checklist = app.sheets.firstMatch
        XCTAssertTrue(checklist.appears(timeout: 10), "no pre-show checklist")
        shoot("checklist", checklist)
        element(app, GuideAXID.checklistStart).click(in: app)
        XCTAssertTrue(app.staticTexts[GuideAXID.liveTitle].appears(timeout: 10))
        let stage = stageWindow(app)
        shoot("stage", stage, stage: true)
        app.typeKey("m", modifierFlags: [], in: app)
        shoot("metronome", stage, stage: true)
        app.typeKey("m", modifierFlags: [], in: app)
        app.typeKey("k", modifierFlags: .command, in: app)
        XCTAssertTrue(element(app, GuideAXID.liveSearch).exists)
        app.typeText("kitabon")
        shoot("stage-search", stage, stage: true)
        app.typeKey(.escape, modifierFlags: [], in: app)
        endShow(app)
    }
}

/// Smart filters, the gig log and Settings (an extension only to keep the class body short).
@MainActor
extension GuideShots {
    /// Smart filters: filter-editor.
    func testSmartFilter() {
        let app = launch()
        _ = element(app, GuideAXID.songRow)
        element(app, GuideAXID.newSmartFilter).click(in: app)
        let sheet = app.sheets.firstMatch
        XCTAssertTrue(sheet.appears(timeout: 10), "no smart filter editor")
        let name = app.textFields[GuideAXID.smartFilterName]
        name.click(in: app)
        name.typeText("Gig ready", in: app)
        let tag = app.textFields[GuideAXID.tagField]
        tag.click(in: app)
        tag.typeText("folk\n", in: app)
        for field in ["Proficiency", "Key"] {
            // Each row's + inserts after itself: add after the last row.
            let adds = sheet.buttons.matching(identifier: GuideAXID.smartFilterAddRow)
            adds.element(boundBy: adds.count - 1).click(in: app)
            let pickers = sheet.popUpButtons.matching(identifier: GuideAXID.smartFilterField)
            let picker = pickers.element(boundBy: pickers.count - 1)
            picker.click(in: app)
            picker.menuItems[field].click(in: app)
        }
        for level in ["Ready", "Pro"] {
            sheet.buttons.matching(NSPredicate(format: "label == %@", level)).firstMatch
                .click(in: app)
        }
        let addKey = element(app, GuideAXID.smartFilterAddKey)
        addKey.click(in: app)
        addKey.menuItems["G"].click(in: app)
        shoot("filter-editor", sheet)
        app.typeKey(.escape, modifierFlags: [], in: app)
    }

    /// A show, then its gig log entry: gig-log (JamFest Opener leaves Kitaabon Wali Gali out,
    /// so asking for it is a real request).
    func testGigLog() {
        // A minute of show per second, so each played song lasts a few minutes.
        let app = launch(["-SegueClockRate", "60"])
        openSetlist(app, "JamFest Opener")
        element(app, GuideAXID.setlistStartShow).click(in: app)
        element(app, GuideAXID.checklistStart).click(in: app)
        XCTAssertTrue(app.staticTexts[GuideAXID.liveTitle].appears(timeout: 10))
        hold(3.2)
        app.typeKey(.rightArrow, modifierFlags: [], in: app)
        hold(0.4)
        app.typeKey("x", modifierFlags: [], in: app)
        app.typeKey("k", modifierFlags: .command, in: app)
        let field = app.textFields[GuideAXID.liveSearchField]
        XCTAssertTrue(field.appears(timeout: 10))
        field.typeText("kitabon", in: app)
        _ = element(app, GuideAXID.liveSearchResult)
        app.typeKey(.return, modifierFlags: .command, in: app)
        let note = app.textFields[GuideAXID.liveSearchNote]
        if note.appears(timeout: 3) {
            note.typeText("For Priya's birthday", in: app)
            app.typeKey(.return, modifierFlags: [], in: app)
        }
        hold(3.5)
        app.typeKey("r", modifierFlags: [], in: app)
        hold(4)
        for _ in 0 ..< 2 {
            app.typeKey(.rightArrow, modifierFlags: [], in: app)
            hold(3.6)
        }
        endShow(app)
        let discard = app.buttons[GuideAXID.reorderDiscard]
        if discard.appears(timeout: 5) {
            discard.click(in: app)
        }
        element(app, GuideAXID.sidebarGigLog).click(in: app)
        element(app, GuideAXID.gigLogRow).click(in: app)
        _ = element(app, GuideAXID.gigSummary)
        shoot("gig-log", mainWindow(app))
    }

    /// Settings panes: settings-live, settings-ai, settings-ai-installed, settings-privacy.
    func testSettings() {
        let app = launch()
        _ = element(app, GuideAXID.songRow)
        app.typeKey(",", modifierFlags: .command, in: app)
        let settings = app.windows.matching(NSPredicate(
            format: "identifier BEGINSWITH %@",
            "com_apple_SwiftUI_Settings",
        )).firstMatch
        XCTAssertTrue(settings.appears(timeout: 10), "Settings did not open")
        for (pane, id) in [
            ("Live", "settings-live"),
            ("AI", "settings-ai"),
            ("Privacy", "settings-privacy"),
        ] {
            settings.toolbars.buttons[pane].click(in: app)
            _ = settings.settles(timeout: 3)
            shoot(id, settings)
        }
        settings.toolbars.buttons["AI"].click(in: app)
        element(app, GuideAXID.modelDownload).click(in: app)
        let state = element(app, GuideAXID.modelState)
        XCTAssertTrue(
            E2E.waitUntil(timeout: 15) {
                ((state.value as? String ?? "") + state.label).contains("Downloaded")
            },
            "the scripted model never finished downloading",
        )
        _ = settings.settles(timeout: 3)
        shoot("settings-ai-installed", settings)
    }
}
