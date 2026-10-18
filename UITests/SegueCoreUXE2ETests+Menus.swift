import AppKit
import XCTest

/// Menus, the main window and the About panel (WS2a 6.3, tests 14-16a).
@MainActor
extension SegueCoreUXE2ETests {
    /// One scenario over the menu bar (B2: these shared their setup): the Help menu, the
    /// Keyboard Shortcuts and Acknowledgements windows, the About panel, the Setlist menu's
    /// keys, then closing and reopening the main window. What each Help link opens is
    /// checked in process (`HelpMenuTests`); one link is clicked here to prove the wiring.
    func testMenus() throws {
        try seedSong("harbour-lights", CoreFixture.harbour, id: CoreFixture.harbourID)
        try seedSetlist(
            "friday",
            id: CoreFixture.fridayID,
            name: "Friday",
            songIDs: [CoreFixture.harbourID],
        )
        let app = try launch()
        XCTAssertTrue(row(app, "Harbour Lights").appears(timeout: 15))

        helpMenu(app)
        shortcutsAndAcknowledgements(app)
        fileMenuAndAbout(app)
        setlistMenuKeys(app)
        try reopenMainWindow(app)
    }

    /// Help: the canonical items, and one link click through the recorded workspace.
    private func helpMenu(_ app: XCUIApplication) {
        let help = app.menuBars.menuBarItems["Help"]
        help.click(in: app)
        let titles = help.menuItems.allElementsBoundByIndex.map(\.title).filter { !$0.isEmpty }
        attachScreen(name: "help-menu")
        app.typeKey(.escape, modifierFlags: [], in: app)
        // Welcome to Segue… and Rate Segue on the App Store stay hidden in this build (their
        // hook and the App Store ID are unset).
        XCTAssertEqual(titles, CoreLinks.helpMenuTitles)

        let (title, url) = CoreLinks.helpLinks[0]
        menu(app, "Help", title)
        XCTAssertTrue(waitForWorkspace("open", [url]), "\(title): \(workspaceCalls())")
    }

    /// Help > Keyboard Shortcuts and Help > Acknowledgements, each closed again.
    private func shortcutsAndAcknowledgements(_ app: XCUIApplication) {
        menu(app, "Help", "Keyboard Shortcuts")
        let window = element(app, CoreAXID.shortcutsWindow)
        XCTAssertTrue(window.appears(timeout: 10))
        XCTAssertTrue(element(app, CoreAXID.shortcutsMainSection).exists)
        XCTAssertTrue(element(app, CoreAXID.shortcutsStageSection).exists)
        // A main-window row matches the menu: Start Show is Cmd-Return.
        let rows = window.descendants(matching: .staticText)
        let startShow = rows.matching(NSPredicate(
            format: "label CONTAINS %@ OR value CONTAINS %@",
            "Start Show",
            "Start Show",
        ))
        .firstMatch
        XCTAssertTrue(startShow.exists)
        let row = startShow.label + (startShow.value as? String ?? "")
        XCTAssertTrue(row.contains("⌘↩"), row)
        // And a stage row comes from the bindings.
        XCTAssertTrue(rows.matching(NSPredicate(
            format: "label CONTAINS %@ OR value CONTAINS %@",
            "Page, Then Next Song",
            "Page, Then Next Song",
        ))
        .firstMatch.exists)
        attachScreen(name: "keyboard-shortcuts-window")
        app.typeKey("w", modifierFlags: .command, in: app)
        XCTAssertTrue(window.disappears(timeout: 10))

        // Acknowledgements (moved from the app menu, A34) credits the bundled font and
        // dependencies.
        menu(app, "Help", "Acknowledgements")
        let acknowledgements = element(app, CoreAXID.acknowledgements)
        XCTAssertTrue(acknowledgements.appears(timeout: 10))
        for name in ["Schibsted Grotesk", "GRDB", "Tonic"] {
            XCTAssertTrue(acknowledgements.staticTexts[name].exists, "\(name) not credited")
        }
        let ofl = NSPredicate(format: "value BEGINSWITH %@", "SIL Open Font License 1.1")
        XCTAssertTrue(acknowledgements.staticTexts.matching(ofl).firstMatch.exists)
        let credits = XCTAttachment(screenshot: app.windows["Acknowledgements"].screenshot())
        credits.name = "acknowledgements"
        credits.lifetime = .keepAlways
        add(credits)
        app.typeKey("w", modifierFlags: .command, in: app)
        XCTAssertTrue(acknowledgements.disappears(timeout: 10))
    }

    /// File > Export Library Archive… waits for its hook (WS2b); About shows the panel with
    /// the version and the credits.
    private func fileMenuAndAbout(_ app: XCUIApplication) {
        app.menuBars.menuBarItems["File"].click(in: app)
        XCTAssertFalse(app.menuBars.menuItems["Export Library Archive…"].exists)
        app.typeKey(.escape, modifierFlags: [], in: app)

        app.menuBars.menuBarItems["Segue"].click(in: app)
        app.menuBars.menuItems["About Segue"].click(in: app)
        let copyright = app.staticTexts["© 2026 Ryan Rony Dsilva"]
        XCTAssertTrue(copyright.appears(timeout: 10))
        attachScreen(name: "about-panel")
        app.typeKey("w", modifierFlags: .command, in: app)
        XCTAssertTrue(copyright.disappears(timeout: 10))
    }

    /// Setlist: Start Show is disabled outside a builder; in one, Cmd-Return starts,
    /// Opt-Cmd-Return rehearses (each up to the checklist) and Shift-Cmd-N names a new set.
    private func setlistMenuKeys(_ app: XCUIApplication) {
        let setlistMenu = app.menuBars.menuBarItems["Setlist"]
        setlistMenu.click(in: app)
        XCTAssertFalse(setlistMenu.menuItems["Start Show"].isEnabled)
        attachScreen(name: "setlist-menu")
        app.typeKey(.escape, modifierFlags: [], in: app)

        element(app, CoreAXID.setlistRow).click(in: app)
        XCTAssertTrue(element(app, CoreAXID.setlistEntry).appears(timeout: 10))
        app.typeKey(.return, modifierFlags: .command, in: app)
        let checklist = element(app, CoreAXID.checklist)
        XCTAssertTrue(checklist.appears(timeout: 10), "Cmd-Return did not start")
        element(app, CoreAXID.checklistCancel).click(in: app)
        XCTAssertTrue(checklist.disappears(timeout: 10))
        app.typeKey(.return, modifierFlags: [.command, .option], in: app)
        XCTAssertTrue(checklist.appears(timeout: 10), "Opt-Cmd-Return did not rehearse")
        element(app, CoreAXID.checklistCancel).click(in: app)
        XCTAssertTrue(checklist.disappears(timeout: 10))

        app.typeKey("n", modifierFlags: [.command, .shift], in: app)
        let name = element(app, CoreAXID.setlistNameField)
        XCTAssertTrue(name.appears(timeout: 10))
        app.typeKey(.escape, modifierFlags: [], in: app)
        XCTAssertTrue(name.disappears(timeout: 10))
    }

    /// Window > Segue Library (exactly one such item), Cmd-0 and a Dock click each bring the
    /// closed main window back, never a second one.
    private func reopenMainWindow(_ app: XCUIApplication) throws {
        element(app, CoreAXID.sidebarLibrary).click(in: app)
        let harbour = row(app, "Harbour Lights")
        XCTAssertTrue(harbour.appears(timeout: 10))
        XCTAssertEqual(app.windows.count, 1)

        app.typeKey("w", modifierFlags: .command, in: app)
        XCTAssertTrue(harbour.disappears(timeout: 10))
        let window = app.menuBars.menuBarItems["Window"]
        window.click()
        let items = window.menuItems.matching(NSPredicate(format: "title == %@", "Segue Library"))
        attachScreen(name: "window-menu")
        XCTAssertEqual(items.count, 1, "\(window.menuItems.allElementsBoundByIndex.map(\.title))")
        items.firstMatch.click()
        XCTAssertTrue(harbour.appears(timeout: 10), "Window > Segue Library")
        XCTAssertEqual(app.windows.count, 1)

        app.typeKey("w", modifierFlags: .command, in: app)
        XCTAssertTrue(harbour.disappears(timeout: 10))
        app.typeKey("0", modifierFlags: .command)
        XCTAssertTrue(harbour.appears(timeout: 10), "Cmd-0")
        XCTAssertEqual(app.windows.count, 1)

        // A Dock click (a reopen event) with no window open.
        app.typeKey("w", modifierFlags: .command, in: app)
        XCTAssertTrue(harbour.disappears(timeout: 10))
        try reopenFromDock()
        XCTAssertTrue(harbour.appears(timeout: 10), "Dock reopen")
        XCTAssertEqual(app.windows.count, 1)
    }

    func testAddSelectedSongToSetlist() throws {
        try seedSong("harbour-lights", CoreFixture.harbour, id: CoreFixture.harbourID)
        try seedSetlist("friday", id: CoreFixture.fridayID, name: "Friday", songIDs: [])
        let app = try launch()
        let paths = try XCTUnwrap(paths)
        let setlistFile = paths.library.appending(path: "setlists/friday.setlist.json")
        let harbour = row(app, "Harbour Lights")
        XCTAssertTrue(harbour.appears(timeout: 15))
        harbour.click(in: app)

        menu(app, "Setlist", "Add Selected Song to Setlist", "Friday")
        // The 1.5 s confirmation first: the file wait below polls too slowly to see it.
        XCTAssertTrue(element(app, CoreAXID.transientMessage).appears(timeout: 5))
        attachScreenshot(app, name: "added-to-setlist")
        XCTAssertTrue(wait { self.entryCount(setlistFile) == 1 }, read(setlistFile))

        // The submenu now checks Friday; choosing it again adds another copy.
        let setlistMenu = app.menuBars.menuBarItems["Setlist"]
        setlistMenu.click(in: app)
        let submenu = setlistMenu.menuItems["Add Selected Song to Setlist"]
        submenu.hover()
        let friday = submenu.menuItems["Friday"]
        XCTAssertTrue(friday.appears(timeout: 5))
        // XCUITest does not expose a menu item's checkmark; the screenshot shows it.
        attachScreen(name: "add-to-setlist-submenu")
        friday.click()
        XCTAssertTrue(wait { self.entryCount(setlistFile) == 2 })

        // The same from the row's context menu.
        E2E.bringToFront(app)
        harbour.rightClick()
        let contextItem = app.menuItems[CoreAXID.addToSetlistMenu].firstMatch
        XCTAssertTrue(contextItem.appears(timeout: 5))
        contextItem.hover()
        app.menuItems["Friday"].firstMatch.click()
        XCTAssertTrue(wait { self.entryCount(setlistFile) == 3 })

        // Edit > Undo ("Add Song") takes the last copy out again.
        harbour.click(in: app)
        app.typeKey("z", modifierFlags: .command, in: app)
        XCTAssertTrue(wait { self.entryCount(setlistFile) == 2 }, "Undo Add Song")
    }
}

extension SegueCoreUXE2ETests {
    /// Chooses `path` (menu, item, submenu item...) from the menu bar.
    @MainActor
    func menu(_ app: XCUIApplication, _ menu: String, _ path: String...) {
        let bar = app.menuBars.menuBarItems[menu]
        bar.click(in: app)
        var current: XCUIElement = bar
        for (index, title) in path.enumerated() {
            let item = current.menuItems[title].firstMatch
            XCTAssertTrue(item.appears(timeout: 5), "No \(menu) > \(title)")
            if index == path.count - 1 {
                item.click()
            } else {
                item.hover()
            }
            current = item
        }
    }

    /// The whole screen (menus and panels live outside the window).
    @MainActor
    func attachScreen(name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    /// Sends Segue a reopen event, as a Dock click does.
    func reopenFromDock() throws {
        let running = NSRunningApplication.runningApplications(
            withBundleIdentifier: "dev.ryandsilva.segue.personal",
        )
        let url = try XCTUnwrap(running.first?.bundleURL)
        let done = expectation(description: "reopen sent")
        NSWorkspace.shared.openApplication(at: url, configuration: .init()) { _, _ in
            done.fulfill()
        }
        wait(for: [done], timeout: 10)
    }

    /// Entries in a setlist file.
    func entryCount(_ url: URL) -> Int {
        guard let data = try? Data(contentsOf: url),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let entries = object["entries"] as? [Any]
        else { return -1 }
        return entries.count
    }
}
