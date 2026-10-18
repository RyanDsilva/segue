import XCTest

/// The first-run Welcome flow through the real UI (WS2b 4.1, 4.2, section 7): the library
/// page on a clean install, seeding the Welcome library, WS3's consent rows hosted as the last
/// page, resuming a flow quit midway, upgraders, and the Welcome songs on stage.
final class SegueWelcomeE2ETests: XCTestCase {
    private var app: XCUIApplication?
    private var root: URL?

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    override func tearDownWithError() throws {
        E2E.terminate(app)
        if let root {
            try? FileManager.default.removeItem(at: root)
        }
    }

    // MARK: Page 1 on a clean install

    @MainActor
    func testFreshInstallShowsLibraryStep() {
        let app = launch(["-SegueResetState", "YES", "-SegueConsent", "undecided"])
        let title = element(app, WelcomeAXID.title)
        XCTAssertTrue(title.appears(timeout: 15), "no Welcome sheet on a clean install")
        XCTAssertEqual(text(title), "Where should your songs live?")
        XCTAssertEqual(text(element(app, WelcomeAXID.step)), "Step 1 of 3")
        XCTAssertTrue(app.buttons[WelcomeAXID.chooserCreate].exists)
        XCTAssertTrue(app.buttons[WelcomeAXID.chooserOpen].exists)
        // WS3's standalone consent sheet waits for the Welcome flow (I-1).
        XCTAssertFalse(element(app, WelcomeAXID.consentSheet).exists)
        // Esc never dismisses the flow.
        app.typeKey(.escape, modifierFlags: [], in: app)
        XCTAssertFalse(E2E.waitUntil(timeout: 1) { !title.exists }, "Esc closed the sheet")
        attach(app, "welcome-p1-light")
        // The real open panel is a sandboxed remote view (Open and Save Panel Service): the
        // runner sees no elements in it, so choosing a folder is covered by the override
        // flags here and by the manual App Store first-run check (accessibility-audit.md).
    }

    // MARK: The whole flow: seed, consent, relaunch

    @MainActor
    func testFirstRunSeedsWelcomeLibrary() throws {
        let library = try emptyLibrary()
        let app = launch(library.arguments([
            "-SegueOnboarding", "fresh", "-SegueConsent", "undecided",
            "-SegueRememberLibrary", "YES", "-SegueAppearance", "light",
        ]))
        let title = element(app, WelcomeAXID.title)
        XCTAssertTrue(title.appears(timeout: 15))
        XCTAssertEqual(text(title), "Welcome to Segue")
        XCTAssertEqual(text(element(app, WelcomeAXID.step)), "Step 2 of 3")
        let checkbox = element(app, WelcomeAXID.addSongs)
        XCTAssertTrue(checkbox.appears(timeout: 5))
        XCTAssertEqual(checkbox.value as? Int, 1, "the checkbox is off for an empty library")
        attach(app, "welcome-p2-light")
        element(app, WelcomeAXID.continueButton).click(in: app)

        answerConsentPage(app, title: title)

        // The library lists the four songs, the setlist and the tag.
        for song in WelcomeSongs.titles {
            XCTAssertTrue(songRow(app, song).appears(timeout: 10), "no row for \(song)")
        }
        XCTAssertTrue(
            row(app, WelcomeAXID.setlistRow, "Welcome Set").appears(timeout: 5),
            "no Welcome Set setlist",
        )
        XCTAssertTrue(row(app, WelcomeAXID.sidebarTag, "Welcome").exists, "no Welcome tag")
        attach(app, "welcome-seeded-library")
        try library.assertSeeded()

        // Asked once: a relaunch from the stored bookmark shows no sheet of any kind, and
        // Settings > Privacy shows the answers.
        app.terminate()
        // Recording services, so Settings > Privacy has its toggles.
        let relaunched = launch([
            "-SegueTestDefaults", "YES", "-SegueConsent", "asStored",
            "-SegueServicesLog", library.root.appending(path: "services.jsonl").path(),
        ])
        XCTAssertTrue(songRow(relaunched, WelcomeSongs.titles[0]).appears(timeout: 15))
        XCTAssertFalse(
            E2E.waitUntil(timeout: 2) {
                self.element(relaunched, WelcomeAXID.title).exists
                    || self.element(relaunched, WelcomeAXID.consentSheet).exists
            },
            "a launch sheet came back",
        )
        relaunched.typeKey(",", modifierFlags: .command, in: relaunched)
        let privacy = relaunched.toolbars.buttons["Privacy"].firstMatch
        XCTAssertTrue(privacy.appears(timeout: 10))
        privacy.click(in: relaunched)
        let analytics = element(relaunched, WelcomeAXID.privacyToggle("analytics"))
        XCTAssertTrue(analytics.appears(timeout: 10))
        XCTAssertEqual(analytics.value as? Int, 0, "analytics should be off")
        XCTAssertEqual(
            element(relaunched, WelcomeAXID.privacyToggle("crashReports")).value as? Int,
            1,
            "crash reports should be on",
        )
    }

    // MARK: A folder that already has songs

    @MainActor
    func testExistingFolderDefaultsToNoSeed() throws {
        let library = try emptyLibrary()
        try library.writeOwnSong()
        let app = launch(library.arguments(["-SegueOnboarding", "fresh"]))
        let checkbox = element(app, WelcomeAXID.addSongs)
        XCTAssertTrue(checkbox.appears(timeout: 15))
        XCTAssertEqual(checkbox.value as? Int, 0, "never seed someone's real library by default")
        // Consent is decided in test runs: page 2 is the last page.
        XCTAssertEqual(text(element(app, WelcomeAXID.step)), "Step 2 of 2")
        element(app, WelcomeAXID.continueButton).click(in: app)
        XCTAssertTrue(element(app, WelcomeAXID.title).disappears(timeout: 10))
        XCTAssertTrue(songRow(app, "My Own Song").appears(timeout: 5))
        XCTAssertEqual(try library.songFiles(), ["my-own-song.cho"], "something was added")
    }

    // MARK: Quit midway, resume; upgraders

    @MainActor
    func testQuitMidOnboardingResumes() throws {
        let library = try emptyLibrary()
        let app = launch(library.arguments([
            "-SegueOnboarding", "fresh", "-SegueConsent", "undecided",
            "-SegueRememberLibrary", "YES", "-SegueAppearance", "dark",
        ]))
        XCTAssertTrue(element(app, WelcomeAXID.addSongs).appears(timeout: 15))
        attach(app, "welcome-p2-dark")
        element(app, WelcomeAXID.addSongs).click(in: app)
        element(app, WelcomeAXID.continueButton).click(in: app)
        XCTAssertTrue(element(app, WelcomeAXID.decline("analytics")).appears(timeout: 10))
        attach(app, "welcome-p3-dark")
        app.terminate()

        // The relaunch opens the stored library and shows only the unanswered page.
        let resumed = launch([
            "-SegueTestDefaults", "YES", "-SegueConsent", "asStored", "-SegueAppearance", "dark",
        ])
        let step = element(resumed, WelcomeAXID.step)
        XCTAssertTrue(step.appears(timeout: 15), "the flow did not resume")
        XCTAssertEqual(text(step), "Step 1 of 1")
        XCTAssertEqual(text(element(resumed, WelcomeAXID.title)), "Help improve Segue?")
        XCTAssertEqual(try library.songFiles(), [], "the unticked checkbox still seeded")
        element(resumed, WelcomeAXID.decline("analytics")).click(in: resumed)
        element(resumed, WelcomeAXID.decline("crashReports")).click(in: resumed)
        element(resumed, WelcomeAXID.continueButton).click(in: resumed)
        XCTAssertTrue(element(resumed, WelcomeAXID.title).disappears(timeout: 10))
    }

    @MainActor
    func testUpgraderSeesOnlyConsentSheet() throws {
        let library = try emptyLibrary()
        // A library remembered by an earlier build: no onboarding keys at all.
        let first = launch(library.arguments(["-SegueRememberLibrary", "YES"]))
        XCTAssertTrue(element(first, WelcomeAXID.sidebarLibrary).appears(timeout: 15))
        first.terminate()

        let upgraded = launch(["-SegueTestDefaults", "YES", "-SegueConsent", "undecided"])
        XCTAssertTrue(element(upgraded, WelcomeAXID.consentSheet).appears(timeout: 15))
        XCTAssertFalse(element(upgraded, WelcomeAXID.title).exists, "an upgrader saw Welcome")
        element(upgraded, WelcomeAXID.decline("analytics")).click(in: upgraded)
        element(upgraded, WelcomeAXID.decline("crashReports")).click(in: upgraded)
        element(upgraded, WelcomeAXID.consentContinue).click(in: upgraded)
        XCTAssertTrue(element(upgraded, WelcomeAXID.consentSheet).disappears(timeout: 10))
        XCTAssertEqual(try library.songFiles(), [], "an upgrader was seeded")
        upgraded.terminate()

        // Marked done: the next launch shows nothing either.
        let again = launch(["-SegueTestDefaults", "YES", "-SegueConsent", "asStored"])
        XCTAssertTrue(element(again, WelcomeAXID.sidebarLibrary).appears(timeout: 15))
        XCTAssertFalse(E2E.waitUntil(timeout: 2) {
            self.element(again, WelcomeAXID.title).exists
                || self.element(again, WelcomeAXID.consentSheet).exists
        })
    }

    // MARK: The screenshot folder and the songs on stage

    @MainActor
    func testSeedWelcomeWithoutPathPlaysOnStage() {
        // No library path: the in-container screenshot folder (WS5 composes this flag).
        let arguments = [
            "-SegueSeedWelcome",
            "YES",
            "-SegueOnboarding",
            "done",
            "-SegueResetState",
            "YES",
        ]
        let app = launch(arguments)
        for song in WelcomeSongs.titles {
            XCTAssertTrue(songRow(app, song).appears(timeout: 15), "no row for \(song)")
        }
        XCTAssertEqual(rowCount(app), 4)

        // Welcome Set on stage: Ferry Lights is the 2-column song.
        element(app, WelcomeAXID.sidebarSetlists).click(in: app)
        let row = element(app, WelcomeAXID.setlistRow)
        XCTAssertTrue(row.appears(timeout: 10))
        row.click(in: app)
        let start = element(app, WelcomeAXID.startShow)
        XCTAssertTrue(start.appears(timeout: 10))
        start.click(in: app)
        let checklistStart = element(app, WelcomeAXID.checklistStart)
        if checklistStart.appears(timeout: 3) {
            checklistStart.click(in: app)
        }
        let title = app.staticTexts[WelcomeAXID.liveTitle]
        XCTAssertTrue(title.appears(timeout: 10))
        for _ in 0 ..< 3 {
            app.typeKey(.rightArrow, modifierFlags: [], in: app)
        }
        XCTAssertTrue(E2E.waitUntil { (title.value as? String) == "Ferry Lights Over Calder Bay" })
        let body = element(app, WelcomeAXID.liveBody)
        XCTAssertTrue(E2E.waitUntil { body.label.hasSuffix("columns 2") }, body.label)
        attach(app, "welcome-ferry-lights-stage")
        app.typeKey(".", modifierFlags: .command, in: app)
        XCTAssertTrue(element(app, WelcomeAXID.liveEndDialog).appears(timeout: 5))
        app.typeKey(.return, modifierFlags: [], in: app)
        XCTAssertTrue(title.disappears(timeout: 10))
        app.terminate()

        // A second launch adds nothing.
        let again = launch(["-SegueSeedWelcome", "YES", "-SegueOnboarding", "done"])
        // The relaunch restores the setlist builder: back to the library list.
        let library = element(again, WelcomeAXID.sidebarLibrary)
        XCTAssertTrue(library.appears(timeout: 15))
        library.click(in: again)
        XCTAssertTrue(songRow(again, WelcomeSongs.titles[0]).appears(timeout: 15))
        XCTAssertFalse(E2E.waitUntil(timeout: 1) { self.rowCount(again) != 4 }, "songs were added")
    }
}

// MARK: - Steps

extension SegueWelcomeE2ETests {
    @MainActor
    private func launch(_ arguments: [String]) -> XCUIApplication {
        let app = XCUIApplication()
        self.app = app
        E2E.launch(app, arguments: arguments)
        return app
    }

    private func emptyLibrary() throws -> WelcomeLibrary {
        let library = try WelcomeLibrary()
        root = library.root
        return library
    }

    @MainActor
    private func element(_ app: XCUIApplication, _ identifier: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    /// Page 3: WS3's four equal buttons, none preselected; Continue waits for both rows;
    /// Return and Esc answer nothing. Answers Don't Share and Send, then Continue.
    @MainActor
    private func answerConsentPage(_ app: XCUIApplication, title: XCUIElement) {
        // Page 3 is WS3's ConsentChoiceView: four equal buttons, none preselected.
        XCTAssertTrue(E2E.waitUntil { self.text(title) == "Help improve Segue?" }, "no page 3")
        XCTAssertEqual(text(element(app, WelcomeAXID.step)), "Step 3 of 3")
        let buttons = ["analytics", "crashReports"].flatMap { toggle in
            [element(app, WelcomeAXID.decline(toggle)), element(app, WelcomeAXID.accept(toggle))]
        }
        for button in buttons {
            XCTAssertTrue(button.appears(timeout: 5))
            XCTAssertEqual(button.value as? String, "not selected", "a choice is preselected")
        }
        let first = buttons[0].frame
        for button in buttons.dropFirst() {
            XCTAssertEqual(button.frame.width, first.width, accuracy: 1, "unequal widths")
            XCTAssertEqual(button.frame.height, first.height, accuracy: 1, "unequal heights")
        }
        let next = element(app, WelcomeAXID.continueButton)
        XCTAssertFalse(next.isEnabled, "Continue is enabled before both rows are answered")
        attach(app, "welcome-p3-light")
        // Return and Esc answer nothing and close nothing.
        app.typeKey(.return, modifierFlags: [], in: app)
        app.typeKey(.escape, modifierFlags: [], in: app)
        XCTAssertFalse(E2E.waitUntil(timeout: 1) { !title.exists }, "the sheet closed")
        for button in buttons {
            XCTAssertEqual(button.value as? String, "not selected")
        }
        element(app, WelcomeAXID.decline("analytics")).click(in: app)
        element(app, WelcomeAXID.accept("crashReports")).click(in: app)
        XCTAssertTrue(E2E.waitUntil { next.isEnabled })
        attach(app, "welcome-p3-answered-light")
        next.click(in: app)
        XCTAssertTrue(title.disappears(timeout: 10), "the sheet did not close")
    }

    /// A static text's string (macOS puts it in the value, not the label).
    @MainActor
    private func text(_ element: XCUIElement) -> String {
        [element.value as? String, element.label, element.title]
            .compactMap(\.self).first { !$0.isEmpty } ?? ""
    }

    /// The element with `identifier` whose label or value mentions `text` (sidebar rows).
    @MainActor
    private func row(_ app: XCUIApplication, _ identifier: String, _ text: String)
        -> XCUIElement
    {
        app.descendants(matching: .any)
            .matching(NSPredicate(
                format: "identifier == %@ AND (label CONTAINS %@ OR value CONTAINS %@)",
                argumentArray: [identifier, text, text],
            ))
            .firstMatch
    }

    @MainActor
    private func songRow(_ app: XCUIApplication, _ title: String) -> XCUIElement {
        app.descendants(matching: .any)
            .matching(NSPredicate(
                format: "identifier == %@ AND label CONTAINS %@",
                WelcomeAXID.songRow,
                title,
            ))
            .firstMatch
    }

    @MainActor
    private func rowCount(_ app: XCUIApplication) -> Int {
        E2E.snapshots(app.windows.firstMatch, identifier: WelcomeAXID.songRow).count
    }

    @MainActor
    private func attach(_ app: XCUIApplication, _ name: String) {
        // Let a page change finish its fade first.
        E2E.waitUntil(timeout: 0.4) { false }
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}

/// The four Welcome songs (WS2b Appendix A), by title.
enum WelcomeSongs {
    static let titles = [
        "Soundcheck at Seven", "Kitaabon Wali Gali", "Kettle On, Lights Low",
        "Ferry Lights Over Calder Bay",
    ]
}

/// A fresh, empty library folder under the E2E sandbox exception.
struct WelcomeLibrary {
    let root: URL

    init() throws {
        root = URL(filePath: "/private/tmp/segue-e2e", directoryHint: .isDirectory)
            .appending(path: "welcome-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    func arguments(_ extra: [String]) -> [String] {
        ["-SegueLibraryPath", root.path(percentEncoded: false), "-SegueResetState", "YES"] + extra
    }

    var songs: URL {
        root.appending(path: "songs", directoryHint: .isDirectory)
    }

    /// The `.cho` files in `songs/`, sorted.
    func songFiles() throws -> [String] {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: songs.path)) ?? []
        return names.filter { $0.hasSuffix(".cho") }.sorted()
    }

    func writeOwnSong() throws {
        try FileManager.default.createDirectory(at: songs, withIntermediateDirectories: true)
        try Data("{title: My Own Song}\n[G]Hello\n".utf8)
            .write(to: songs.appending(path: "my-own-song.cho"))
    }

    /// The four songs with their sidecars, and the Welcome Set setlist file.
    func assertSeeded(file: StaticString = #filePath, line: UInt = #line) throws {
        let expected = [
            "ferry-lights-over-calder-bay.cho", "kettle-on-lights-low.cho",
            "kitaabon-wali-gali.cho", "soundcheck-at-seven.cho",
        ]
        XCTAssertEqual(try songFiles(), expected, file: file, line: line)
        let ferry = songs.appending(path: "ferry-lights-over-calder-bay.segue.json")
        let sidecar = try JSONSerialization.jsonObject(with: Data(contentsOf: ferry))
            as? [String: Any]
        let tags = sidecar?["tags"] as? [String] ?? []
        XCTAssertTrue(tags.contains("Welcome"), "\(tags)", file: file, line: line)
        XCTAssertEqual(sidecar?["proficiency"] as? String, "learning", file: file, line: line)
        let live = sidecar?["live"] as? [String: Any]
        XCTAssertEqual(live?["columns"] as? Int, 2, file: file, line: line)
        let setlists = root.appending(path: "setlists", directoryHint: .isDirectory)
        let names = try FileManager.default.contentsOfDirectory(atPath: setlists.path)
        XCTAssertEqual(names, ["welcome-set.setlist.json"], file: file, line: line)
    }
}

/// Identifiers the Welcome E2E uses (mirrors `AccessibilityID` in SegueUI).
enum WelcomeAXID {
    static let title = "segue.welcome.title"
    static let step = "segue.welcome.step"
    static let addSongs = "segue.welcome.addSongs"
    static let continueButton = "segue.welcome.continue"
    static let chooserCreate = "segue.chooser.create"
    static let chooserOpen = "segue.chooser.open"
    static let consentSheet = "segue.consent.sheet"
    static let consentContinue = "segue.consent.continue"
    static func decline(_ toggle: String) -> String {
        "segue.consent.\(toggle).decline"
    }

    static func accept(_ toggle: String) -> String {
        "segue.consent.\(toggle).accept"
    }

    static func privacyToggle(_ toggle: String) -> String {
        "segue.privacy.\(toggle).toggle"
    }

    static let songRow = "segue.library.row"
    static let sidebarLibrary = "segue.sidebar.library"
    static let sidebarSetlists = "segue.sidebar.setlists"
    static let setlistRow = "segue.setlists.row"
    static let sidebarTag = "segue.sidebar.tag"
    static let startShow = "segue.setlist.startShow"
    static let checklistStart = "segue.live.checklist.start"
    static let liveTitle = "segue.live.title"
    static let liveBody = "segue.live.body"
    static let liveEndDialog = "segue.live.endDialog"
}
