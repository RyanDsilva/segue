import XCTest

/// Steps and observations shared by the services E2E classes (WS3 spec 14.3). Every launch
/// runs the Recording adapters (`-SegueServicesLog`), so each signal, breadcrumb,
/// crash-reporter start and sent report is one JSON line the test reads back.
protocol ServicesE2E: XCTestCase {
    var library: LiveLibrary? { get }
    var app: XCUIApplication? { get set }
}

extension LiveLibrary {
    /// The Recording adapters' JSON-lines file.
    var servicesLog: URL {
        root.appending(path: "services.jsonl", directoryHint: .notDirectory)
    }

    /// The diagnostic log folder beside it.
    var diagnosticLogs: URL {
        root.appending(path: "Logs", directoryHint: .isDirectory)
    }

    var workspaceLog: URL {
        root.appending(path: "workspace.log", directoryHint: .notDirectory)
    }

    /// Every recorded services line, parsed.
    func servicesEntries() -> [[String: Any]] {
        guard let data = try? Data(contentsOf: servicesLog) else { return [] }
        return data.split(separator: 0x0A).compactMap { line in
            try? JSONSerialization.jsonObject(with: Data(line)) as? [String: Any]
        }
    }

    /// The names of the recorded analytics signals, in order.
    func signals() -> [String] {
        servicesEntries().filter { $0["kind"] as? String == "signal" }
            .compactMap { $0["name"] as? String }
    }

    /// The recorded signals named `name` with their parameters.
    func signals(named name: String) -> [[String: String]] {
        servicesEntries()
            .filter { $0["kind"] as? String == "signal" && $0["name"] as? String == name }
            .compactMap { $0["params"] as? [String: String] }
    }

    func kinds() -> [String] {
        servicesEntries().compactMap { $0["kind"] as? String }
    }

    /// The raw services log text (for leak greps).
    func servicesText() -> String {
        (try? String(contentsOf: servicesLog, encoding: .utf8)) ?? ""
    }

    /// Every diagnostic log file's text.
    func diagnosticLogText() -> String {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: diagnosticLogs.path))
            ?? []
        return names.sorted().compactMap { name in
            try? String(contentsOf: diagnosticLogs.appending(path: name), encoding: .utf8)
        }.joined(separator: "\n")
    }
}

@MainActor
extension ServicesE2E {
    /// Launches on the library with Recording services and `extra` arguments.
    func launchServices(
        _ library: LiveLibrary,
        reset: Bool = true,
        extra: [String] = [],
    ) -> XCUIApplication {
        let app = XCUIApplication()
        self.app = app
        E2E.launch(app, arguments: library.arguments(reset: reset, extra: [
            "-SegueServicesLog", library.servicesLog.path(percentEncoded: false),
            "-SegueWorkspaceLog", library.workspaceLog.path(percentEncoded: false),
        ] + extra))
        return app
    }

    func element(_ app: XCUIApplication, _ identifier: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    /// Settings (Cmd-,) on the Privacy pane.
    func openPrivacySettings(_ app: XCUIApplication) {
        app.typeKey(",", modifierFlags: .command, in: app)
        let tab = app.toolbars.buttons["Privacy"].firstMatch
        XCTAssertTrue(tab.appears(timeout: 10), "Settings has no Privacy tab")
        tab.click(in: app)
        XCTAssertTrue(element(app, ServicesAXID.privacyToggle("analytics")).appears(timeout: 10))
    }

    /// Answers the consent prompt and presses Continue.
    func answerConsent(_ app: XCUIApplication, analytics: Bool, crash: Bool) {
        element(
            app,
            analytics ? ServicesAXID.consentAccept("analytics")
                : ServicesAXID.consentDecline("analytics"),
        ).click(in: app)
        element(
            app,
            crash ? ServicesAXID.consentAccept("crashReports")
                : ServicesAXID.consentDecline("crashReports"),
        ).click(in: app)
        element(app, ServicesAXID.consentContinue).click(in: app)
        XCTAssertTrue(element(app, ServicesAXID.consentSheet).disappears(timeout: 10))
    }

    /// Opens `title` in the editor (the visual canvas).
    func openEditor(_ app: XCUIApplication, titled title: String) {
        openSong(app, titled: title)
        let edit = element(app, ServicesAXID.editSong)
        XCTAssertTrue(edit.appears(timeout: 10))
        edit.click(in: app)
        XCTAssertTrue(element(app, ServicesAXID.editorDone).appears(timeout: 10))
    }

    /// Selects `title` in the library list.
    func openSong(_ app: XCUIApplication, titled title: String) {
        let row = app.descendants(matching: .any)
            .matching(NSPredicate(
                format: "identifier == %@ AND label CONTAINS %@",
                LiveAXID.songRow,
                title,
            ))
            .firstMatch
        XCTAssertTrue(row.appears(timeout: 10), "no library row for \(title)")
        row.click(in: app)
    }

    func waitFor(timeout: TimeInterval = 10, _ condition: () -> Bool) -> Bool {
        E2E.waitUntil(timeout: timeout, condition)
    }

    func screenshot(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "services-\(name)"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}

/// Identifiers of the services UI (mirrors `AccessibilityID+Services` in SegueUI).
enum ServicesAXID {
    static let consentSheet = "segue.consent.sheet"
    static let consentContinue = "segue.consent.continue"
    static func consentDecline(_ toggle: String) -> String {
        "segue.consent.\(toggle).decline"
    }

    static func consentAccept(_ toggle: String) -> String {
        "segue.consent.\(toggle).accept"
    }

    static func privacyToggle(_ toggle: String) -> String {
        "segue.privacy.\(toggle).toggle"
    }

    static func privacyCaption(_ toggle: String) -> String {
        "segue.privacy.\(toggle).caption"
    }

    static let librarySearch = "segue.library.search"
    static let editSong = "segue.song.edit"
    static let editorDone = "segue.editor.done"
    static let editorTransposeUp = "segue.editor.transpose.up"
    static let editorNashville = "segue.editor.display.nashville"
    static let editorPaletteChord = "segue.editor.palette.chord"
    static let privacyDiagnosticsID = "segue.privacy.diagnosticsID"
    static let privacyCopyID = "segue.privacy.diagnosticsID.copy"
    static let privacyRestartCaption = "segue.privacy.crashReports.restart"
}
