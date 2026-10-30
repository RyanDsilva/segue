import XCTest

/// P8-5 set composer E2E: a 12-song set (plus a break) typed into the composer row with
/// ⌘L and one Return per line, romanized Hindi spellings included, an "in A" gig key, the
/// duplicate block, "No song matches", builder undo and both builder modes. Every
/// non-typing key goes through one counting helper: ⌘L + 13 Returns, no Tab or ↓ needed
/// (section 3's "after" number).
final class SegueSetComposerE2ETests: SetlistE2ETestCase {
    /// The composer corpus (P8-5 section 13.1), with keys and lengths.
    private struct Song {
        var stem: String
        var title: String
        var key: String?
        var length: String?

        init(_ stem: String, _ title: String, _ key: String?, _ length: String?) {
            self.stem = stem
            self.title = title
            self.key = key
            self.length = length
        }
    }

    private static let corpus: [Song] = [
        Song("kesariya", "Kesariya", "G", "4:28"),
        Song("tum-hi-ho", "Tum Hi Ho", "Bb", "4:22"),
        Song("tum-hi-ho-bandhu", "Tum Hi Ho Bandhu", "C", "3:56"),
        Song("channa-mereya", "Channa Mereya", "Em", "4:49"),
        Song("pehla-nasha", "Pehla Nasha", "D", "4:47"),
        Song("deewana-hai-dekho", "Deewana Hai Dekho", "Am", "5:01"),
        Song("kabhi-kabhi-aditi", "Kabhi Kabhi Aditi", "G", "3:39"),
        Song("phir-le-aya-dil", "Phir Le Aya Dil", "Dm", "5:02"),
        Song("tujh-mein-rab", "Tujh Mein Rab Dikhta Hai", "F", "4:40"),
        Song("ae-dil-hai-mushkil", "Ae Dil Hai Mushkil", "Am", "4:29"),
        Song("kitaabon-wali-gali", "Kitaabon Wali Gali", "C", nil),
        Song("stuck-in-a-moment", "Stuck in a Moment", "A", "4:33"),
        Song("wonderwall", "Wonderwall", "F#m", "4:18"),
        Song("hotel-california", "Hotel California", "Bm", "6:30"),
        Song("soundcheck-at-seven", "Soundcheck at Seven", "E", nil),
        Song("naina", "", nil, nil),
    ]

    private static let lines = [
        "kesariyaa in A", "tum hi ho", "chana mereya", "kitabon wali", "---", "pehla nasha",
        "fir le aya dil", "diwana hai dekho", "kabhie kabhi", "ae dil hain mushkil",
        "tujh mein rab", "wonderwall", "tum hi ho bandhu",
    ]

    private static let expected = [
        "Kesariya", "Tum Hi Ho", "Channa Mereya", "Kitaabon Wali Gali", "Pehla Nasha",
        "Phir Le Aya Dil", "Deewana Hai Dekho", "Kabhi Kabhi Aditi", "Ae Dil Hai Mushkil",
        "Tujh Mein Rab Dikhta Hai", "Wonderwall", "Tum Hi Ho Bandhu",
    ]

    private static let composer = "segue.setlist.composer"
    private static let composerStatus = "segue.setlist.composer.status"
    private static let setlistBreak = "segue.setlist.break"

    /// Non-typing key presses and clicks, counted by `press(_:_:_:)`.
    private var actions = 0

    @MainActor
    func testTypeASetWithOneReturnPerSong() throws {
        let root = try XCTUnwrap(libraryRoot)
        try Self.seed(root)
        let app = try launch(waitForSongs: false, light: true)
        // The library list is lazy: wait for its first rows, the corpus's first title among
        // them (24 songs do not all fit the window).
        SetlistE2E.waitUntil("The seeded songs never listed") {
            SetlistE2E.row(app, SetlistAXID.songRow, "Ae Dil Hai Mushkil").exists
        }
        createSetlist(app, "Sangeet Night")
        let field = app.textFields[Self.composer]
        XCTAssertTrue(field.appears(timeout: 5), "No composer row")

        // ⌘L, then each line and one Return.
        press(app, "l", .command)
        for (offset, line) in Self.lines.enumerated() {
            app.typeText(line, in: app)
            press(app, XCUIKeyboardKey.return.rawValue, [])
            let rows = SetlistE2E.all(app, SetlistAXID.setlistEntry)
            let breaks = SetlistE2E.all(app, Self.setlistBreak)
            SetlistE2E.waitUntil("\"\(line)\" did not add a row") {
                rows.count + breaks.count == offset + 1
            }
        }
        XCTAssertEqual(actions, 14, "⌘L + 13 Returns")
        waitForEntries(app, Self.expected)
        screenshot(app, "composer-set")

        // Kesariya is in G with no capo: "in A" set +2, and the row shows A.
        XCTAssertEqual(SetlistE2E.texts(app, SetlistAXID.entryKey).first, "A")
        SetlistE2E.waitForDisk("The break is not the 5th entry, labelled Set 2") {
            let file = try XCTUnwrap(SetlistFixture.setlistFiles(root).first)
            let entries = try XCTUnwrap(file["entries"] as? [[String: Any]])
            let first = entries.first?["overrides"] as? [String: Any]
            return entries.count == 13
                && (entries[4]["break"] as? [String: Any])?["label"] as? String == "Set 2"
                && first?["transpose"] as? Int == 2
        }
        // Focus stayed in the composer, which is empty.
        XCTAssertEqual(field.value as? String ?? "", "")
        assertComposerHasFocus(app, field)
        checkDuplicateNoMatchAndUndo(app, field)
        checkModes(app, field)
    }

    /// The duplicate block, "No song matches" and builder undo, after the 12-song set.
    @MainActor
    private func checkDuplicateNoMatchAndUndo(_ app: XCUIApplication, _ field: XCUIElement) {
        // A song already in the set is flagged, not added; its row is selected.
        app.typeText("kesariya", in: app)
        app.typeKey(.return, modifierFlags: [], in: app)
        let status = SetlistE2E.element(app, Self.composerStatus)
        SetlistE2E.waitUntil("No duplicate status") {
            status.exists && SetlistE2E.text(status).contains("Already in the set at #1")
        }
        XCTAssertEqual(SetlistE2E.all(app, SetlistAXID.setlistEntry).count, 12)
        SetlistE2E.waitUntil("The first row is not selected") {
            SetlistE2E.all(app, SetlistAXID.setlistEntry).element(boundBy: 0).isSelected
        }
        screenshot(app, "composer-duplicate")

        // No match: the typed text replaces the selected "kesariya".
        app.typeText("qqqq", in: app)
        SetlistE2E.waitUntil("No no-match status") {
            status.exists && SetlistE2E.text(status) == "No song matches"
        }
        app.typeKey(.return, modifierFlags: [], in: app)
        XCTAssertFalse(
            E2E.waitUntil(timeout: 1) {
                SetlistE2E.all(app, SetlistAXID.setlistEntry).count != 12
            },
            "Return on no match changed the set",
        )

        // ⌘Z once: the last song goes; the composer keeps focus.
        app.typeKey("z", modifierFlags: .command, in: app)
        waitForEntries(app, Array(Self.expected.dropLast()))
        app.typeKey(.escape, modifierFlags: [], in: app)
        assertComposerHasFocus(app, field)
    }

    @MainActor
    private func checkModes(_ app: XCUIApplication, _ field: XCUIElement) {
        // Arrange, then Pick: the composer is still the last row and ⌘L focuses it.
        app.typeKey("2", modifierFlags: .command, in: app)
        assertComposerIsLast(app)
        app.typeKey("1", modifierFlags: .command, in: app)
        assertComposerIsLast(app)
        let library = SetlistE2E.element(app, SetlistAXID.builderLibrary)
        XCTAssertTrue(library.appears(timeout: 5), "Pick's library column is gone")
        library.click(in: app)
        app.typeKey("l", modifierFlags: .command, in: app)
        assertComposerHasFocus(app, field)
    }

    // MARK: - Steps

    /// Counts one non-typing key press (⌘L, Return).
    @MainActor
    private func press(
        _ app: XCUIApplication,
        _ key: String,
        _ modifiers: XCUIElement.KeyModifierFlags,
    ) {
        actions += 1
        app.typeKey(key, modifierFlags: modifiers, in: app)
    }

    /// Types a character and checks it lands in the composer, then clears it again.
    @MainActor
    private func assertComposerHasFocus(
        _ app: XCUIApplication,
        _ field: XCUIElement,
        file: StaticString = #filePath,
        line: UInt = #line,
    ) {
        app.typeText("x", in: app)
        SetlistE2E.waitUntil("The composer does not have keyboard focus", file: file, line: line) {
            (field.value as? String)?.hasSuffix("x") == true
        }
        app.typeKey(.escape, modifierFlags: [], in: app)
        SetlistE2E.waitUntil("Escape did not clear the composer", file: file, line: line) {
            (field.value as? String ?? "").isEmpty
        }
    }

    @MainActor
    private func assertComposerIsLast(_ app: XCUIApplication) {
        let zone = SetlistE2E.element(app, SetlistAXID.setlistDropZone)
        let rows = SetlistE2E.all(app, SetlistAXID.setlistEntry)
        SetlistE2E.waitUntil("The composer is not the last row") {
            guard zone.exists, rows.firstMatch.exists else { return false }
            let last = rows.element(boundBy: rows.count - 1)
            return zone.frame.minY >= last.frame.maxY - 1
        }
    }

    @MainActor
    private func createSetlist(_ app: XCUIApplication, _ name: String) {
        app.typeKey("n", modifierFlags: [.command, .shift], in: app)
        let field = app.textFields[SetlistAXID.newSetlistName]
        XCTAssertTrue(field.appears(timeout: 5))
        field.typeText(name + "\n", in: app)
        let title = app.staticTexts[SetlistAXID.setlistTitle]
        SetlistE2E.waitUntil("The builder never showed \(name)") {
            title.exists && SetlistE2E.text(title) == name
        }
    }

    @MainActor
    private func waitForEntries(_ app: XCUIApplication, _ titles: [String]) {
        SetlistE2E.waitUntil(
            "Expected entries \(titles), got \(SetlistE2E.texts(app, SetlistAXID.entryTitle))",
        ) {
            SetlistE2E.texts(app, SetlistAXID.entryTitle) == titles
        }
    }

    /// Writes the corpus songs (with sidecars, so IDs are fixed) into the seeded library.
    private static func seed(_ root: URL) throws {
        for (index, song) in corpus.enumerated() {
            var lines: [String] = []
            if !song.title.isEmpty {
                lines.append("{title: \(song.title)}")
            }
            if let key = song.key {
                lines.append("{key: \(key)}")
            }
            if let length = song.length {
                lines.append("{duration: \(length)}")
            }
            lines += ["", "La la la, the first line", "Second line of the song", ""]
            try SetlistFixture.write(
                lines.joined(separator: "\n"),
                to: root.appending(path: "songs/\(song.stem).cho"),
            )
            let id = "01JC0000000000000000000C" + String(format: "%02d", index)
            try SetlistFixture.write(
                #"{"schemaVersion": 3, "id": "\#(id)", "tags": [], "cues": [], "#
                    + #""displayPrefs": {}, "live": {}, "createdAt": "2026-10-01T10:00:00.000Z", "#
                    + #""updatedAt": "2026-10-01T10:00:00.000Z"}"#,
                to: root.appending(path: "songs/\(song.stem).segue.json"),
            )
        }
    }
}
