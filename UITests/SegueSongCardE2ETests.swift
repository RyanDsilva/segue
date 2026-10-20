import XCTest

/// The song card and Text mode's slash menu through the real UI (P3-10, R80, R81), on a
/// fresh Welcome library: set key, tempo and length on a song from the card's tokens, see
/// the directives in Text mode, then wrap two typed lines in a Chorus with `/cho` + Return.
final class SegueSongCardE2ETests: XCTestCase {
    private var app: XCUIApplication?
    private var library: WelcomeLibrary?

    override func setUpWithError() throws {
        continueAfterFailure = false
        library = try WelcomeLibrary()
    }

    override func tearDownWithError() throws {
        E2E.terminate(app)
        if let root = library?.root {
            try? FileManager.default.removeItem(at: root)
        }
    }

    @MainActor
    func testCardWritesDirectivesAndSlashWrapsAChorus() throws {
        let library = try XCTUnwrap(library)
        let app = XCUIApplication()
        self.app = app
        E2E.launch(app, arguments: library.arguments(["-SegueSeedWelcome", "YES"]))
        let row = app.descendants(matching: .any).matching(identifier: SongCardAXID.songRow)
            .matching(NSPredicate(format: "label BEGINSWITH %@", "Kettle On")).firstMatch
        XCTAssertTrue(row.appears(timeout: 15), "no Welcome song row")
        row.click(in: app)

        // Key: open the token, switch to Minor (the picker opens on the current key's mode,
        // Kettle On is in G major), pick Em.
        element(app, SongCardAXID.token("key")).click(in: app)
        let minor = app.radioButtons["Minor"].firstMatch
        XCTAssertTrue(minor.appears(timeout: 5), "no Major / Minor switch")
        minor.click(in: app)
        let em = app.descendants(matching: .any).matching(identifier: SongCardAXID.keyOption)
            .matching(NSPredicate(format: "label == %@", "Em")).firstMatch
        XCTAssertTrue(em.appears(timeout: 5), "no key picker")
        em.click(in: app)
        XCTAssertTrue(waitForFile(library, contains: "{key: Em}"))

        // Tempo: type 100 and Return.
        element(app, SongCardAXID.token("tempo")).click(in: app)
        let tempo = element(app, SongCardAXID.tempo)
        XCTAssertTrue(tempo.appears(timeout: 5), "no tempo field")
        tempo.typeKey("a", modifierFlags: .command, in: app)
        tempo.typeText("100\n", in: app)
        XCTAssertTrue(waitForFile(library, contains: "{tempo: 100}"))

        // Length: type 4:10 and Return.
        element(app, SongCardAXID.token("length")).click(in: app)
        let length = element(app, SongCardAXID.length)
        XCTAssertTrue(length.appears(timeout: 5), "no length field")
        length.typeKey("a", modifierFlags: .command, in: app)
        length.typeText("4:10\n", in: app)
        XCTAssertTrue(waitForFile(library, contains: "{duration: 4:10}"))
        app.typeKey(.escape, modifierFlags: [], in: app)

        // Text mode shows the directives.
        element(app, SongCardAXID.editSong).click(in: app)
        element(app, SongCardAXID.editorModeText).click(in: app)
        let editor = app.textViews[SongCardAXID.editorText]
        XCTAssertTrue(editor.appears(timeout: 5))
        let text = editor.value as? String ?? ""
        for directive in ["{key: Em}", "{tempo: 100}", "{duration: 4:10}"] {
            XCTAssertTrue(text.contains(directive), "\(directive) missing from:\n\(text)")
        }

        slashWrapsAChorus(app, editor: editor)
    }

    /// `/cho` + Return on two typed lines wraps them in a Chorus.
    @MainActor
    private func slashWrapsAChorus(_ app: XCUIApplication, editor: XCUIElement) {
        // Kettle On already has a chorus, so under the section numbering rule (P3-11) the
        // new one, below it, is Chorus 2 and the existing one becomes Chorus 1 in the same
        // undo step.
        editor.click(in: app)
        editor.typeKey(.downArrow, modifierFlags: .command, in: app)
        editor.typeText("\nLa la one\nLa la two", in: app)
        editor.typeKey(.upArrow, modifierFlags: .shift, in: app)
        editor.typeKey(.leftArrow, modifierFlags: [.command, .shift], in: app)
        editor.typeText("/cho", in: app)
        let menu = element(app, SongCardAXID.slashMenu)
        XCTAssertTrue(menu.appears(timeout: 5), "no slash menu")
        editor.typeKey(.return, modifierFlags: [], in: app)
        XCTAssertTrue(E2E.waitUntil {
            let value = editor.value as? String ?? ""
            return value.contains("{start_of_chorus: Chorus 1}\n")
                && value
                .contains("{start_of_chorus: Chorus 2}\nLa la one\nLa la two\n{end_of_chorus}")
        }, "no chorus in:\n\(editor.value as? String ?? "")")
    }

    @MainActor
    private func element(_ app: XCUIApplication, _ identifier: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    private func waitForFile(_ library: WelcomeLibrary, contains text: String) -> Bool {
        E2E.waitUntil {
            let file = library.songs.appending(path: "kettle-on-lights-low.cho")
            return ((try? String(contentsOf: file, encoding: .utf8)) ?? "").contains(text)
        }
    }
}

/// Identifiers the song card E2E uses (mirrors `AccessibilityID` in SegueUI).
enum SongCardAXID {
    static let songRow = "segue.library.row"
    static let keyOption = "segue.songCard.keyOption"
    static let tempo = "segue.songCard.tempo"
    static let length = "segue.songCard.length"
    static let editSong = "segue.song.edit"
    static let editorModeText = "segue.editor.mode.text"
    static let editorText = "segue.editor.text"
    static let slashMenu = "segue.editor.slashMenu"

    static func token(_ field: String) -> String {
        "segue.songCard.token.\(field)"
    }
}
