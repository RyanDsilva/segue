import AppKit
import XCTest

// Queries, waits and fixtures for `SegueEditorE2ETests`.

extension SegueEditorE2ETests {
    // MARK: - Helpers

    /// A fresh app instance on this test's clean temp library, frontmost and showing the
    /// empty library.
    @MainActor
    func launch(extraArguments: [String] = []) throws -> XCUIApplication {
        let root = try XCTUnwrap(libraryRoot)
        let app = XCUIApplication()
        self.app = app
        E2E.launch(app, arguments: [
            "-SegueLibraryPath", root.path(percentEncoded: false),
            "-SegueResetState", "YES",
        ] + extraArguments)
        XCTAssertTrue(element(app, EditorAXID.libraryEmpty).waitForExistence(timeout: 15))
        return app
    }

    enum EditorMode {
        case text
        case visual
    }

    @MainActor
    func switchMode(_ app: XCUIApplication, to mode: EditorMode) {
        switch mode {
        case .text:
            element(app, EditorAXID.editorModeText).click(in: app)
            XCTAssertTrue(app.textViews[EditorAXID.editorText].waitForExistence(timeout: 5))
        case .visual:
            element(app, EditorAXID.editorModeVisual).click(in: app)
            XCTAssertTrue(app.textViews[EditorAXID.editorVisual].waitForExistence(timeout: 5))
        }
    }

    @MainActor
    func element(_ app: XCUIApplication, _ identifier: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    @MainActor
    func completionChips(_ app: XCUIApplication) -> XCUIElementQuery {
        app.descendants(matching: .any).matching(identifier: EditorAXID.editorCompletion)
    }

    @MainActor
    func pills(_ app: XCUIApplication) -> XCUIElementQuery {
        app.descendants(matching: .any).matching(identifier: EditorAXID.editorPill)
    }

    @MainActor
    func pillLabels(_ app: XCUIApplication) -> [String] {
        pills(app).allElementsBoundByIndex.map(\.label)
    }

    @MainActor
    func pill(_ app: XCUIApplication, _ label: String) -> XCUIElement {
        pills(app).matching(NSPredicate(format: "label == %@", label)).firstMatch
    }

    @MainActor
    func lane(_ app: XCUIApplication, _ word: String) -> XCUIElement {
        let lane = app.descendants(matching: .any).matching(identifier: EditorAXID.editorLane)
            .matching(NSPredicate(format: "label == %@", word)).firstMatch
        XCTAssertTrue(lane.waitForExistence(timeout: 5), "No chord slot over \(word)")
        return lane
    }

    @MainActor
    func previewChords(_ app: XCUIApplication) -> [String] {
        element(app, EditorAXID.editorPreview).staticTexts
            .matching(identifier: EditorAXID.sheetChord)
            .allElementsBoundByIndex.compactMap { $0.value as? String }
    }

    @MainActor
    func promptButton(_ app: XCUIApplication, _ title: String) -> XCUIElement {
        app.sheets.buttons[title].firstMatch
    }

    @MainActor
    static func text(_ element: XCUIElement) -> String {
        element.label.isEmpty ? (element.value as? String ?? "") : element.label
    }

    /// "n=40 max=3.10ms mean=1.20ms" -> 40.
    @MainActor
    static func keystrokeCount(_ element: XCUIElement) -> Int {
        let value = element.label
        guard let range = value.range(of: #"n=(\d+)"#, options: .regularExpression)
        else { return 0 }
        return Int(value[range].dropFirst(2)) ?? 0
    }

    /// A field of the stats label, in ms ("p95", "max").
    @MainActor
    static func keystrokeStat(_ name: String, _ element: XCUIElement) -> Double {
        let value = element.label
        guard let range = value.range(of: name + #"=[0-9.]+"#, options: .regularExpression) else {
            return .infinity
        }
        return Double(value[range].dropFirst(name.count + 1)) ?? .infinity
    }

    /// p95 under one 60 Hz frame; no keystroke over two (first-keystroke cache warm-up in
    /// a Debug build on a shared machine stays under that).
    @MainActor
    func assertTypingFast(_ stats: XCUIElement, mode: String) {
        let p95 = Self.keystrokeStat("p95", stats)
        let max = Self.keystrokeStat("max", stats)
        XCTAssertLessThan(p95, 16, "\(mode) keystroke p95 \(p95) ms: \(stats.label)")
        XCTAssertLessThan(max, 33, "\(mode) keystroke max \(max) ms: \(stats.label)")
        let attachment = XCTAttachment(string: "\(mode): \(stats.label)")
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func wait(timeout: TimeInterval = 10, _ condition: @escaping () -> Bool) -> Bool {
        let predicate = NSPredicate { _, _ in condition() }
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: nil)
        return XCTWaiter().wait(for: [expectation], timeout: timeout) == .completed
    }

    func waitForValue(_ element: XCUIElement, _ value: String) -> Bool {
        let predicate = NSPredicate(format: "value == %@", value)
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: element)
        return XCTWaiter().wait(for: [expectation], timeout: 10) == .completed
    }

    /// The one `.cho` in the library contains every snippet.
    func assertFileContains(_ snippets: [String]) throws {
        let songs = try XCTUnwrap(libraryRoot).appending(path: "songs", directoryHint: .isDirectory)
        let files = try FileManager.default.contentsOfDirectory(atPath: songs.path)
            .filter { $0.hasSuffix(".cho") }
        XCTAssertEqual(files.count, 1, "songs/: \(files)")
        let file = try XCTUnwrap(files.first)
        let source = try String(contentsOf: songs.appending(path: file), encoding: .utf8)
        for snippet in snippets {
            XCTAssertTrue(source.contains(snippet), "\(file) lacks \(snippet):\n\(source)")
        }
    }

    @MainActor
    func attachScreenshot(_ app: XCUIApplication, name: String) {
        let window = app.windows.firstMatch
        let screenshot = window.exists ? window.screenshot() : app.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}

/// Accessibility identifiers (mirrors `AccessibilityID` in SegueUI).
enum EditorAXID {
    static let newSong = "segue.library.newSong"
    static let libraryEmpty = "segue.library.empty"
    static let songTitle = "segue.song.title"
    static let editSong = "segue.song.edit"
    static let editorText = "segue.editor.text"
    static let editorSave = "segue.editor.save"
    static let editorPreview = "segue.editor.preview"
    static let editorModeText = "segue.editor.mode.text"
    static let editorModeVisual = "segue.editor.mode.visual"
    static let editorVisual = "segue.editor.visual"
    static let editorPill = "segue.editor.pill"
    static let editorLane = "segue.editor.lane"
    static let editorChordField = "segue.editor.chordPopover.field"
    static let editorCompletion = "segue.editor.completion"
    static let editorTransposeDown = "segue.editor.transpose.down"
    static let editorTransposeUp = "segue.editor.transpose.up"
    static let editorTransposeValue = "segue.editor.transpose.value"
    static let editorCapoUp = "segue.editor.capo.up"
    static let editorCapoValue = "segue.editor.capo.value"
    static let editorShapes = "segue.editor.display.shapes"
    static let editorConcert = "segue.editor.display.concert"
    static let editorNashville = "segue.editor.display.nashville"
    static let editorDiagramsToggle = "segue.editor.diagrams"
    static let editorApplyTransposition = "segue.editor.applyTransposition"
    static let editorFlaggedDefines = "segue.editor.flaggedDefines"
    static let editorCursor = "segue.editor.status.cursor"
    static let editorKeystrokeStats = "segue.editor.status.keystrokes"
    static let editorInputSettings = "segue.editor.status.inputSettings"
    static let sheetChord = "segue.sheet.chord"
    static let guitarDiagram = "segue.diagrams.guitar"
    static let shapeEditorSave = "segue.diagrams.shapeEditor.save"
}

/// Songs typed in the E2E run. Original text written for this test (licence-free).
enum EditorFixture {
    static let typed = """
    {title: Raah Test}
    {key: G}

    {start_of_verse}
    [C]Dil ki baat. hai "sach" -- [G]teh
    {end_of_verse}

    """

    static let withEm = typed.replacingOccurrences(of: "hai", with: "[Em]hai")
    static let afterDrag = withEm.replacingOccurrences(of: "[C]Dil ki", with: "Dil [C]ki")

    static let gestures = """
    {key: Am}
    {start_of_verse}
    [Am]Dil ki raah pe [F]chalte
    {end_of_verse}

    """

    /// `gestures` after typing `5` over "raah" in Nashville view (A minor counts from C).
    static let gesturesNashville = gestures.replacingOccurrences(of: "raah", with: "[G]raah")

    static let gesturesAfter = """
    {key: Am}
    {start_of_verse}
    Di[Am]l ki [F]raah pe [F]chalte
    {end_of_verse}

    """

    static let darkSong = """
    {title: Shaam Dhali}
    {key: Am}
    {start_of_verse: Verse 1}
    [Am]Dil ki raah pe [F]chalte chalte
    [C]Shaam dhali aur [G]raat hui
    {end_of_verse}
    """

    static func longSong(lines: Int) -> String {
        var text = "{title: Long Song}\n{key: G}\n\n{start_of_verse}\n"
        for index in 4 ..< lines - 1 {
            text += "[G]Line \(index) of the [C]long song, [D]tum hi [Em]ho\n"
        }
        return text + "{end_of_verse}\n"
    }
}
