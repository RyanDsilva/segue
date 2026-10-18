import AppKit
import XCTest

/// Menus, the main window and the About panel (WS2a 6.3, tests 14-16a).
@MainActor
extension SegueCoreUXE2ETests {
    func testHelpMenu() throws {
        try seedSong("harbour-lights", CoreFixture.harbour)
        let app = try launch()
        XCTAssertTrue(row(app, "Harbour Lights").waitForExistence(timeout: 15))

        let help = app.menuBars.menuBarItems["Help"]
        help.click(in: app)
        let titles = help.menuItems.allElementsBoundByIndex.map(\.title).filter { !$0.isEmpty }
        attachScreen(name: "help-menu")
        app.typeKey(.escape, modifierFlags: [], in: app)
        // Welcome to Segue… and Rate Segue on the App Store stay hidden in this build (their
        // hook and the App Store ID are unset).
        XCTAssertEqual(titles, CoreLinks.helpMenuTitles)

        for (title, url) in CoreLinks.helpLinks {
            menu(app, "Help", title)
            XCTAssertTrue(waitForWorkspace("open", [url]), "\(title): \(workspaceCalls())")
        }
        menu(app, "Help", "Report a Problem…")
        XCTAssertTrue(wait {
            self.workspaceCalls()
                .contains { $0.0 == "open" && $0.1.first?.hasPrefix(CoreLinks.supportMail) == true }
        })

        menu(app, "Help", "Keyboard Shortcuts")
        XCTAssertTrue(element(app, CoreAXID.shortcutsWindow).waitForExistence(timeout: 10))
        menu(app, "Help", "Acknowledgements")
        XCTAssertTrue(element(app, CoreAXID.acknowledgements).waitForExistence(timeout: 10))

        // File > Export Library Archive… waits for its hook (WS2b).
        app.menuBars.menuBarItems["File"].click(in: app)
        XCTAssertFalse(app.menuBars.menuItems["Export Library Archive…"].exists)
        app.typeKey(.escape, modifierFlags: [], in: app)

        // About: the panel with the version and the credits.
        app.menuBars.menuBarItems["Segue"].click(in: app)
        app.menuBars.menuItems["About Segue"].click(in: app)
        XCTAssertTrue(app.staticTexts["© 2026 Ryan Rony Dsilva"].waitForExistence(timeout: 10))
        attachScreen(name: "about-panel")
    }

    func testReopenMainWindow() throws {
        try seedSong("harbour-lights", CoreFixture.harbour)
        let app = try launch()
        let harbour = row(app, "Harbour Lights")
        XCTAssertTrue(harbour.waitForExistence(timeout: 15))

        // Window > Segue Library (exactly one such item).
        app.typeKey("w", modifierFlags: .command, in: app)
        XCTAssertTrue(harbour.waitForNonExistence(timeout: 10))
        let window = app.menuBars.menuBarItems["Window"]
        window.click()
        let items = window.menuItems.matching(NSPredicate(format: "title == %@", "Segue Library"))
        attachScreen(name: "window-menu")
        XCTAssertEqual(items.count, 1, "\(window.menuItems.allElementsBoundByIndex.map(\.title))")
        items.firstMatch.click()
        XCTAssertTrue(harbour.waitForExistence(timeout: 10), "Window > Segue Library")
        XCTAssertEqual(app.windows.count, 1)

        // Cmd-0.
        app.typeKey("w", modifierFlags: .command, in: app)
        XCTAssertTrue(harbour.waitForNonExistence(timeout: 10))
        app.typeKey("0", modifierFlags: .command)
        XCTAssertTrue(harbour.waitForExistence(timeout: 10), "Cmd-0")
        XCTAssertEqual(app.windows.count, 1)

        // A Dock click (a reopen event) with no window open.
        app.typeKey("w", modifierFlags: .command, in: app)
        XCTAssertTrue(harbour.waitForNonExistence(timeout: 10))
        try reopenFromDock()
        XCTAssertTrue(harbour.waitForExistence(timeout: 10), "Dock reopen")
        XCTAssertEqual(app.windows.count, 1)
    }

    func testSetlistMenuShortcuts() throws {
        try seedSong("harbour-lights", CoreFixture.harbour, id: CoreFixture.harbourID)
        try seedSetlist(
            "friday",
            id: CoreFixture.fridayID,
            name: "Friday",
            songIDs: [CoreFixture.harbourID],
        )
        let app = try launch()
        XCTAssertTrue(row(app, "Harbour Lights").waitForExistence(timeout: 15))

        // Outside a builder, Start Show is disabled.
        let setlistMenu = app.menuBars.menuBarItems["Setlist"]
        setlistMenu.click(in: app)
        XCTAssertFalse(setlistMenu.menuItems["Start Show"].isEnabled)
        attachScreen(name: "setlist-menu")
        app.typeKey(.escape, modifierFlags: [], in: app)

        element(app, CoreAXID.setlistRow).click(in: app)
        XCTAssertTrue(element(app, CoreAXID.setlistEntry).waitForExistence(timeout: 10))
        app.typeKey(.return, modifierFlags: .command, in: app)
        let checklist = element(app, CoreAXID.checklist)
        XCTAssertTrue(checklist.waitForExistence(timeout: 10), "Cmd-Return did not start")
        element(app, CoreAXID.checklistCancel).click(in: app)
        XCTAssertTrue(checklist.waitForNonExistence(timeout: 10))
        app.typeKey(.return, modifierFlags: [.command, .option], in: app)
        XCTAssertTrue(checklist.waitForExistence(timeout: 10), "Opt-Cmd-Return did not rehearse")
        element(app, CoreAXID.checklistCancel).click(in: app)
        XCTAssertTrue(checklist.waitForNonExistence(timeout: 10))

        app.typeKey("n", modifierFlags: [.command, .shift], in: app)
        XCTAssertTrue(element(app, CoreAXID.setlistNameField).waitForExistence(timeout: 10))
    }

    func testAddSelectedSongToSetlist() throws {
        try seedSong("harbour-lights", CoreFixture.harbour, id: CoreFixture.harbourID)
        try seedSetlist("friday", id: CoreFixture.fridayID, name: "Friday", songIDs: [])
        let app = try launch()
        let paths = try XCTUnwrap(paths)
        let setlistFile = paths.library.appending(path: "setlists/friday.setlist.json")
        let harbour = row(app, "Harbour Lights")
        XCTAssertTrue(harbour.waitForExistence(timeout: 15))
        harbour.click(in: app)

        menu(app, "Setlist", "Add Selected Song to Setlist", "Friday")
        // The 1.5 s confirmation first: the file wait below polls too slowly to see it.
        XCTAssertTrue(element(app, CoreAXID.transientMessage).waitForExistence(timeout: 5))
        attachScreenshot(app, name: "added-to-setlist")
        XCTAssertTrue(wait { self.entryCount(setlistFile) == 1 }, read(setlistFile))

        // The submenu now checks Friday; choosing it again adds another copy.
        let setlistMenu = app.menuBars.menuBarItems["Setlist"]
        setlistMenu.click(in: app)
        let submenu = setlistMenu.menuItems["Add Selected Song to Setlist"]
        submenu.hover()
        let friday = submenu.menuItems["Friday"]
        XCTAssertTrue(friday.waitForExistence(timeout: 5))
        // XCUITest does not expose a menu item's checkmark; the screenshot shows it.
        attachScreen(name: "add-to-setlist-submenu")
        friday.click()
        XCTAssertTrue(wait { self.entryCount(setlistFile) == 2 })

        // The same from the row's context menu.
        E2E.bringToFront(app)
        harbour.rightClick()
        let contextItem = app.menuItems[CoreAXID.addToSetlistMenu].firstMatch
        XCTAssertTrue(contextItem.waitForExistence(timeout: 5))
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
            XCTAssertTrue(item.waitForExistence(timeout: 5), "No \(menu) > \(title)")
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

    @MainActor
    func testKeyboardShortcutsWindow() throws {
        let app = try launch()
        XCTAssertTrue(element(app, CoreAXID.libraryEmpty).waitForExistence(timeout: 15))
        app.typeKey("/", modifierFlags: .command, in: app)
        let window = element(app, CoreAXID.shortcutsWindow)
        XCTAssertTrue(window.waitForExistence(timeout: 10))
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
    }
}
