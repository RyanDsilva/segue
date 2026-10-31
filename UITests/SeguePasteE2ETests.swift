import AppKit
import XCTest

/// Paste and import through the review sheet (P3-4, spec 6.1-6.2, R75, R83, R96) on a
/// fresh library: the clipboard via New Song from Clipboard, Cancel then Accept; New Song's
/// paste flow and Start blank; three files that need converting in ONE sheet with one
/// unticked. Test runs have no AI providers: the deterministic result is what is accepted.
@MainActor
final class SeguePasteE2ETests: XCTestCase {
    private var app: XCUIApplication?
    private var base: URL?

    /// A chords-over-lyrics sheet: a title line, a verse, a repeated chorus (R101 labels
    /// both Chorus) and a site's junk line.
    static let sheet = """
    Harbour Lights - Segue Originals
    Tabbed by someone | rate this tab

    G               C
    Lanterns on the water, ropes upon the quay
    D               G
    Every boat is coming home, every one but me

    C        G
    Hold the light, hold the light
    D            G
    Bring her home tonight

    G               C
    Gulls above the breakwater, salt upon the sill
    D               G
    Every window burning bright, burning for me still

    C        G
    Hold the light, hold the light
    D            G
    Bring her home tonight
    """

    /// The async fixtures are main-actor isolated in XCTest, like this class; the
    /// synchronous setUpWithError()/tearDownWithError() overrides are nonisolated.
    override func setUp() async throws {
        continueAfterFailure = false
        let base = URL(filePath: "/private/tmp/segue-e2e", directoryHint: .isDirectory)
            .appending(path: "paste-\(UUID().uuidString)", directoryHint: .isDirectory)
        try? FileManager.default.removeItem(at: base)
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        self.base = base
        // One song, so the library opens on the list (not the empty state).
        let songs = library.appending(path: "songs", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: songs, withIntermediateDirectories: true)
        try Data("{title: River Song}\n[Am]Water\n".utf8)
            .write(to: songs.appending(path: "river-song.cho"))
    }

    override func tearDown() async throws {
        E2E.terminate(app)
        if let base {
            try? FileManager.default.removeItem(at: base)
        }
    }

    // MARK: - Tests

    func testClipboardPasteCancelThenAccept() {
        let app = launch()
        setClipboard(Self.sheet)

        // Cancel writes nothing.
        app.typeKey("v", modifierFlags: [.command, .option], in: app)
        let sheet = element(app, PasteAXID.sheet)
        XCTAssertTrue(sheet.appears(timeout: 10), "No review sheet")
        XCTAssertTrue(element(app, PasteAXID.original).appears(timeout: 5))
        XCTAssertTrue(element(app, PasteAXID.result).exists)
        attach(app, "paste-review")
        element(app, PasteAXID.cancel).click(in: app)
        XCTAssertTrue(sheet.disappears(timeout: 10))
        XCTAssertFalse(exists("harbour-lights"))

        // Accept writes the converted song with its sections.
        app.typeKey("v", modifierFlags: [.command, .option], in: app)
        XCTAssertTrue(sheet.appears(timeout: 10))
        let labels = app.descendants(matching: .any).matching(identifier: PasteAXID.sectionLabel)
        XCTAssertTrue(E2E.waitUntil { labels.count >= 3 }, "sections: \(labels.count)")
        element(app, PasteAXID.accept).click(in: app)
        XCTAssertTrue(sheet.disappears(timeout: 10))
        XCTAssertTrue(E2E.waitUntil { self.exists("harbour-lights") }, "nothing written")
        let text = read("harbour-lights")
        XCTAssertTrue(text.contains("{title: Harbour Lights}"), text)
        XCTAssertTrue(text.contains("{artist: Segue Originals}"), text)
        XCTAssertEqual(text.components(separatedBy: "{start_of_chorus").count - 1, 2, text)
        XCTAssertTrue(text.contains("{start_of_verse}"), text)
        XCTAssertFalse(text.contains("Tabbed by"), text)
        XCTAssertFalse(text.contains("{key"), text)
        XCTAssertTrue(row(app, "Harbour Lights").appears(timeout: 10))
    }

    func testNewSongPastesOrStartsBlank() {
        let app = launch()
        setClipboard(Self.sheet)

        // New Song: the input state; Command-V pastes straight into review.
        element(app, PasteAXID.newSong).click(in: app)
        let input = element(app, PasteAXID.input)
        XCTAssertTrue(input.appears(timeout: 10), "No input state")
        attach(app, "new-song-input")
        input.click(in: app)
        app.typeKey("v", modifierFlags: .command, in: app)
        let accept = element(app, PasteAXID.accept)
        XCTAssertTrue(accept.appears(timeout: 10), "The paste did not move to review")
        accept.click(in: app)
        XCTAssertTrue(E2E.waitUntil { self.exists("harbour-lights") }, "nothing written")

        // New Song, then Start blank: the empty editor.
        element(app, PasteAXID.newSong).click(in: app)
        XCTAssertTrue(input.appears(timeout: 10))
        element(app, PasteAXID.startBlank).click(in: app)
        let editor = app.textViews[PasteAXID.editorText]
        XCTAssertTrue(editor.appears(timeout: 10), "Start blank opened no editor")
        XCTAssertTrue(E2E.waitUntil { (editor.value as? String)?.isEmpty == true })
        XCTAssertTrue(input.disappears(timeout: 5))
    }

    func testThreeFilesOneSheetUntickOne() throws {
        let source = try XCTUnwrap(base).appending(path: "in", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        var files: [String] = []
        for (name, title) in [
            ("tide.txt", "Tide Song"),
            ("pier.crd", "Pier Song"),
            ("rope.txt", "Rope Song"),
        ] {
            let url = source.appending(path: name)
            try Data(Self.sheet.replacingOccurrences(of: "Harbour Lights", with: title).utf8)
                .write(to: url)
            files.append(url.path(percentEncoded: false))
        }
        let app = launch(extra: ["-SegueImportPanelPaths", files.joined(separator: ":")])

        app.typeKey("i", modifierFlags: [.command, .shift], in: app)
        let rows = app.descendants(matching: .any).matching(identifier: PasteAXID.batchRow)
        XCTAssertTrue(E2E.waitUntil { rows.count == 3 }, "rows: \(rows.count)")
        let ticks = app.checkBoxes.matching(identifier: PasteAXID.batchTick)
        XCTAssertEqual(ticks.count, 3)
        let rope = app.checkBoxes.matching(NSPredicate(
            format: "identifier == %@ AND label == %@",
            PasteAXID.batchTick,
            "rope.txt",
        )).firstMatch
        rope.click(in: app)
        let accept = element(app, PasteAXID.accept)
        XCTAssertTrue(E2E.waitUntil { accept.label == "Import 2 Songs" }, accept.label)
        attach(app, "paste-batch")
        accept.click(in: app)
        XCTAssertTrue(accept.disappears(timeout: 10))
        XCTAssertTrue(E2E.waitUntil { self.exists("tide-song") && self.exists("pier-song") })
        XCTAssertFalse(exists("rope-song"))
        XCTAssertTrue(row(app, "Tide Song").appears(timeout: 10))
    }

    // MARK: - Helpers

    private var library: URL {
        (base ?? URL(filePath: "/private/tmp")).appending(
            path: "library",
            directoryHint: .isDirectory,
        )
    }

    private func launch(extra: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        self.app = app
        let root = base ?? URL(filePath: "/private/tmp")
        E2E.launch(app, arguments: [
            "-SegueLibraryPath", library.path(percentEncoded: false),
            "-SegueTrashPath", root.appending(path: "trash").path(percentEncoded: false),
            "-SegueResetState", "YES",
        ] + extra)
        XCTAssertTrue(row(app, "River Song").appears(timeout: 15))
        return app
    }

    private func setClipboard(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    private func exists(_ slug: String) -> Bool {
        FileManager.default.fileExists(
            atPath: library.appending(path: "songs/\(slug).cho").path(percentEncoded: false),
        )
    }

    private func read(_ slug: String) -> String {
        (try? String(contentsOf: library.appending(path: "songs/\(slug).cho"), encoding: .utf8))
            ?? ""
    }

    private func element(_ app: XCUIApplication, _ identifier: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    private func row(_ app: XCUIApplication, _ title: String) -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(
            format: "identifier == %@ AND label BEGINSWITH %@",
            PasteAXID.songRow,
            title,
        )).firstMatch
    }

    private func attach(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}

/// Mirrors `AccessibilityID+Paste.swift` (the UI test target cannot import SegueUI).
enum PasteAXID {
    static let sheet = "segue.paste.sheet"
    static let input = "segue.paste.input"
    static let startBlank = "segue.paste.startBlank"
    static let original = "segue.paste.original"
    static let result = "segue.paste.result"
    static let sectionLabel = "segue.paste.sectionLabel"
    static let accept = "segue.paste.accept"
    static let cancel = "segue.paste.cancel"
    static let batchRow = "segue.paste.batchRow"
    static let batchTick = "segue.paste.batchTick"
    static let newSong = "segue.library.newSong"
    static let songRow = "segue.library.row"
    static let editorText = "segue.editor.text"
}
