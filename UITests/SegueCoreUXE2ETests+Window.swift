import AppKit
import XCTest

/// The main window's frame across launches (WS2a 3.5.5, spike 0d) and a real Finder drag
/// onto the library (3.2, spike 0c).
@MainActor
extension SegueCoreUXE2ETests {
    func testMainWindowFrameRestoredOnRelaunch() throws {
        try seedSong("harbour-lights", CoreFixture.harbour)
        let app = try launch()
        XCTAssertTrue(row(app, "Harbour Lights").waitForExistence(timeout: 15))
        let before = app.windows.firstMatch.frame

        // Move the window by its title bar towards the middle of the usable screen (AppKit
        // pulls a frame under the Dock or menu bar back in on launch, which is not what is
        // tested here), then shrink it from the bottom-right corner.
        let visible = try Self.visibleScreenRect()
        let move = CGVector(
            dx: before.midX < visible.midX ? 90 : -90,
            dy: before.midY < visible.midY ? 60 : -60,
        )
        let shrink = CGVector(dx: -120, dy: -80)
        reshape(app, move: move, resize: shrink)
        let moved = app.windows.firstMatch.frame
        XCTAssertNotEqual(moved, before, "the drags did not change the frame")
        XCTAssertTrue(visible.contains(moved), "moved \(moved) outside \(visible)")

        // Quit (Cmd-Q, so AppKit saves the frame), then relaunch without ignoring state.
        try quitAndRelaunchKeepingState(app)
        let restored = app.windows.firstMatch.frame
        attachScreenshot(app, name: "frame-restored")

        // Put the frame back before asserting, so later tests start from the usual one.
        reshape(
            app,
            move: CGVector(dx: -move.dx, dy: -move.dy),
            resize: CGVector(dx: -shrink.dx, dy: -shrink.dy),
        )
        app.typeKey("q", modifierFlags: .command, in: app)
        XCTAssertTrue(app.wait(for: .notRunning, timeout: 15))
        XCTAssertEqual(restored, moved, "before \(before), moved \(moved), restored \(restored)")
    }

    /// Drags the main window's title bar by `move`, then its bottom-right corner by `resize`.
    private func reshape(_ app: XCUIApplication, move: CGVector, resize: CGVector) {
        let window = app.windows.firstMatch
        E2E.bringToFront(app)
        let titleBar = window.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0))
            .withOffset(CGVector(dx: 0, dy: 14))
        titleBar.press(forDuration: 0.4, thenDragTo: titleBar.withOffset(move))
        let corner = window.coordinate(withNormalizedOffset: CGVector(dx: 1, dy: 1))
            .withOffset(CGVector(dx: -2, dy: -2))
        corner.press(forDuration: 0.4, thenDragTo: corner.withOffset(resize))
    }

    /// Quits with Cmd-Q and launches again on the same library and test defaults, without
    /// `-ApplePersistenceIgnoreState`.
    private func quitAndRelaunchKeepingState(_ app: XCUIApplication) throws {
        app.typeKey("q", modifierFlags: .command, in: app)
        XCTAssertTrue(app.wait(for: .notRunning, timeout: 15))
        let paths = try XCTUnwrap(paths)
        app.launchArguments = [
            "-SegueLibraryPath", paths.library.path(percentEncoded: false),
            "-SegueTrashPath", paths.trash.path(percentEncoded: false),
            "-SegueWorkspaceLog", paths.workspaceLog.path(percentEncoded: false),
            "-SegueTestDefaults", "YES",
            "-SegueUITesting", "YES",
        ]
        app.launch()
        E2E.bringToFront(app)
        XCTAssertTrue(row(app, "Harbour Lights").waitForExistence(timeout: 15))
    }

    /// The main screen minus the menu bar and Dock, in XCUITest's top-left coordinates.
    private static func visibleScreenRect() throws -> CGRect {
        let screen = try XCTUnwrap(NSScreen.screens.first)
        let visible = screen.visibleFrame
        return CGRect(
            x: visible.minX,
            y: screen.frame.maxY - visible.maxY,
            width: visible.width,
            height: visible.height,
        )
    }

    func testDragFromFinderImports() throws {
        try seedSong("harbour-lights", CoreFixture.harbour)
        let paths = try XCTUnwrap(paths)
        let source = paths.importSource
        let folder = source.appending(path: "gig-folder", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let file = source.appending(path: "river-song.chopro")
        try Data(CoreFixture.river.utf8).write(to: file)
        try Data("{title: Paper Moon}\n[C]Paper moon\n".utf8)
            .write(to: folder.appending(path: "paper-moon.cho"))

        let app = try launch()
        XCTAssertTrue(row(app, "Harbour Lights").waitForExistence(timeout: 15))

        // A file, then a folder, each dragged from a real Finder window onto the list.
        try dragFromFinder(file, onto: app)
        XCTAssertTrue(row(app, "River Song").waitForExistence(timeout: 10), "the file drop")
        try dragFromFinder(folder, onto: app)
        XCTAssertTrue(row(app, "Paper Moon").waitForExistence(timeout: 10), "the folder drop")
        attachScreenshot(app, name: "finder-drop")
        // Import copies: the dragged originals stay where they were.
        XCTAssertTrue(FileManager.default.fileExists(atPath: file.path(percentEncoded: false)))
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: folder.appending(path: "paper-moon.cho").path(percentEncoded: false),
        ))
    }

    /// Reveals `url` in a Finder window and drags its icon onto Segue's song list, at a
    /// point the Finder window does not cover; closes that Finder window afterwards.
    private func dragFromFinder(_ url: URL, onto app: XCUIApplication) throws {
        let list = element(app, CoreAXID.songList)
        XCTAssertTrue(list.waitForExistence(timeout: 5))
        let finder = XCUIApplication(bundleIdentifier: "com.apple.finder")
        NSWorkspace.shared.activateFileViewerSelecting([url])
        XCTAssertTrue(finder.wait(for: .runningForeground, timeout: 10))
        let name = url.lastPathComponent
        // The topmost match is the item itself: the path bar at the bottom names it too.
        let matches = finder.windows.firstMatch.descendants(matching: .any)
            .matching(NSPredicate(
                format: "title == %@ OR value == %@ OR label == %@",
                name,
                name,
                name,
            ))
        XCTAssertTrue(matches.firstMatch.waitForExistence(timeout: 10), "Finder shows no \(name)")
        let item = try XCTUnwrap(
            matches.allElementsBoundByIndex.filter { $0.frame.height > 0 }
                .min { $0.frame.minY < $1.frame.minY },
        )
        // Every Finder window counts: the user may have others open over Segue.
        let cover = finder.windows.allElementsBoundByIndex.map(\.frame)
        let area = list.frame
        let candidates = stride(from: 0.1, through: 0.9, by: 0.1).flatMap { dx in
            stride(from: 0.1, through: 0.9, by: 0.1).map { dy in CGVector(dx: dx, dy: dy) }
        }
        let offset = try XCTUnwrap(candidates.first { vector in
            let point = CGPoint(
                x: area.minX + area.width * vector.dx,
                y: area.minY + area.height * vector.dy,
            )
            return !cover.contains { $0.contains(point) }
        }, "Finder covers the whole list: \(cover) over \(area)")
        item.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).press(
            forDuration: 0.8,
            thenDragTo: list.coordinate(withNormalizedOffset: offset),
            withVelocity: .slow,
            thenHoldForDuration: 0.8,
        )
        finder.typeKey("w", modifierFlags: .command)
    }
}
