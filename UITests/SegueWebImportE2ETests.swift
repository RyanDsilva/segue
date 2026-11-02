import XCTest

/// P9-4 spec 15.4 (Personal build only): Import from Web Page and Find Lyrics end to end on
/// a clean library, offline. `-SegueImportFixtures YES` (Debug only) serves saved pages for
/// the chord site's tab and search, and a lyrics record; the other chord site stays
/// challenged, so its group offers Open Here. Nothing is saved without Accept.
@MainActor
final class SegueWebImportE2ETests: XCTestCase {
    private var app: XCUIApplication?
    private var base: URL?

    static let tabAddress =
        "https://tabs.ultimate-guitar.com/tab/misc-soundtrack/aashiqui-2-tum-hi-ho-chords-1234996"

    override func setUp() async throws {
        continueAfterFailure = false
        let base = URL(filePath: "/private/tmp/segue-e2e", directoryHint: .isDirectory)
            .appending(path: "web-import-\(UUID().uuidString)", directoryHint: .isDirectory)
        try? FileManager.default.removeItem(at: base)
        self.base = base
        try FileManager.default.createDirectory(
            at: library.appending(path: "songs", directoryHint: .isDirectory),
            withIntermediateDirectories: true,
        )
    }

    override func tearDown() async throws {
        E2E.terminate(app)
        if let base {
            try? FileManager.default.removeItem(at: base)
        }
    }

    func testImportAPageThenFindLyricsAcrossTheGroups() {
        let app = XCUIApplication()
        self.app = app
        E2E.launch(app, arguments: [
            "-SegueLibraryPath", library.path(percentEncoded: false),
            "-SegueResetState", "YES",
            "-SegueImportFixtures", "YES",
        ])
        // The Personal build's File menu has both items (spec 11.1).
        XCTAssertTrue(element(app, WebAXID.libraryEmpty).appears(timeout: 15))
        let file = app.menuBars.menuBarItems["File"]
        XCTAssertTrue(file.menuItems["Import from Web Page…"].exists, "No Import from Web Page…")
        XCTAssertTrue(file.menuItems["Find Lyrics…"].exists, "No Find Lyrics…")
        // The empty library offers both too (spec 11.2).
        XCTAssertTrue(element(app, WebAXID.emptyWebImport).exists, "No empty-state web import")
        XCTAssertTrue(element(app, WebAXID.emptyFindLyrics).exists, "No empty-state Find lyrics")

        importPage(app)
        reviewTheBestVersion(app)
        reviewALyricsRecord(app)
    }

    // MARK: - Steps

    /// File > Import from Web Page… (⇧⌘U): the web field, the review, Accept.
    private func importPage(_ app: XCUIApplication) {
        app.typeKey("u", modifierFlags: [.command, .shift], in: app)
        let field = element(app, WebAXID.webField)
        XCTAssertTrue(field.appears(timeout: 10), "No web field")
        field.click(in: app)
        field.typeText(Self.tabAddress + "\n", in: app)
        let sourceLine = element(app, WebAXID.sourceLine)
        XCTAssertTrue(sourceLine.appears(timeout: 30), "The page never reached the review")
        XCTAssertTrue(sourceLine.label.contains("ultimate-guitar.com"), sourceLine.label)
        attach(app, "web-import-review")
        element(app, WebAXID.accept).click(in: app)
        XCTAssertTrue(E2E.waitUntil(timeout: 15) { self.songFiles.count == 1 }, "nothing written")
        let text = songFiles.first.map(read) ?? ""
        XCTAssertTrue(text.contains("{title: Tum Hi Ho}"), text)
        XCTAssertTrue(text.contains("{album: Aashiqui 2}"), text)
        XCTAssertTrue(text.contains("{artist: Arijit Singh}"), text)
        XCTAssertTrue(text.contains("{start_of_verse"), text)
    }

    /// File > Find Lyrics… (⇧⌘L): three groups; the best version previews and reviews.
    private func reviewTheBestVersion(_ app: XCUIApplication) {
        let sourceLine = element(app, WebAXID.sourceLine)
        search(app)
        XCTAssertTrue(element(app, WebAXID.group("lyricsRecord")).appears(timeout: 30))
        XCTAssertTrue(element(app, WebAXID.openHere).appears(timeout: 30), "No Open Here")
        let review = element(app, WebAXID.review)
        XCTAssertTrue(E2E.waitUntil(timeout: 30) { review.isEnabled }, "No preview")
        XCTAssertTrue(element(app, WebAXID.preview).exists)
        attach(app, "find-lyrics")
        review.click(in: app)
        XCTAssertTrue(sourceLine.appears(timeout: 15))
        XCTAssertTrue(sourceLine.label.contains("ver 2"), sourceLine.label)
        element(app, WebAXID.cancel).click(in: app)
        XCTAssertTrue(sourceLine.disappears(timeout: 10))
    }

    /// A lyrics record: the attribution and labelled sections; Cancel writes nothing.
    private func reviewALyricsRecord(_ app: XCUIApplication) {
        let sourceLine = element(app, WebAXID.sourceLine)
        let review = element(app, WebAXID.review)
        search(app)
        // The lyrics record's row: its label has no versions count (spec 14).
        let record = app.descendants(matching: .any).matching(NSPredicate(
            format: "identifier BEGINSWITH %@ AND label BEGINSWITH %@ AND NOT (label CONTAINS %@)",
            WebAXID.resultPrefix,
            "Tum Hi Ho, Arijit Singh",
            "version",
        )).firstMatch
        XCTAssertTrue(record.appears(timeout: 30), "No lyrics record row in \(resultRows(app))")
        record.click(in: app)
        XCTAssertTrue(E2E.waitUntil(timeout: 30) { review.isEnabled })
        review.click(in: app)
        XCTAssertTrue(sourceLine.appears(timeout: 15))
        XCTAssertTrue(sourceLine.label.hasPrefix("Lyrics from LRCLIB"), sourceLine.label)
        let labels = app.descendants(matching: .any).matching(identifier: WebAXID.sectionLabel)
        XCTAssertTrue(E2E.waitUntil { labels.count >= 2 }, "sections: \(labels.count)")
        attach(app, "lyrics-review")
        element(app, WebAXID.cancel).click(in: app)
        XCTAssertTrue(sourceLine.disappears(timeout: 10))
        XCTAssertEqual(songFiles.count, 1)
    }

    // MARK: - Helpers

    private var library: URL {
        (base ?? URL(filePath: "/private/tmp")).appending(
            path: "library",
            directoryHint: .isDirectory,
        )
    }

    private var songFiles: [URL] {
        let songs = library.appending(path: "songs", directoryHint: .isDirectory)
        return ((try? FileManager.default.contentsOfDirectory(
            at: songs,
            includingPropertiesForKeys: nil,
        )) ?? []).filter { $0.pathExtension == "cho" }
    }

    /// Every result row's identifier and label, for a failure message.
    private func resultRows(_ app: XCUIApplication) -> String {
        let rows = app.descendants(matching: .any).matching(NSPredicate(
            format: "identifier BEGINSWITH %@",
            "segue.findLyrics.",
        ))
        return (0 ..< rows.count).map { index in
            let row = rows.element(boundBy: index)
            return "\(row.identifier)=\(row.label)|\(row.elementType.rawValue)"
        }.joined(separator: "; ")
    }

    private func read(_ url: URL) -> String {
        (try? String(contentsOf: url, encoding: .utf8)) ?? ""
    }

    private func search(_ app: XCUIApplication) {
        app.typeKey("l", modifierFlags: [.command, .shift], in: app)
        let field = element(app, WebAXID.findField)
        XCTAssertTrue(field.appears(timeout: 10), "No Find Lyrics sheet")
        field.click(in: app)
        field.typeText("tum hi ho\n", in: app)
        XCTAssertTrue(element(app, WebAXID.group("tabJSON")).appears(timeout: 30))
    }

    private func element(_ app: XCUIApplication, _ identifier: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    private func attach(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}

/// Mirrors `AccessibilityID+Paste.swift` (the UI test target cannot import SegueUI).
enum WebAXID {
    static let webField = "segue.paste.webField"
    static let sourceLine = "segue.paste.sourceLine"
    static let accept = "segue.paste.accept"
    static let cancel = "segue.paste.cancel"
    static let sectionLabel = "segue.paste.sectionLabel"
    static let findField = "segue.findLyrics.field"
    static let review = "segue.findLyrics.review"
    static let preview = "segue.findLyrics.preview"
    static let resultPrefix = "segue.findLyrics.result."
    static let openHere = "segue.web.openHere"
    static let libraryEmpty = "segue.library.empty"
    static let emptyWebImport = "segue.library.webImport"
    static let emptyFindLyrics = "segue.library.findLyrics"

    static func group(_ name: String) -> String {
        "segue.findLyrics.group.\(name)"
    }
}
