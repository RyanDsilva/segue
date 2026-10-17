import AppKit
import XCTest

/// Phase 1 editor E2E (docs/phases/1-editor-and-music-theory.md, "UI E2E"), driven through
/// the real UI on a fresh temp library per test:
///
/// - create a song in text mode with `{` directive and `[` chord autocomplete, with every
///   automatic text substitution off;
/// - visual mode: click a syllable to add a chord, drag another, undo, cursor mapping both
///   ways, back to the exact source;
/// - capo / transpose / Nashville toggles change the rendered chords;
/// - a custom shape lands as `{define}` in the file on disk;
/// - "Apply transposition to source" flags the custom shape;
/// - quitting / closing with unsaved edits prompts;
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
        let app = app
        MainActor.assumeIsolated {
            if let app, app.state != .notRunning {
                app.terminate()
            }
        }
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
        saveEditor(app)
        try assertFileContains(["{define: G ", "[Em]hai"])
        applyTranspositionToSource(app)
        saveEditor(app)
        try assertFileContains(["{key: A}", "{capo: 2}", "[D]Dil", "{define: G "])
    }

    /// Pill gestures: select + Backspace deletes, ← → nudges, Option-drag duplicates; all
    /// on the shared undo stack.
    @MainActor
    func testPillGestures() throws {
        let app = try launch(extraArguments: ["-NSRequiresAquaSystemAppearance", "YES"])
        element(app, EditorAXID.newSong).click()
        let editor = app.textViews[EditorAXID.editorText]
        XCTAssertTrue(editor.waitForExistence(timeout: 10))
        editor.click()
        editor.typeText(EditorFixture.gestures)
        app.typeKey(.escape, modifierFlags: [])
        switchMode(app, to: .visual)
        XCTAssertTrue(wait { self.pillLabels(app) == ["Am", "F"] }, "\(pillLabels(app))")

        // Select F, Backspace deletes it; undo restores it.
        pill(app, "F").click()
        attachScreenshot(app, name: "pill-selected")
        app.typeKey(.delete, modifierFlags: [])
        XCTAssertTrue(wait { self.pillLabels(app) == ["Am"] }, "\(pillLabels(app))")
        app.typeKey("z", modifierFlags: .command)
        if !wait({ self.pillLabels(app) == ["Am", "F"] }) {
            switchMode(app, to: .text)
            XCTFail("Undo after delete: \(editor.value as? String ?? "")")
        }

        // Select Am, nudge right twice: "[Am]Dil" -> "Di[Am]l"... i.e. two characters on.
        pill(app, "Am").click()
        app.typeKey(.rightArrow, modifierFlags: [])
        app.typeKey(.rightArrow, modifierFlags: [])
        app.typeKey(.escape, modifierFlags: [])

        // Option-drag F onto "raah": a copy, the original stays.
        let from = pill(app, "F").coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        let to = lane(app, "raah").coordinate(withNormalizedOffset: CGVector(dx: 0.05, dy: 0.5))
        XCUIElement.perform(withKeyModifiers: .option) {
            from.press(forDuration: 0.3, thenDragTo: to)
        }
        XCTAssertTrue(wait { self.pillLabels(app) == ["Am", "F", "F"] }, "\(pillLabels(app))")
        attachScreenshot(app, name: "pill-duplicated")
        switchMode(app, to: .text)
        XCTAssertTrue(
            waitForValue(editor, EditorFixture.gesturesAfter),
            editor.value as? String ?? "",
        )
    }

    @MainActor
    func testUnsavedEditsPromptOnCloseAndQuit() throws {
        let app = try launch()
        element(app, EditorAXID.newSong).click()
        let editor = app.textViews[EditorAXID.editorText]
        XCTAssertTrue(editor.waitForExistence(timeout: 10))
        editor.click()
        editor.typeText("{title: Unsaved}\n")

        // Close the window: prompt, Cancel keeps everything.
        app.typeKey("w", modifierFlags: .command)
        let cancel = promptButton(app, "Cancel")
        XCTAssertTrue(cancel.waitForExistence(timeout: 5), "No prompt on window close")
        attachScreenshot(app, name: "close-prompt")
        cancel.click()
        XCTAssertTrue(editor.waitForExistence(timeout: 5))
        XCTAssertEqual(editor.value as? String, "{title: Unsaved}\n")

        // Quit: prompt, Cancel keeps the app running.
        app.typeKey("q", modifierFlags: .command)
        let cancelQuit = promptButton(app, "Cancel")
        XCTAssertTrue(cancelQuit.waitForExistence(timeout: 5), "No prompt on quit")
        attachScreenshot(app, name: "quit-prompt")
        cancelQuit.click()
        XCTAssertTrue(editor.waitForExistence(timeout: 5))
        XCTAssertEqual(app.state, .runningForeground)

        // Quit again and save: the song is written, then the app quits.
        app.typeKey("q", modifierFlags: .command)
        let save = promptButton(app, "Save")
        XCTAssertTrue(save.waitForExistence(timeout: 5))
        save.click()
        XCTAssertTrue(app.wait(for: .notRunning, timeout: 15), "App did not quit after Save")
        try assertFileContains(["{title: Unsaved}"])
    }

    @MainActor
    func testKeystrokeLatencyOn200LineSong() throws {
        let app = try launch()
        element(app, EditorAXID.newSong).click()
        let editor = app.textViews[EditorAXID.editorText]
        XCTAssertTrue(editor.waitForExistence(timeout: 10))
        editor.click()
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(EditorFixture.longSong(lines: 200), forType: .string)
        app.typeKey("v", modifierFlags: .command)
        XCTAssertTrue(wait { (editor.value as? String)?.contains("Line 198 of the") == true })
        // Measure fresh: type into the middle of the song.
        app.typeKey(.upArrow, modifierFlags: .command)
        for _ in 0 ..< 100 {
            app.typeKey(.downArrow, modifierFlags: [])
        }
        let stats = element(app, EditorAXID.editorKeystrokeStats)
        let before = Self.keystrokeCount(stats)
        editor.typeText("tum hi ho [G]pyaar ki raah pe chalte chalte ")
        XCTAssertTrue(wait { Self.keystrokeCount(stats) >= before + 40 })
        attachScreenshot(app, name: "long-song-text")
        assertTypingFast(stats, mode: "Text")

        // Visual mode: typing lyrics goes through the tree editor and re-projection.
        element(app, EditorAXID.editorModeVisual).click()
        let canvas = app.textViews[EditorAXID.editorVisual]
        XCTAssertTrue(canvas.waitForExistence(timeout: 10))
        let visualBefore = Self.keystrokeCount(stats)
        canvas.typeText("dil se dil tak ")
        XCTAssertTrue(wait { Self.keystrokeCount(stats) >= visualBefore + 15 })
        attachScreenshot(app, name: "long-song-visual")
        assertTypingFast(stats, mode: "Visual")
    }

    @MainActor
    func testDarkAppearance() throws {
        let app = try launch(extraArguments: ["-AppleInterfaceStyle", "Dark"])
        element(app, EditorAXID.newSong).click()
        let editor = app.textViews[EditorAXID.editorText]
        XCTAssertTrue(editor.waitForExistence(timeout: 10))
        editor.click()
        editor.typeText(EditorFixture.darkSong)
        app.typeKey(.escape, modifierFlags: [])
        attachScreenshot(app, name: "dark-text")
        element(app, EditorAXID.editorModeVisual).click()
        XCTAssertTrue(app.textViews[EditorAXID.editorVisual].waitForExistence(timeout: 10))
        let pill = pills(app).firstMatch
        XCTAssertTrue(pill.waitForExistence(timeout: 5))
        pill.click()
        attachScreenshot(app, name: "dark-visual")
    }

    override func record(_ issue: XCTIssue) {
        nonisolated(unsafe) var issue = issue
        if let app {
            MainActor.assumeIsolated {
                issue.add(XCTAttachment(screenshot: app.screenshot()))
                issue.add(XCTAttachment(string: app.debugDescription))
            }
        }
        super.record(issue)
    }
}
