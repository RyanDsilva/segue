import XCTest

/// Apple's automated accessibility audit on every main screen (WS2b 4.9.2, section 7):
/// library, song detail, editor (text and visual), setlist builder, gig log, each Settings
/// pane, the Welcome sheet and the stage, in light; the phase 3 screens are in
/// `AccessibilityAuditE2ETests+Phase3.swift`. XCUITest does not expose custom
/// accessibility actions, so the chord pill's actions are `EditorCanvasAccessibilityTests` and
/// the set rows' Move up / Move down are in the VoiceOver walk. Findings that are not Segue's
/// to fix are listed in `ignoredIssue` with the reason (accessibility-audit.md).
final class AccessibilityAuditE2ETests: XCTestCase {
    private var library: LiveLibrary?
    var app: XCUIApplication?
    /// The phase 3 test's Welcome library (`AccessibilityAuditE2ETests+Phase3.swift`).
    var welcomeRoot: URL?
    /// Every finding, by screen, written to the report attachment.
    private var findings: [String] = []

    override func setUpWithError() throws {
        continueAfterFailure = true
        library = try LiveLibrary()
    }

    override func tearDownWithError() throws {
        let report = XCTAttachment(string: findings.isEmpty ? "no findings"
            : findings.joined(separator: "\n"))
        report.name = "accessibility-audit-findings"
        report.lifetime = .keepAlways
        add(report)
        E2E.terminate(app)
        library?.remove()
        if let welcomeRoot {
            try? FileManager.default.removeItem(at: welcomeRoot)
        }
    }

    @MainActor
    func testMainScreensLight() throws {
        try auditMainScreens(appearance: "light")
    }

    @MainActor
    private func auditMainScreens(appearance: String) throws {
        let library = try XCTUnwrap(library)
        let app = XCUIApplication()
        self.app = app
        E2E.launch(app, arguments: library.arguments(extra: ["-SegueAppearance", appearance]))
        auditLibraryAndEditor(app, appearance)
        auditBuilderAndGigLog(app, appearance)
        auditSettingsAndWelcome(app, appearance)
        auditStage(app, appearance)
    }

    /// Library, song detail, the editor in both modes; the pill's four actions.
    @MainActor
    private func auditLibraryAndEditor(
        _ app: XCUIApplication,
        _ look: String,
    ) {
        let row = element(app, AuditAXID.songRow)
        XCTAssertTrue(row.appears(timeout: 15))
        audit(app, "library-\(look)")
        row.click(in: app)
        XCTAssertTrue(element(app, AuditAXID.editSong).appears(timeout: 10))
        audit(app, "song-\(look)")
        element(app, AuditAXID.editSong).click(in: app)
        let visual = element(app, AuditAXID.editorModeVisual)
        XCTAssertTrue(visual.appears(timeout: 10))
        element(app, AuditAXID.editorModeText).click(in: app)
        audit(app, "editor-text-\(look)")
        visual.click(in: app)
        let pill = element(app, AuditAXID.editorPill)
        XCTAssertTrue(pill.appears(timeout: 10))
        audit(app, "editor-visual-\(look)")
        element(app, AuditAXID.editorDone).click(in: app)
    }

    /// The builder (set rows reorder without drag) and the gig log.
    @MainActor
    private func auditBuilderAndGigLog(
        _ app: XCUIApplication,
        _ look: String,
    ) {
        element(app, AuditAXID.sidebarSetlists).click(in: app)
        let setlist = element(app, AuditAXID.setlistRow)
        XCTAssertTrue(setlist.appears(timeout: 10))
        setlist.click(in: app)
        let entry = element(app, AuditAXID.setlistEntry)
        XCTAssertTrue(entry.appears(timeout: 10))
        audit(app, "builder-\(look)")
        element(app, AuditAXID.sidebarGigLog).click(in: app)
        audit(app, "giglog-\(look)")
    }

    /// Every Settings pane, then Help > Welcome to Segue… (revisit mode).
    @MainActor
    private func auditSettingsAndWelcome(_ app: XCUIApplication, _ look: String) {
        app.typeKey(",", modifierFlags: .command, in: app)
        for pane in ["General", "Appearance", "Live", "AI", "Privacy", "Data"] {
            let tab = app.toolbars.buttons[pane].firstMatch
            XCTAssertTrue(tab.appears(timeout: 10))
            tab.click(in: app)
            XCTAssertTrue(app.windows[pane].firstMatch.appears(timeout: 5))
            audit(app, "settings-\(pane.lowercased())-\(look)")
        }
        app.typeKey("w", modifierFlags: .command, in: app)
        let help = app.menuBars.menuBarItems["Help"]
        help.click(in: app)
        help.menuItems["Welcome to Segue…"].firstMatch.click()
        XCTAssertTrue(element(app, AuditAXID.welcomeTitle).appears(timeout: 10))
        audit(app, "welcome-revisit-\(look)")
        app.typeKey(.escape, modifierFlags: [], in: app)
        XCTAssertTrue(element(app, AuditAXID.welcomeTitle).disappears(timeout: 5))
    }

    /// The pre-show checklist (when it shows) and the stage.
    @MainActor
    private func auditStage(_ app: XCUIApplication, _ look: String) {
        element(app, AuditAXID.sidebarSetlists).click(in: app)
        element(app, AuditAXID.setlistRow).click(in: app)
        element(app, AuditAXID.startShow).click(in: app)
        let checklistStart = element(app, AuditAXID.checklistStart)
        if checklistStart.appears(timeout: 3) {
            audit(app, "checklist-\(look)")
            checklistStart.click(in: app)
        }
        XCTAssertTrue(app.staticTexts[AuditAXID.liveTitle].appears(timeout: 10))
        audit(app, "stage-\(look)")
        app.typeKey(".", modifierFlags: .command, in: app)
        XCTAssertTrue(element(app, AuditAXID.liveEndDialog).appears(timeout: 5))
        app.typeKey(.return, modifierFlags: [], in: app)
    }
}

@MainActor
extension AccessibilityAuditE2ETests {
    func element(_ app: XCUIApplication, _ identifier: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    /// Runs the audit on the frontmost state; every finding not on the ignore list fails.
    func audit(_ app: XCUIApplication, _ screen: String) {
        E2E.waitUntil(timeout: 0.4) { false }
        do {
            try app.performAccessibilityAudit(for: .all) { issue in
                // Report-only types are never resolved to their element: each property read
                // (identifier, label, value, frame) is a separate accessibility round trip
                // (~50 ms), and resolving every contrast and layout finding made one audit
                // take minutes. Only the enforced type is described in full.
                guard issue.auditType == .sufficientElementDescription else {
                    self.findings.append("\(screen): \(issue.compactDescription)")
                    return true
                }
                let element = issue.element
                let value = (element?.value as? String).map { "'\($0.prefix(40))'" } ?? "-"
                let frame = element.map {
                    "\(Int($0.frame.minX)),\(Int($0.frame.minY)) \(Int($0.frame.width))x"
                        + "\(Int($0.frame.height))"
                } ?? "-"
                let type = element?.elementType.rawValue ?? 0
                let id = element?.identifier ?? ""
                let label = element?.label ?? ""
                let line = "\(screen): \(issue.compactDescription) | type \(type) "
                    + "id '\(id)' label '\(label)' value \(value) frame \(frame)"
                self.findings.append(line)
                return Self.ignoredIssue(issue)
            }
        } catch {
            XCTFail("\(screen): \(error)")
        }
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "audit-\(screen)"
        shot.lifetime = .keepAlways
        add(shot)
    }

    /// Instrumentation that exists only in UI test runs (`UITesting.isActive`).
    static let testOnlyIdentifiers: Set = [
        "segue.editor.status.keystrokes", "segue.editor.status.inputSettings",
        "segue.editor.saveStatus", "segue.live.body", "segue.live.checklist.row.state",
    ]

    /// Controls a person acts on: each needs a name (VoiceOver, Voice Control).
    static let namedTypes: Set<XCUIElement.ElementType> = [
        .button, .link, .image, .checkBox, .radioButton, .toggle, .switch, .textField,
        .searchField, .slider, .stepper, .menuItem, .popUpButton, .menuButton,
    ]

    /// Returning true reports the issue without failing. Enforced: a description on every
    /// control a person acts on and on every Segue-identified element. Report-only (triaged
    /// in docs/release/accessibility-audit.md, section 6): contrast (sampled from screenshots;
    /// the token contrast test is the gate), missing actions on SwiftUI menu buttons,
    /// parent/child mismatches and anonymous SwiftUI layout groups, AppKit's Touch Bar and
    /// the system "emoji & symbols" item.
    static func ignoredIssue(_ issue: XCUIAccessibilityAuditIssue) -> Bool {
        let element = issue.element
        let identifier = element?.identifier ?? ""
        if testOnlyIdentifiers.contains(identifier) || element?.label == "emoji & symbols" {
            return true
        }
        guard issue.auditType == .sufficientElementDescription else { return true }
        let type = element?.elementType ?? .other
        return !(namedTypes.contains(type) || identifier.hasPrefix("segue."))
    }
}

/// Identifiers the audit walks (mirrors `AccessibilityID` in SegueUI).
enum AuditAXID {
    static let songRow = "segue.library.row"
    static let editSong = "segue.song.edit"
    static let editorDone = "segue.editor.done"
    static let editorModeText = "segue.editor.mode.text"
    static let editorModeVisual = "segue.editor.mode.visual"
    static let editorPill = "segue.editor.pill"
    static let sidebarSetlists = "segue.sidebar.setlists"
    static let sidebarGigLog = "segue.sidebar.gigLog"
    static let setlistRow = "segue.setlists.row"
    static let setlistEntry = "segue.setlist.entry"
    static let startShow = "segue.setlist.startShow"
    static let checklistStart = "segue.live.checklist.start"
    static let liveTitle = "segue.live.title"
    static let liveEndDialog = "segue.live.endDialog"
    static let welcomeTitle = "segue.welcome.title"
}
