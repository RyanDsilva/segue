import XCTest

/// The library copy test (R197, docs/release/v1.0-readiness.md 2.1): the 1.0 build opens a
/// COPY of the owner's real library and runs every first-open upgrade on it, so the owner
/// can read exactly what 1.0 changes on disk before it ever touches the real folder.
///
/// Runs only from `scripts/library-copy-test.sh`, which stages the copy into the E2E VM and
/// sets `SEGUE_COPY_LIBRARY` (through `TEST_RUNNER_SEGUE_COPY_LIBRARY`) to it; skipped
/// everywhere else, so `make e2e` and the gate never see it. Never run it on the host.
///
/// Two scenarios, each on its own fresh copy under /private/tmp/segue-e2e:
/// - `open`: open, answer the one-time notes (timings note OK; the `{duration}` offer Not
///   Now if it appears), then one sidecar write that ends where it started (proficiency
///   Ready, then Undo), so the sidecar is saved by 1.0 and shows its migration; quit.
/// - `duration`: the same copy with a `{duration: 4:30}` line added to the first song, then
///   Remove on the cleanup offer; quit.
/// Each attaches the library folder afterwards (`library-after-<scenario>`, a zip), what
/// went to the Trash (`trash-<scenario>`) and the injected song (`injected-duration`), for
/// the host script to diff against its untouched copy.
final class SegueLibraryCopyE2ETests: XCTestCase {
    private var app: XCUIApplication?

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    override func tearDownWithError() throws {
        E2E.terminate(app)
    }

    private var source: URL {
        get throws {
            guard let path = ProcessInfo.processInfo.environment["SEGUE_COPY_LIBRARY"],
                  !path.isEmpty
            else {
                throw XCTSkip("only scripts/library-copy-test.sh runs the library copy test")
            }
            return URL(fileURLWithPath: path, isDirectory: true)
        }
    }

    @MainActor
    func testOpenAndSave() throws {
        let root = try prepare("open")
        let app = launch(root)
        answerNotes(app, remove: false)
        let row = app.descendants(matching: .any).matching(identifier: "segue.library.row")
            .firstMatch
        XCTAssertTrue(row.appears(timeout: 15), "the copied library lists no song")
        row.click(in: app)
        let ready = app.descendants(matching: .any)
            .matching(identifier: "segue.song.proficiency.ready").firstMatch
        XCTAssertTrue(ready.appears(timeout: 10), "no proficiency control")
        let songs = root.appending(path: "library/songs")
        let sidecars = try FileManager.default.contentsOfDirectory(atPath: songs.path)
            .filter { $0.hasSuffix(".segue.json") }
        func proficiencies() -> [String] {
            sidecars.compactMap { name in
                (try? Data(contentsOf: songs.appending(path: name)))
                    .flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
                    .flatMap { $0["proficiency"] as? String }
            }
        }
        let before = proficiencies()
        ready.click(in: app)
        XCTAssertTrue(
            E2E.waitUntil(timeout: 10) { proficiencies() != before },
            "setting Ready wrote no sidecar",
        )
        row.click(in: app) // the window's Cmd-Z, not a field's
        app.typeKey("z", modifierFlags: .command, in: app)
        XCTAssertTrue(
            E2E.waitUntil(timeout: 10) { proficiencies() == before },
            "Undo did not restore the proficiency",
        )
        quit(app)
        try attach(root, "open")
    }

    @MainActor
    func testDurationCleanup() throws {
        let root = try prepare("duration")
        let songs = root.appending(path: "library/songs")
        let first = try XCTUnwrap(
            FileManager.default.contentsOfDirectory(atPath: songs.path)
                .filter { $0.hasSuffix(".cho") }.min(),
            "no song in the copy",
        )
        let song = songs.appending(path: first)
        var text = try String(contentsOf: song, encoding: .utf8)
        let lines = text.components(separatedBy: "\n")
        let titleLine = lines.firstIndex { $0.hasPrefix("{title") } ?? 0
        var edited = lines
        edited.insert("{duration: 4:30}", at: titleLine + 1)
        text = edited.joined(separator: "\n")
        try text.write(to: song, atomically: true, encoding: .utf8)
        let injected =
            XCTAttachment(
                string: "added {duration: 4:30} after line \(titleLine + 1) of songs/\(first)",
            )
        injected.name = "injected-duration"
        injected.lifetime = .keepAlways
        add(injected)

        let app = launch(root)
        answerNotes(app, remove: true)
        XCTAssertTrue(
            E2E.waitUntil(timeout: 15) {
                (try? String(contentsOf: song, encoding: .utf8))?.contains("{duration") == false
            },
            "Remove left the {duration} line in songs/\(first)",
        )
        quit(app)
        try attach(root, "duration")
    }

    // MARK: - Support

    /// A fresh copy of the staged library at /private/tmp/segue-e2e/copy-<name>/library,
    /// with an empty trash folder beside it.
    @MainActor
    private func prepare(_ name: String) throws -> URL {
        let root = URL(fileURLWithPath: "/private/tmp/segue-e2e/copy-\(name)", isDirectory: true)
        let files = FileManager.default
        try? files.removeItem(at: root)
        try files.createDirectory(
            at: root.appending(path: "trash"),
            withIntermediateDirectories: true,
        )
        try files.copyItem(at: source, to: root.appending(path: "library"))
        return root
    }

    @MainActor
    private func launch(_ root: URL) -> XCUIApplication {
        let app = XCUIApplication()
        self.app = app
        E2E.launch(app, arguments: [
            "-SegueLibraryPath", root.appending(path: "library").path(percentEncoded: false),
            "-SegueTrashPath", root.appending(path: "trash").path(percentEncoded: false),
            "-SegueWorkspaceLog", root.appending(path: "workspace.log").path(percentEncoded: false),
            "-SegueResetState", "YES",
            "-SegueAutosaveDelay", "0.3",
        ])
        return app
    }

    /// Clicks through the one-time notes in order: OK on each note, then Remove or Not Now
    /// on the `{duration}` offer when it appears. Records which ones showed.
    @MainActor
    private func answerNotes(_ app: XCUIApplication, remove: Bool) {
        var seen: [String] = []
        for _ in 0 ..< 4 {
            let alert = app.dialogs.firstMatch.exists ? app.dialogs.firstMatch : app.sheets
                .firstMatch
            guard alert.appears(timeout: 6) else { break }
            let title = alert.staticTexts.allElementsBoundByIndex.map(\.label)
                .joined(separator: " / ")
            seen.append(title)
            if alert.buttons["OK"].exists {
                alert.buttons["OK"].click(in: app)
            } else if alert.buttons["Remove"].exists {
                alert.buttons[remove ? "Remove" : "Not Now"].click(in: app)
            } else {
                break
            }
            _ = alert.disappears(timeout: 5)
        }
        let note = XCTAttachment(string: seen.isEmpty ? "(no one-time notes)" : seen
            .joined(separator: "\n"))
        note.name = "notes-shown"
        note.lifetime = .keepAlways
        add(note)
    }

    @MainActor
    private func quit(_ app: XCUIApplication) {
        E2E.quitting(app) { app.typeKey("q", modifierFlags: .command, in: app) }
        XCTAssertTrue(E2E.waitUntil(timeout: 20) { app.state == .notRunning }, "Segue did not quit")
    }

    @MainActor
    private func attach(_ root: URL, _ name: String) throws {
        for (folder, label) in [("library", "library-after-\(name)"), ("trash", "trash-\(name)")] {
            let attachment = XCTAttachment(compressedContentsOfDirectory: root.appending(path: folder))
            attachment.name = label
            attachment.lifetime = .keepAlways
            add(attachment)
        }
    }
}
