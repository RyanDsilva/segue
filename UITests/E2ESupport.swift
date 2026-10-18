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
            app.windows.firstMatch.appears(timeout: 15),
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
            app.reaches(.runningForeground, timeout: 15),
            "Segue did not become the frontmost app (state \(app.state.rawValue))",
            file: file,
            line: line,
        )
        XCTAssertTrue(
            app.windows.firstMatch.appears(timeout: 15),
            "Segue is frontmost but has no window on screen",
            file: file,
            line: line,
        )
    }
}

// MARK: - Waiting

/// The suite's one way to wait (docs/test-performance.md A1). XCTest's own waits
/// (`waitForExistence`, `XCTNSPredicateExpectation`, `XCUIApplication.wait(for:)`) re-check
/// about once a second, so a UI that is ready 100 ms later still costs a whole second; these
/// poll every `pollInterval` instead.
extension E2E {
    /// How often a wait re-checks its condition.
    nonisolated static let pollInterval: TimeInterval = 0.05

    /// Polls `condition` until it holds or `timeout` passes; true when it held. The run loop
    /// keeps turning between checks (workspace callbacks and the like still arrive).
    @discardableResult
    nonisolated static func waitUntil(
        timeout: TimeInterval = 10,
        _ condition: () throws -> Bool,
    ) rethrows -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while true {
            if try condition() {
                return true
            }
            if Date() >= deadline {
                return false
            }
            RunLoop.current.run(until: Date().addingTimeInterval(pollInterval))
        }
    }

    /// `waitUntil` that records a failure with `message` when the condition never held.
    @discardableResult
    nonisolated static func expect(
        _ message: @autoclosure () -> String,
        timeout: TimeInterval = 10,
        file: StaticString = #filePath,
        line: UInt = #line,
        _ condition: () throws -> Bool,
    ) -> Bool {
        let held = waitUntil(timeout: timeout) { (try? condition()) ?? false }
        if !held {
            XCTFail(message(), file: file, line: line)
        }
        return held
    }
}

extension E2E {
    /// Every element with `identifier` under `root`, in tree order, from one consistent
    /// snapshot. Reading `allElementsBoundByIndex` while a list re-renders (search
    /// filtering, a re-layout) can lose an element between the count and the read, which
    /// XCUITest reports as a failure; a snapshot cannot. An unavailable tree reads as empty.
    static func snapshots(
        _ root: XCUIElement,
        identifier: String,
    ) -> [any XCUIElementSnapshot] {
        guard let top = try? root.snapshot() else { return [] }
        var found: [any XCUIElementSnapshot] = []
        var stack: [any XCUIElementSnapshot] = [top]
        while let node = stack.popLast() {
            if node.identifier == identifier {
                found.append(node)
            }
            stack.append(contentsOf: node.children.reversed())
        }
        return found
    }
}

@MainActor
extension XCUIElement {
    /// Waits until the element exists (`waitForExistence`, polled fast).
    func appears(timeout: TimeInterval = 10) -> Bool {
        E2E.waitUntil(timeout: timeout) { exists }
    }

    /// Waits until the element is gone (`waitForNonExistence`, polled fast).
    func disappears(timeout: TimeInterval = 10) -> Bool {
        E2E.waitUntil(timeout: timeout) { !exists }
    }

    /// Waits until the element's frame stops changing (a panel sliding in, a list
    /// re-laying out), so a click lands where the element ends up.
    func settles(timeout: TimeInterval = 5) -> Bool {
        var last = CGRect.null
        return E2E.waitUntil(timeout: timeout) {
            let frame = exists ? self.frame : .null
            defer { last = frame }
            return !frame.isNull && frame == last
        }
    }

    /// Waits until the element exists with `value` as its accessibility value.
    func hasValue(_ value: String, timeout: TimeInterval = 10) -> Bool {
        E2E.waitUntil(timeout: timeout) { exists && self.value as? String == value }
    }
}

@MainActor
extension XCUIApplication {
    /// Waits for a process state (`wait(for:timeout:)`, polled fast).
    func reaches(_ state: XCUIApplication.State, timeout: TimeInterval = 10) -> Bool {
        E2E.waitUntil(timeout: timeout) { self.state == state }
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
