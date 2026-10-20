import AppKit
import XCTest

/// The user guide's screenshots (WS6 section 5), one test per area. Run by `make docs-shots`
/// (twice: dark, then light), never by `make e2e` or the gate. Shot ids match the
/// `<Shot id>` and `<Tile shot>` uses in guide/src/content/docs.
final class GuideShots: GuideShotCase {
    /// Library, song card and search: start-library, card, library-search.
    @MainActor
    func testLibrary() {
        let app = launch()
        let window = mainWindow(app)
        _ = element(app, GuideAXID.songRow)
        shoot("start-library", window)

        song(app, titled: "Kettle On, Lights Low").click(in: app)
        _ = element(app, GuideAXID.songCard)
        shoot("card", window, callouts: [
            "key": app.descendants(matching: .any)[GuideAXID.songCardKeyMode],
            "tempo": app.descendants(matching: .any)[GuideAXID.songCardTempo],
            "length": app.descendants(matching: .any)[GuideAXID.songCardLength],
        ])

        let search = element(app, GuideAXID.librarySearch)
        search.click(in: app)
        search.typeText("kitabon", in: app)
        _ = song(app, titled: "Kitaabon Wali Gali")
        shoot("library-search", window)
    }

    /// The editor: editor-visual, transpose.
    @MainActor
    func testEditor() {
        let app = launch()
        song(app, titled: "Kettle On, Lights Low").click(in: app)
        element(app, GuideAXID.editSong).click(in: app)
        let window = mainWindow(app)
        _ = element(app, GuideAXID.editorVisual)
        shoot("editor-visual", window)
        let up = element(app, GuideAXID.editorTransposeUp)
        up.click(in: app)
        up.click(in: app)
        shoot("transpose", window)
    }

    /// New Song and paste: new-song, paste-review.
    @MainActor
    func testNewSongAndPaste() {
        let app = launch()
        element(app, GuideAXID.newSong).click(in: app)
        let sheet = app.sheets.firstMatch
        XCTAssertTrue(sheet.appears(timeout: 10), "New Song opened no sheet")
        shoot("new-song", sheet)
        app.typeKey(.escape, modifierFlags: [], in: app)
        XCTAssertTrue(sheet.disappears(timeout: 10))

        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(GuideFixtures.chordSitePaste, forType: .string)
        _ = element(app, GuideAXID.songRow)
        app.typeKey("v", modifierFlags: [.command, .option], in: app)
        let review = element(app, GuideAXID.pasteSheet)
        _ = review.settles(timeout: 5)
        shoot("paste-review", app.sheets.firstMatch.exists ? app.sheets.firstMatch : review)
        element(app, GuideAXID.pasteCancel).click(in: app)
    }

    /// The set builder and the assistant: builder-pick, builder-arrange, assistant-bar.
    @MainActor
    func testSetBuilder() {
        let app = launch()
        let window = mainWindow(app)
        openWelcomeSet(app)
        app.typeKey("1", modifierFlags: .command, in: app)
        shoot("builder-pick", window)
        app.typeKey("2", modifierFlags: .command, in: app)
        shoot("builder-arrange", window)
        let field = element(app, GuideAXID.assistantField)
        field.click(in: app)
        field.typeText("20 min, songs I know well, no ballads", in: app)
        shoot("assistant-bar", element(app, GuideAXID.assistantBar))
    }

    /// On stage (dark run only): checklist (both runs), stage, metronome, stage-search.
    @MainActor
    func testStage() {
        let app = launch()
        openWelcomeSet(app)
        element(app, GuideAXID.setlistStartShow).click(in: app)
        let checklist = app.sheets.firstMatch
        XCTAssertTrue(checklist.appears(timeout: 10), "no pre-show checklist")
        shoot("checklist", checklist)
        element(app, GuideAXID.checklistStart).click(in: app)
        XCTAssertTrue(app.staticTexts[GuideAXID.liveTitle].appears(timeout: 10))
        let stage = app.windows.matching(NSPredicate(format: "title == %@", "Perform")).firstMatch
        XCTAssertTrue(stage.appears(timeout: 10), "the stage window is missing")
        shoot("stage", stage, stage: true)
        app.typeKey("m", modifierFlags: [], in: app)
        shoot("metronome", stage, stage: true)
        app.typeKey("m", modifierFlags: [], in: app)
        app.typeKey("k", modifierFlags: .command, in: app)
        XCTAssertTrue(element(app, GuideAXID.liveSearch).exists)
        app.typeText("kitabon")
        shoot("stage-search", stage, stage: true)
        app.typeKey(.escape, modifierFlags: [], in: app)
        app.typeKey(".", modifierFlags: .command, in: app)
        XCTAssertTrue(element(app, GuideAXID.liveEndDialog).exists)
        app.typeKey(.return, modifierFlags: [], in: app)
    }

    /// Settings panes: settings-live, settings-ai, settings-privacy.
    @MainActor
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
    }

    // MARK: - Helpers

    /// A library row whose label starts with `title`.
    @MainActor
    func song(_ app: XCUIApplication, titled title: String) -> XCUIElement {
        let row = app.descendants(matching: .any).matching(identifier: GuideAXID.songRow)
            .matching(NSPredicate(format: "label BEGINSWITH %@", title)).firstMatch
        XCTAssertTrue(row.appears(timeout: 15), "no song row \(title)")
        return row
    }

    /// Opens the Welcome Set in the set builder.
    @MainActor
    func openWelcomeSet(_ app: XCUIApplication) {
        element(app, GuideAXID.setlistRow).click(in: app)
    }
}

/// Text the captures use. Original lyrics only: the Welcome song "Kettle On, Lights Low",
/// laid out as a chord site would show it (header, chords over lyrics, menu junk).
enum GuideFixtures {
    static let chordSitePaste = """
    Kettle On, Lights Low Chords by Segue Originals
    Transpose  -1  +1
    Capo 3

    [Verse 1]
    G          Cadd9
    Kettle on, lights low,
    G              D/F#
    Rain on the window glass,
    Em7            Cadd9
    Nowhere we need to go,
    G       D       G
    Let the evening pass.

    [Chorus]
    Cadd9         G
    Turn, turn, round the room,
    Cadd9            D
    Slow as the clock can go,
    Em7        Cadd9          G
    One more waltz for the afternoon,
    Am7      D          G
    Kettle on, lights low.
    """
}
