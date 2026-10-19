import XCTest

/// Shared setup for the phase 2 builder / library metadata / gig log E2E suites (unit D):
/// a fresh temp library seeded with songs (with sidecars, so IDs are known), plus helpers
/// to seed setlists and shows, query the UI and read the files back.
enum SetlistFixture {
    /// A seeded song: file stem, title, key, capo, tempo and `{duration}` (nil = unknown).
    struct Song {
        let stem: String
        let title: String
        let artist: String
        let key: String
        let capo: Int?
        let tempo: Int
        let duration: String?
        let index: Int

        /// A fixed, valid ULID per song.
        var id: String {
            "01JC0000000000000000000S" + String(format: "%02d", index)
        }

        var source: String {
            var lines = ["{title: \(title)}", "{artist: \(artist)}", "{key: \(key)}"]
            if let capo {
                lines.append("{capo: \(capo)}")
            }
            lines.append("{tempo: \(tempo)}")
            if let duration {
                lines.append("{duration: \(duration)}")
            }
            lines += [
                "",
                "{start_of_verse}",
                "[\(key)]Lanterns on the water, boats come drifting in",
                "Salt upon my collar and the tide is turning thin",
                "{end_of_verse}",
                "",
                "{start_of_chorus}",
                "[\(key)]Hold on, harbor lights",
                "{end_of_chorus}",
                "",
            ]
            return lines.joined(separator: "\n")
        }
    }

    /// Original titles from the design mockups (licence-free).
    static let songs: [Song] = [
        Song(
            stem: "harbor-lights",
            title: "Harbor Lights",
            artist: "The Lanterns",
            key: "G",
            capo: 2,
            tempo: 96,
            duration: "3:40",
            index: 1,
        ),
        Song(
            stem: "paper-boats",
            title: "Paper Boats",
            artist: "The Lanterns",
            key: "D",
            capo: nil,
            tempo: 120,
            duration: "3:12",
            index: 2,
        ),
        Song(
            stem: "dil-ki-raah",
            title: "Dil Ki Raah",
            artist: "Mira Sen",
            key: "Am",
            capo: nil,
            tempo: 88,
            duration: "4:05",
            index: 3,
        ),
        Song(
            stem: "saawan-ki-shaam",
            title: "Saawan Ki Shaam",
            artist: "Mira Sen",
            key: "C",
            capo: nil,
            tempo: 76,
            duration: nil,
            index: 4,
        ),
        Song(
            stem: "northbound",
            title: "Northbound",
            artist: "Original",
            key: "E",
            capo: nil,
            tempo: 132,
            duration: "2:58",
            index: 5,
        ),
        Song(
            stem: "kitchen-radio",
            title: "Kitchen Radio",
            artist: "Original",
            key: "A",
            capo: nil,
            tempo: 104,
            duration: "3:25",
            index: 6,
        ),
        Song(
            stem: "lamplighter",
            title: "Lamplighter",
            artist: "The Lanterns",
            key: "F",
            capo: nil,
            tempo: 70,
            duration: "4:12",
            index: 7,
        ),
        Song(
            stem: "morning-ferry",
            title: "Morning Ferry",
            artist: "Original",
            key: "Bb",
            capo: nil,
            tempo: 92,
            duration: "3:33",
            index: 8,
        ),
    ]

    static func song(_ title: String) -> Song {
        guard let song = songs.first(where: { $0.title == title }) else {
            preconditionFailure("No fixture song \(title)")
        }
        return song
    }

    /// Titles in the library's order (by title).
    static var sortedTitles: [String] {
        songs.map(\.title).sorted()
    }

    /// A fresh library folder under the Debug sandbox exception path.
    static func makeRoot() throws -> URL {
        let root = URL(filePath: "/private/tmp/segue-e2e", directoryHint: .isDirectory)
            .appending(path: "run-\(UUID().uuidString)", directoryHint: .isDirectory)
        try? FileManager.default.removeItem(at: root)
        try FileManager.default.createDirectory(
            at: root.appending(path: "songs", directoryHint: .isDirectory),
            withIntermediateDirectories: true,
        )
        for song in songs {
            try write(song.source, to: root.appending(path: "songs/\(song.stem).cho"))
            try write(sidecar(song), to: root.appending(path: "songs/\(song.stem).segue.json"))
        }
        return root
    }

    static func write(_ text: String, to url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true,
        )
        try Data(text.utf8).write(to: url)
    }

    private static func sidecar(_ song: Song) -> String {
        """
        {
          "schemaVersion" : 3,
          "id" : "\(song.id)",
          "tags" : [],
          "cues" : [],
          "displayPrefs" : {},
          "live" : {},
          "createdAt" : "2026-10-01T10:00:00.000Z",
          "updatedAt" : "2026-10-01T10:00:00.000Z"
        }
        """
    }

    /// Reads a JSON object file.
    static func json(_ url: URL) throws -> [String: Any] {
        try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any],
            "\(url.lastPathComponent) is not a JSON object",
        )
    }

    /// The song's sidecar as on disk now.
    static func sidecarJSON(_ root: URL, _ title: String) throws -> [String: Any] {
        try json(root.appending(path: "songs/\(song(title).stem).segue.json"))
    }

    /// Every setlist file, parsed.
    static func setlistFiles(_ root: URL) throws -> [[String: Any]] {
        let folder = root.appending(path: "setlists", directoryHint: .isDirectory)
        guard FileManager.default.fileExists(atPath: folder.path) else { return [] }
        return try FileManager.default.contentsOfDirectory(atPath: folder.path)
            .filter { $0.hasSuffix(".setlist.json") }
            .sorted()
            .map { try json(folder.appending(path: $0)) }
    }
}

/// Polling helpers shared by the phase 2 D suites.
@MainActor
enum SetlistE2E {
    static func element(_ app: XCUIApplication, _ identifier: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    static func all(_ app: XCUIApplication, _ identifier: String) -> XCUIElementQuery {
        app.descendants(matching: .any).matching(identifier: identifier)
    }

    /// The visible text of an element: combined SwiftUI rows expose it as label or value.
    static func text(_ element: XCUIElement) -> String {
        let label = element.label
        let value = element.value as? String ?? ""
        return label.isEmpty ? value : (value.isEmpty ? label : label + " " + value)
    }

    /// The first element with `identifier` whose text starts with `title`.
    static func row(_ app: XCUIApplication, _ identifier: String, _ title: String) -> XCUIElement {
        all(app, identifier)
            .matching(NSPredicate(
                format: "label BEGINSWITH %@ OR value BEGINSWITH %@",
                title,
                title,
            ))
            .firstMatch
    }

    /// Waits until `condition` holds (10 s by default).
    @discardableResult
    static func waitUntil(
        _ message: @autoclosure () -> String,
        timeout: TimeInterval = 10,
        file: StaticString = #filePath,
        line: UInt = #line,
        _ condition: () -> Bool,
    ) -> Bool {
        E2E.expect(message(), timeout: timeout, file: file, line: line, condition)
    }

    /// Waits until a file-backed condition holds; failures inside count as "not yet".
    @discardableResult
    static func waitForDisk(
        _ message: @autoclosure () -> String,
        file: StaticString = #filePath,
        line: UInt = #line,
        _ condition: () throws -> Bool,
    ) -> Bool {
        E2E.expect(message(), file: file, line: line, condition)
    }

    /// Texts of all elements with `identifier`, in order, from one consistent snapshot (so
    /// rows re-rendering mid-read never fail the query; an unavailable tree reads as empty).
    static func texts(_ app: XCUIApplication, _ identifier: String) -> [String] {
        guard let root = try? app.snapshot() else { return [] }
        var found: [String] = []
        var stack: [any XCUIElementSnapshot] = [root]
        while let node = stack.popLast() {
            if node.identifier == identifier {
                let value = node.value as? String ?? ""
                let label = node.label
                found.append(label.isEmpty ? value : (value.isEmpty ? label : label + " " + value))
            }
            stack.append(contentsOf: node.children.reversed())
        }
        return found
    }

    /// Replaces the text of a search field.
    static func search(_ app: XCUIApplication, _ identifier: String, _ query: String) {
        let field = app.searchFields[identifier]
        XCTAssertTrue(field.appears(timeout: 5))
        field.click(in: app)
        field.typeKey("a", modifierFlags: .command, in: app)
        if query.isEmpty {
            field.typeKey(.delete, modifierFlags: [], in: app)
        } else {
            field.typeText(query, in: app)
        }
    }
}

/// Accessibility identifiers (mirrors `AccessibilityID` / `AccessibilityID+Setlists`).
enum SetlistAXID {
    static let sidebarLibrary = "segue.sidebar.library"
    static let sidebarGigLog = "segue.sidebar.gigLog"
    static let sidebarTag = "segue.sidebar.tag"
    static let songRow = "segue.library.row"
    static let librarySearch = "segue.library.search"
    static let songTitle = "segue.song.title"
    static let filterTag = "segue.filter.tag"
    static func filterProficiency(_ level: String) -> String {
        "segue.filter.proficiency.\(level)"
    }

    static func songProficiency(_ level: String) -> String {
        "segue.song.proficiency.\(level)"
    }

    static let songPlayStats = "segue.song.playStats"
    static let songTag = "segue.song.tag"
    static let songTagRemove = "segue.song.tag.remove"
    static let songTagField = "segue.song.tag.field"
    static let songNotes = "segue.song.notes"
    static let songCue = "segue.song.cue"
    static let songEditNotes = "segue.song.editNotes"
    static let notesEditorText = "segue.notesEditor.text"
    static let notesEditorAddCue = "segue.notesEditor.addCue"
    static let notesEditorCueText = "segue.notesEditor.cue.text"
    static let notesEditorSave = "segue.notesEditor.save"
    static let newSetlist = "segue.setlists.new"
    static let newSetlistName = "segue.setlists.new.name"
    static let newSetlistCreate = "segue.setlists.new.create"
    static let setlistRow = "segue.setlists.row"
    static let setlistTitle = "segue.setlist.title"
    static let setlistEntries = "segue.setlist.entries"
    static let setlistEntry = "segue.setlist.entry"
    static let builderLibrary = "segue.builder.library"
    static let builderSearch = "segue.builder.search"
    static let builderLibraryRow = "segue.builder.library.row"
    static let builderAdd = "segue.builder.add"
    static let builderInSet = "segue.builder.inSet"
    static let setlistTotal = "segue.setlist.total"
    static let setlistTarget = "segue.setlist.target"
    static let setlistDetailsLine = "segue.setlist.detailsLine"
    static let setlistStartShow = "segue.setlist.startShow"
    static let setlistRehearse = "segue.setlist.rehearse"
    static let setlistMenu = "segue.setlist.menu"
    static let setlistDropZone = "segue.setlist.dropZone"
    static let entryTitle = "segue.setlist.entry.title"
    static let entryKey = "segue.setlist.entry.key"
    static let entryCapo = "segue.setlist.entry.capo"
    static let entryLength = "segue.setlist.entry.length"
    static let entryStart = "segue.setlist.entry.start"
    static let entryNote = "segue.setlist.entry.note"
    static let entryRemove = "segue.setlist.entry.remove"
    static let entryCapoUp = "segue.entryEditor.capo.up"
    static let entryCapoValue = "segue.entryEditor.capo.value"
    static let entryTransposeUp = "segue.entryEditor.transpose.up"
    static let entryNoteField = "segue.entryEditor.note"
    static let entryDone = "segue.entryEditor.done"
    static let setlistNameField = "segue.setlistName.field"
    static let setlistNameSave = "segue.setlistName.save"
    static let setlistRenameAction = "segue.setlist.action.rename"
    static let setlistDuplicateAction = "segue.setlist.action.duplicate"
    static let setlistDeleteAction = "segue.setlist.action.delete"
    static let detailsVenue = "segue.setlistDetails.venue"
    static let detailsHasDate = "segue.setlistDetails.hasDate"
    static let detailsTarget = "segue.setlistDetails.target"
    static let detailsSave = "segue.setlistDetails.save"
    static let gigLogList = "segue.gigLog.list"
    static let gigLogRow = "segue.gigLog.row"
    static let gigTitle = "segue.gig.title"
    static let gigSummary = "segue.gig.summary"
    static let gigVenue = "segue.gig.venue"
    static let gigNotes = "segue.gig.notes"
    static func gigRating(_ value: Int) -> String {
        "segue.gig.rating.\(value)"
    }

    static let gigPlayedRow = "segue.gig.played"
    static let gigSkippedRow = "segue.gig.skipped"
    static let gigDelete = "segue.gig.delete"
    static let gigMoreMenu = "segue.gig.more"
    static let gigReveal = "segue.gig.reveal"
    static let reorderSheet = "segue.reorder"
    static let reorderPlannedRow = "segue.reorder.planned"
    static let reorderPerformedRow = "segue.reorder.performed"
    static let reorderInclude = "segue.reorder.include"
    static let reorderSave = "segue.reorder.save"
    static let reorderDiscard = "segue.reorder.discard"
}

/// Base for the D suites: a seeded temp library per test, failure attachments, screenshots.
class SetlistE2ETestCase: XCTestCase {
    var libraryRoot: URL?
    var app: XCUIApplication?

    override func setUpWithError() throws {
        continueAfterFailure = false
        libraryRoot = try SetlistFixture.makeRoot()
    }

    override func tearDownWithError() throws {
        E2E.terminate(app)
        if let libraryRoot {
            try? FileManager.default.removeItem(at: libraryRoot)
        }
    }

    /// Launches on the seeded library and waits for its songs.
    /// `light` forces the light appearance (the design mockups are light) whatever the
    /// system appearance is; otherwise the app follows the system.
    @MainActor
    func launch(waitForSongs: Bool = true, light: Bool = false) throws -> XCUIApplication {
        let root = try XCTUnwrap(libraryRoot)
        let app = XCUIApplication()
        self.app = app
        var arguments = [
            "-SegueLibraryPath", root.path(percentEncoded: false),
            "-SegueResetState", "YES",
            // Deletes go to a folder inside the test library, never the user's Trash.
            "-SegueTrashPath", Self.trashFolder(root).path(percentEncoded: false),
            // Show in Finder is recorded, never performed.
            "-SegueWorkspaceLog", Self.workspaceLog(root).path(percentEncoded: false),
        ]
        if light {
            arguments += ["-NSRequiresAquaSystemAppearance", "YES"]
        }
        E2E.launch(app, arguments: arguments)
        if waitForSongs {
            SetlistE2E.waitUntil("The seeded songs never listed") {
                SetlistE2E.all(app, SetlistAXID.songRow).count == SetlistFixture.songs.count
            }
        }
        return app
    }

    /// The stand-in Trash for `root` (`-SegueTrashPath`), removed with the library.
    static func trashFolder(_ root: URL) -> URL {
        root.appending(path: ".e2e-trash", directoryHint: .isDirectory)
    }

    /// What the app revealed or opened (`-SegueWorkspaceLog`), one JSON line per call.
    static func workspaceLog(_ root: URL) -> URL {
        root.appending(path: ".e2e-workspace.log", directoryHint: .notDirectory)
    }

    /// File names in the stand-in Trash.
    static func trashed(_ root: URL) -> [String] {
        let path = trashFolder(root).path(percentEncoded: false)
        return ((try? FileManager.default.contentsOfDirectory(atPath: path)) ?? []).sorted()
    }

    /// Attaches the main window as `builder-<name>` (exported to .build/screenshots/builder).
    @MainActor
    func screenshot(_ app: XCUIApplication, _ name: String) {
        let window = app.windows.firstMatch
        let shot = window.exists ? window.screenshot() : app.screenshot()
        let attachment = XCTAttachment(screenshot: shot)
        attachment.name = "builder-\(name)"
        attachment.lifetime = .keepAlways
        add(attachment)
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
