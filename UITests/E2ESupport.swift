import XCTest

/// Launching and driving Segue on a shared desktop.
///
/// The E2E suite runs on the developer's own Mac, where another app is usually in use (an
/// editor in a full-screen Space, a permission dialog parked on screen). macOS's cooperative
/// activation does not hand focus to an app that is launched or relaunched while the user
/// works elsewhere: Segue then opens its window on another Space, its accessibility tree
/// has no window, and synthesized keystrokes time out because nothing in Segue is key.
/// So every launch waits until Segue is frontmost with a window, and every synthesized
/// click, drag and keystroke first re-asserts that, instead of assuming focus or a window
/// position.
@MainActor
enum E2E {
    /// Arguments every test launch carries: no restored windows from an earlier run (each
    /// test starts from a fresh app instance, not from the last test's window state), and
    /// the test-only instrumentation switched on (`UITesting` in SegueUI).
    static let freshInstanceArguments = [
        "-ApplePersistenceIgnoreState", "YES",
        "-SegueUITesting", "YES",
    ]

    /// Launches a fresh instance with `arguments` and waits until it is frontmost with its
    /// window in the accessibility tree.
    static func launch(
        _ app: XCUIApplication,
        arguments: [String],
        file: StaticString = #filePath,
        line: UInt = #line,
    ) {
        app.launchArguments = arguments + freshInstanceArguments
        app.launch()
        bringToFront(app, file: file, line: line)
        XCTAssertTrue(
            app.windows.firstMatch.waitForExistence(timeout: 15),
            "Segue launched without a window on screen",
            file: file,
            line: line,
        )
    }

    /// Test tear-down: quits a still-running instance so the next test starts fresh.
    nonisolated static func terminate(_ app: XCUIApplication?) {
        MainActor.assumeIsolated {
            if let app, app.state != .notRunning {
                app.terminate()
            }
        }
    }

    /// Makes Segue the active app (macOS switches to the Space holding its window) and
    /// waits until it is frontmost and its window is in the accessibility tree.
    static func bringToFront(
        _ app: XCUIApplication,
        file: StaticString = #filePath,
        line: UInt = #line,
    ) {
        // Fast path: already frontmost (a process-state read, no accessibility query).
        if app.state == .runningForeground {
            return
        }
        app.activate()
        XCTAssertTrue(
            app.wait(for: .runningForeground, timeout: 15),
            "Segue did not become the frontmost app (state \(app.state.rawValue))",
            file: file,
            line: line,
        )
        XCTAssertTrue(
            app.windows.firstMatch.waitForExistence(timeout: 15),
            "Segue is frontmost but has no window on screen",
            file: file,
            line: line,
        )
    }
}

/// Synthesized input that first makes sure Segue is frontmost (see `E2E`).
@MainActor
extension XCUIElement {
    func click(in app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) {
        E2E.bringToFront(app, file: file, line: line)
        click()
    }

    /// Types `text` a line at a time, re-asserting focus between lines, so a long text
    /// never runs on after another app took the keyboard.
    func typeText(
        _ text: String,
        in app: XCUIApplication,
        file: StaticString = #filePath,
        line: UInt = #line,
    ) {
        var chunks: [String] = []
        var current = ""
        for character in text {
            current.append(character)
            if character == "\n" {
                chunks.append(current)
                current = ""
            }
        }
        if !current.isEmpty {
            chunks.append(current)
        }
        for chunk in chunks {
            E2E.bringToFront(app, file: file, line: line)
            typeText(chunk)
        }
    }

    func typeKey(
        _ key: XCUIKeyboardKey,
        modifierFlags: XCUIElement.KeyModifierFlags,
        in app: XCUIApplication,
        file: StaticString = #filePath,
        line: UInt = #line,
    ) {
        E2E.bringToFront(app, file: file, line: line)
        typeKey(key, modifierFlags: modifierFlags)
    }

    func typeKey(
        _ key: String,
        modifierFlags: XCUIElement.KeyModifierFlags,
        in app: XCUIApplication,
        file: StaticString = #filePath,
        line: UInt = #line,
    ) {
        E2E.bringToFront(app, file: file, line: line)
        typeKey(key, modifierFlags: modifierFlags)
    }
}

@MainActor
extension XCUICoordinate {
    func click(in app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) {
        E2E.bringToFront(app, file: file, line: line)
        click()
    }

    func press(
        forDuration duration: TimeInterval,
        thenDragTo other: XCUICoordinate,
        in app: XCUIApplication,
        file: StaticString = #filePath,
        line: UInt = #line,
    ) {
        E2E.bringToFront(app, file: file, line: line)
        press(forDuration: duration, thenDragTo: other)
    }
}
