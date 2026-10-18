import AppKit
import XCTest

/// Phase 1 editor E2E (docs/phases/1-editor-and-music-theory.md, "UI E2E"), driven through
/// the real UI on a fresh temp library per test:
///
/// - create a song in text mode with `{` directive and `[` chord autocomplete, with every
///   automatic text substitution off;
/// - visual mode: click a syllable to add a chord, drag another, undo, cursor mapping both
///   ways, back to the exact source;
/// - capo / transpose / Nashville toggles change the rendered chords, and Nashville view
///   takes chord input as numbers;
/// - a custom shape lands as `{define}` in the file on disk;
/// - "Apply transposition to source" flags the custom shape;
/// - closing and quitting right after typing save without asking (autosave, R17);
/// - typing stays under 16 ms per keystroke on a 200-line song.
final class SegueEditorE2ETests: XCTestCase {
    var libraryRoot: URL?
    var app: XCUIApplication?

    override func setUpWithError() throws {
        continueAfterFailure = false
        let root = URL(filePath: "/private/tmp/segue-e2e", directoryHint: .isDirectory)
            .appending(path: "editor-\(UUID().uuidString)", directoryHint: .isDirectory)
        try? FileManager.default.removeItem(at: root)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        libraryRoot = root
    }

    override func tearDownWithError() throws {
        E2E.terminate(app)
        if let libraryRoot {
            try? FileManager.default.removeItem(at: libraryRoot)
        }
    }

    // MARK: - Tests

    @MainActor
    func testEditorFlow() throws {
        // The light UI is the brand's primary appearance (dark is covered below).
        let app = try launch(extraArguments: ["-NSRequiresAquaSystemAppearance", "YES"])
        createSongWithAutocomplete(app)
        editInVisualMode(app)
        toggleDisplayOptions(app)
        addCustomShape(app)
        finishEditing(app)
        try assertFileContains(["{define: G ", "[Em]hai"])
        applyTranspositionToSource(app)
        finishEditing(app)
        try assertFileContains(["{key: A}", "{capo: 2}", "[D]Dil", "{define: G "])
    }

    /// The visual editor's gestures (B2: one scenario, both on a fresh song in the light
    /// appearance): pill gestures, then Nashville number entry on a second song.
    @MainActor
    func testVisualEditorGestures() throws {
        let app = try launch(extraArguments: ["-NSRequiresAquaSystemAppearance", "YES"])
        pillGestures(app)
        nashvilleNumberEntry(app)
    }

    /// Pill gestures: select + Backspace deletes, ← → nudges, Option-drag duplicates; all
    /// on the shared undo stack.
    @MainActor
    private func pillGestures(_ app: XCUIApplication) {
        element(app, EditorAXID.newSong).click(in: app)
        let editor = app.textViews[EditorAXID.editorText]
        XCTAssertTrue(editor.appears(timeout: 10))
        editor.click(in: app)
        editor.typeText(EditorFixture.gestures, in: app)
        app.typeKey(.escape, modifierFlags: [], in: app)
        switchMode(app, to: .visual)
        XCTAssertTrue(wait { self.pillLabels(app) == ["Am", "F"] }, "\(pillLabels(app))")

        // Select F, Backspace deletes it; undo restores it.
        pill(app, "F").click(in: app)
        attachScreenshot(app, name: "pill-selected")
        app.typeKey(.delete, modifierFlags: [], in: app)
        XCTAssertTrue(wait { self.pillLabels(app) == ["Am"] }, "\(pillLabels(app))")
        app.typeKey("z", modifierFlags: .command, in: app)
        if !wait({ self.pillLabels(app) == ["Am", "F"] }) {
            switchMode(app, to: .text)
            XCTFail("Undo after delete: \(editor.value as? String ?? "")")
        }

        // Select Am, nudge right twice: "[Am]Dil" -> "Di[Am]l"... i.e. two characters on.
        pill(app, "Am").click(in: app)
        app.typeKey(.rightArrow, modifierFlags: [], in: app)
        app.typeKey(.rightArrow, modifierFlags: [], in: app)
        app.typeKey(.escape, modifierFlags: [], in: app)

        // Option-drag F onto "raah": a copy, the original stays.
        let from = pill(app, "F").coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        let to = lane(app, "raah").coordinate(withNormalizedOffset: CGVector(dx: 0.05, dy: 0.5))
        XCUIElement.perform(withKeyModifiers: .option) {
            from.press(forDuration: 0.3, thenDragTo: to, in: app)
        }
        XCTAssertTrue(wait { self.pillLabels(app) == ["Am", "F", "F"] }, "\(pillLabels(app))")
        attachScreenshot(app, name: "pill-duplicated")
        switchMode(app, to: .text)
        XCTAssertTrue(
            waitForValue(editor, EditorFixture.gesturesAfter),
            editor.value as? String ?? "",
        )
    }

    /// Nashville view accepts numbers in the chord popover; the source gets letters. A new
    /// song started from the open editor (which saves it first).
    @MainActor
    private func nashvilleNumberEntry(_ app: XCUIApplication) {
        element(app, EditorAXID.newSong).click(in: app)
        let editor = app.textViews[EditorAXID.editorText]
        XCTAssertTrue(editor.appears(timeout: 10))
        XCTAssertTrue(wait { (editor.value as? String)?.isEmpty == true }, "not a new song")
        editor.click(in: app)
        editor.typeText(EditorFixture.gestures, in: app)
        app.typeKey(.escape, modifierFlags: [], in: app)
        element(app, EditorAXID.editorNashville).click(in: app)
        switchMode(app, to: .visual)
        XCTAssertTrue(wait { self.pillLabels(app) == ["6m", "4"] }, "\(pillLabels(app))")

        lane(app, "raah").coordinate(withNormalizedOffset: CGVector(dx: 0.1, dy: 0.5))
            .click(in: app)
        let field = app.textFields[EditorAXID.editorChordField]
        XCTAssertTrue(field.appears(timeout: 5), "No chord popover")
        field.typeText("5", in: app)
        attachScreenshot(app, name: "nashville-number-entry")
        app.typeKey(.return, modifierFlags: [], in: app)
        XCTAssertTrue(wait { self.pillLabels(app) == ["6m", "5", "4"] }, "\(pillLabels(app))")
        switchMode(app, to: .text)
        XCTAssertTrue(
            waitForValue(editor, EditorFixture.gesturesNashville),
            editor.value as? String ?? "",
        )
    }

    @MainActor
    func testCloseAndQuitSaveWithoutAsking() throws {
        let app = try launch()
        element(app, EditorAXID.newSong).click(in: app)
        let editor = app.textViews[EditorAXID.editorText]
        XCTAssertTrue(editor.appears(timeout: 10))
        editor.click(in: app)
        editor.typeText("{title: Unsaved}\n", in: app)

        // Close the window right after typing: no prompt, the edit is saved (autosave, R17).
        app.typeKey("w", modifierFlags: .command, in: app)
        XCTAssertTrue(editor.disappears(timeout: 10), "The window did not close")
        XCTAssertFalse(app.sheets.firstMatch.exists, "Closing must not ask")
        try assertFileContains(["{title: Unsaved}"])
        XCTAssertEqual(app.state, .runningForeground)

        // Quit: no prompt, the app quits.
        E2E.quitting { app.typeKey("q", modifierFlags: .command, in: app) }
        XCTAssertTrue(app.reaches(.notRunning, timeout: 15), "App did not quit")
    }

    @MainActor
    func testKeystrokeLatencyOn200LineSong() throws {
        let app = try launch()
        element(app, EditorAXID.newSong).click(in: app)
        let editor = app.textViews[EditorAXID.editorText]
        XCTAssertTrue(editor.appears(timeout: 10))
        editor.click(in: app)
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(EditorFixture.longSong(lines: 200), forType: .string)
        app.typeKey("v", modifierFlags: .command, in: app)
        XCTAssertTrue(wait { (editor.value as? String)?.contains("Line 198 of the") == true })
        // Measure fresh: type into the middle of the song.
        app.typeKey(.upArrow, modifierFlags: .command, in: app)
        for _ in 0 ..< 100 {
            app.typeKey(.downArrow, modifierFlags: [], in: app)
        }
        let stats = element(app, EditorAXID.editorKeystrokeStats)
        let before = Self.keystrokeCount(stats)
        editor.typeText("tum hi ho [G]pyaar ki raah pe chalte chalte ", in: app)
        XCTAssertTrue(wait { Self.keystrokeCount(stats) >= before + 40 })
        attachScreenshot(app, name: "long-song-text")
        assertTypingFast(stats, mode: "Text")

        // Visual mode: typing lyrics goes through the tree editor and re-projection. As in
        // text mode, type enough (45 keystrokes) that p95 describes typing: the first key
        // event after the mode switch carries a one-off warm-up of the canvas text input
        // (about 10 ms), which the two-frame `max` bound covers but must not set p95 alone.
        element(app, EditorAXID.editorModeVisual).click(in: app)
        let canvas = app.textViews[EditorAXID.editorVisual]
        XCTAssertTrue(canvas.appears(timeout: 10))
        let visualBefore = Self.keystrokeCount(stats)
        canvas.typeText("dil se dil tak, tum hi ho pyaar ki raah pe chalte ", in: app)
        XCTAssertTrue(wait { Self.keystrokeCount(stats) >= visualBefore + 45 })
        attachScreenshot(app, name: "long-song-visual")
        assertTypingFast(stats, mode: "Visual")
    }

    @MainActor
    func testDarkAppearance() throws {
        let app = try launch(extraArguments: ["-AppleInterfaceStyle", "Dark"])
        element(app, EditorAXID.newSong).click(in: app)
        let editor = app.textViews[EditorAXID.editorText]
        XCTAssertTrue(editor.appears(timeout: 10))
        editor.click(in: app)
        editor.typeText(EditorFixture.darkSong, in: app)
        app.typeKey(.escape, modifierFlags: [], in: app)
        attachScreenshot(app, name: "dark-text")
        element(app, EditorAXID.editorModeVisual).click(in: app)
        XCTAssertTrue(app.textViews[EditorAXID.editorVisual].appears(timeout: 10))
        let pill = pills(app).firstMatch
        XCTAssertTrue(pill.appears(timeout: 5))
        pill.click(in: app)
        attachScreenshot(app, name: "dark-visual")
    }

    override func record(_ issue: XCTIssue) {
        nonisolated(unsafe) var issue = issue
        if MainActor.assumeIsolated({ E2E.isExpectedExit(issue) }) {
            return
        }
        let app = app
        MainActor.assumeIsolated {
            for attachment in E2E.failureAttachments(for: app) {
                issue.add(attachment)
            }
        }
        super.record(issue)
    }
}
