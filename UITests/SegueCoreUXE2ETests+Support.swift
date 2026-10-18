import AppKit
import XCTest

// Launching, queries, waits and file checks for `SegueCoreUXE2ETests`.

extension SegueCoreUXE2ETests {
    /// The test's folders, all under the sandbox exception path `/private/tmp/segue-e2e/`.
    struct Paths {
        let base: URL

        var library: URL {
            base.appending(path: "library", directoryHint: .isDirectory)
        }

        /// The stand-in Trash (`-SegueTrashPath`).
        var trash: URL {
            base.appending(path: "trash", directoryHint: .isDirectory)
        }

        /// What the app would open or reveal (`-SegueWorkspaceLog`).
        var workspaceLog: URL {
            base.appending(path: "workspace.log", directoryHint: .notDirectory)
        }

        /// Files the import tests import from.
        var importSource: URL {
            base.appending(path: "import-src", directoryHint: .isDirectory)
        }

        func song(_ slug: String) -> URL {
            library.appending(path: "songs/\(slug).cho", directoryHint: .notDirectory)
        }
    }

    /// Launches a fresh instance on this test's library. `autosaveDelay` nil keeps the
    /// shipped 1 s debounce; `reset` false relaunches on the stored test defaults (state
    /// restore).
    @MainActor
    @discardableResult
    func launch(
        autosaveDelay: String? = "0.3",
        reset: Bool = true,
        extraArguments: [String] = [],
    ) throws -> XCUIApplication {
        let paths = try XCTUnwrap(paths)
        let app = XCUIApplication()
        self.app = app
        var arguments = [
            "-SegueLibraryPath", paths.library.path(percentEncoded: false),
            "-SegueTrashPath", paths.trash.path(percentEncoded: false),
            "-SegueWorkspaceLog", paths.workspaceLog.path(percentEncoded: false),
        ]
        arguments += reset ? ["-SegueResetState", "YES"] : ["-SegueTestDefaults", "YES"]
        if let autosaveDelay {
            arguments += ["-SegueAutosaveDelay", autosaveDelay]
        }
        E2E.launch(app, arguments: arguments + extraArguments)
        return app
    }

    /// Writes a song file into the library before launch (it gets a sidecar on open).
    func seedSong(_ slug: String, _ source: String) throws {
        let paths = try XCTUnwrap(paths)
        let url = paths.song(slug)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true,
        )
        try Data(source.utf8).write(to: url)
    }

    func read(_ url: URL) -> String {
        (try? String(contentsOf: url, encoding: .utf8)) ?? ""
    }

    func exists(_ url: URL) -> Bool {
        FileManager.default.fileExists(atPath: url.path(percentEncoded: false))
    }

    /// File names directly in `folder`, sorted (empty when it does not exist).
    func names(in folder: URL) -> [String] {
        let names = try? FileManager.default
            .contentsOfDirectory(atPath: folder.path(percentEncoded: false))
        return (names ?? []).filter { !$0.hasPrefix(".") }.sorted()
    }

    // MARK: Queries

    @MainActor
    func element(_ app: XCUIApplication, _ identifier: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    @MainActor
    func songRows(_ app: XCUIApplication) -> XCUIElementQuery {
        app.descendants(matching: .any).matching(identifier: CoreAXID.songRow)
    }

    @MainActor
    func row(_ app: XCUIApplication, _ title: String) -> XCUIElement {
        songRows(app)
            .matching(NSPredicate(
                format: "label BEGINSWITH %@ OR value BEGINSWITH %@",
                title,
                title,
            ))
            .firstMatch
    }

    /// Selects `title` in the library and opens its editor in text mode, caret at the end.
    @MainActor
    @discardableResult
    func openEditor(_ app: XCUIApplication, _ title: String) -> XCUIElement {
        let row = row(app, title)
        XCTAssertTrue(row.waitForExistence(timeout: 15), "No row \(title)")
        row.click(in: app)
        return openSelectedEditor(app)
    }

    /// Opens the selected song's editor in text mode, caret at the end.
    @MainActor
    @discardableResult
    func openSelectedEditor(_ app: XCUIApplication) -> XCUIElement {
        let edit = element(app, CoreAXID.editSong)
        XCTAssertTrue(edit.waitForExistence(timeout: 10))
        edit.click(in: app)
        let textMode = element(app, CoreAXID.editorModeText)
        XCTAssertTrue(textMode.waitForExistence(timeout: 10))
        textMode.click(in: app)
        let editor = app.textViews[CoreAXID.editorText]
        XCTAssertTrue(editor.waitForExistence(timeout: 10))
        editor.click(in: app)
        editor.typeKey(.downArrow, modifierFlags: .command, in: app)
        return editor
    }

    @MainActor
    func saveStatus(_ app: XCUIApplication) -> XCUIElement {
        element(app, CoreAXID.editorSaveStatus)
    }

    // MARK: Waits

    func wait(timeout: TimeInterval = 10, _ condition: @escaping () -> Bool) -> Bool {
        let predicate = NSPredicate { _, _ in condition() }
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: nil)
        return XCTWaiter().wait(for: [expectation], timeout: timeout) == .completed
    }

    /// Waits until the editor's save status reads `text`.
    @MainActor
    func waitForStatus(_ app: XCUIApplication, _ text: String, timeout: TimeInterval = 10) -> Bool {
        let predicate = NSPredicate(format: "label == %@", text)
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: saveStatus(app))
        return XCTWaiter().wait(for: [expectation], timeout: timeout) == .completed
    }

    func waitForValue(_ element: XCUIElement, _ value: String, timeout: TimeInterval = 10) -> Bool {
        let predicate = NSPredicate(format: "value == %@", value)
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: element)
        return XCTWaiter().wait(for: [expectation], timeout: timeout) == .completed
    }

    /// Waits until the file at `url` contains `snippet`.
    func waitForFile(_ url: URL, contains snippet: String, timeout: TimeInterval = 10) -> Bool {
        wait(timeout: timeout) { self.read(url).contains(snippet) }
    }

    /// Makes another app frontmost, then Segue again (a real deactivate/activate cycle).
    @MainActor
    func reactivate(_ app: XCUIApplication) {
        let finder = XCUIApplication(bundleIdentifier: "com.apple.finder")
        finder.activate()
        _ = finder.wait(for: .runningForeground, timeout: 5)
        app.activate()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 10))
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

/// Song sources the tests seed.
enum CoreFixture {
    static let harbour = "{title: Harbour Lights}\n[G]Lanterns on the [C]water\n"
    static let river = "{title: River Song}\n[D]Down by the [A]river\n"
}

/// Accessibility identifiers (mirrors `AccessibilityID` in SegueUI).
enum CoreAXID {
    static let songRow = "segue.library.row"
    static let songTitle = "segue.song.title"
    static let editSong = "segue.song.edit"
    static let newSong = "segue.library.newSong"
    static let libraryEmpty = "segue.library.empty"
    static let editorText = "segue.editor.text"
    static let editorModeText = "segue.editor.mode.text"
    static let editorDone = "segue.editor.done"
    static let editorSaveStatus = "segue.editor.saveStatus"
    static let editorConflictBar = "segue.editor.conflict"
    static let editorConflictReload = "segue.editor.conflict.reload"
    static let editorConflictOverwrite = "segue.editor.conflict.overwrite"
    static let editorConflictCopy = "segue.editor.conflict.copy"
    static let transientMessage = "segue.main.transient"
}
