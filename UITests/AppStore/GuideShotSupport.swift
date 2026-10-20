import AppKit
import XCTest

/// The capture layer for the user guide (WS6 section 5) and, later, the store screenshots
/// (WS5 section 8): the App Store flavour on a clean Welcome library (`-SegueScreenshotLibrary`),
/// at a fixed window frame and clock, in the appearance `make docs-shots` asks for.
///
/// Each shot is an attachment named `guide-<id>-<appearance>` (PNG, Retina) plus
/// `guide-<id>-<appearance>.frames` (JSON: callout target frames as fractions of the shot),
/// which `scripts/docs-shots.swift` turns into `guide/public/shots/*.avif` and
/// `guide/src/data/shots.json`. Stage shots exist once (the stage is always dark): they are
/// taken only in the dark run and named `guide-<id>-stage`.
class GuideShotCase: XCTestCase {
    /// The main window frame in points, top-left origin at the screen's visible area (clear
    /// of the menu bar and Dock), WS6 5.3: 2560x1600 px on Retina.
    static let windowFrame = "0,0,1280,800"
    /// Dates in the gig log and cards stay the same between runs.
    static let fixedClock = "2026-11-20T20:00:00Z"

    var app: XCUIApplication?

    /// `dark` or `light`, from `TEST_RUNNER_SEGUE_SHOT_APPEARANCE` (make docs-shots).
    var appearance: String {
        ProcessInfo.processInfo.environment["SEGUE_SHOT_APPEARANCE"] ?? "dark"
    }

    var isDarkRun: Bool {
        appearance == "dark"
    }

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    override func tearDownWithError() throws {
        E2E.terminate(app)
    }

    /// Launches the App Store flavour on the screenshot library.
    @MainActor
    func launch(_ extra: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        self.app = app
        E2E.launch(app, arguments: [
            "-SegueScreenshotLibrary", "YES",
            "-SegueResetState", "YES",
            "-SegueAppearance", appearance,
            "-SegueWindowFrame", Self.windowFrame,
            "-SegueStageWindowed", "YES",
            "-SegueFixedClock", Self.fixedClock,
        ] + extra)
        // The frame is applied once the window exists: wait for it before driving the UI.
        let window = mainWindow(app)
        XCTAssertTrue(
            E2E.waitUntil(timeout: 10) {
                window
                    .exists && abs(window.frame.width - 1280) < 2 && abs(
                        window.frame.height - 800,
                    ) <
                    2
            },
            "the main window did not move to \(Self.windowFrame)",
        )
        return app
    }

    /// The first element with `identifier`, failing the run if it never appears.
    @MainActor
    func element(
        _ app: XCUIApplication,
        _ identifier: String,
        file: StaticString = #filePath,
        line: UInt = #line,
    ) -> XCUIElement {
        let element = app.descendants(matching: .any).matching(identifier: identifier).firstMatch
        XCTAssertTrue(element.appears(timeout: 15), "no \(identifier)", file: file, line: line)
        return element
    }

    /// Captures `element` as shot `id`, with the frames of `callouts` (name -> element).
    /// `stage: true` shots are taken in the dark run only.
    @MainActor
    func shoot(
        _ id: String,
        _ element: XCUIElement,
        callouts: [String: XCUIElement] = [:],
        stage: Bool = false,
        file: StaticString = #filePath,
        line: UInt = #line,
    ) {
        if stage, !isDarkRun {
            return
        }
        // Settle: no hover highlight, no half-finished animation.
        if let app {
            mainWindow(app).coordinate(withNormalizedOffset: .zero)
                .withOffset(CGVector(dx: -12, dy: -12)).hover()
        }
        _ = element.settles(timeout: 3)
        let frame = element.frame
        let screenshot = element.screenshot()
        let png = screenshot.pngRepresentation
        let pixels = NSBitmapImageRep(data: png).map { ($0.pixelsWide, $0.pixelsHigh) } ?? (0, 0)
        XCTAssertEqual(
            Double(pixels.0),
            frame.width * 2,
            accuracy: 4,
            "shot \(id) is \(pixels.0) px wide for \(frame.width) pt: not a Retina capture",
            file: file,
            line: line,
        )
        let name = "guide-\(id)-\(stage ? "stage" : appearance)"
        let image = XCTAttachment(data: png, uniformTypeIdentifier: "public.png")
        image.name = name
        image.lifetime = .keepAlways
        add(image)

        var frames: [String: [String: Double]] = [:]
        for (callout, target) in callouts where target.exists {
            let rect = target.frame
            frames[callout] = [
                "x": (rect.minX - frame.minX) / frame.width,
                "y": (rect.minY - frame.minY) / frame.height,
                "w": rect.width / frame.width,
                "h": rect.height / frame.height,
            ]
        }
        if let data = try? JSONSerialization.data(withJSONObject: frames, options: [.sortedKeys]) {
            let attachment = XCTAttachment(data: data, uniformTypeIdentifier: "public.json")
            attachment.name = "\(name).frames"
            attachment.lifetime = .keepAlways
            add(attachment)
        }
    }

    /// The main window.
    @MainActor
    func mainWindow(_ app: XCUIApplication) -> XCUIElement {
        app.windows.matching(NSPredicate(format: "identifier BEGINSWITH %@", GuideAXID.mainWindow))
            .firstMatch
    }

    /// A clip marker (`clip-start`, `clip-end`): the wall-clock time as an attachment, so
    /// `scripts/docs-clips-encode.sh` cuts the recording to the storyboard.
    @MainActor
    func mark(_ name: String) {
        let attachment = XCTAttachment(string: String(format: "%.3f", Date().timeIntervalSince1970))
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    /// Paced holds for the clips (`make docs-clips`): the one place a timed wait is right.
    @MainActor
    func hold(_ seconds: TimeInterval) {
        let done = expectation(description: "hold")
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds) { done.fulfill() }
        wait(for: [done], timeout: seconds + 5)
    }
}

/// Identifiers the guide captures use (mirrors `AccessibilityID` in SegueUI, which the UI
/// test target cannot import).
enum GuideAXID {
    /// The main window scene's id (`SegueRootView.windowID`); SwiftUI prefixes the window
    /// identifier with it.
    static let mainWindow = "segue.main"
    static let songList = "segue.library.list"
    static let songRow = "segue.library.row"
    static let librarySearch = "segue.library.search"
    static let newSong = "segue.library.newSong"
    static let songCard = "segue.songCard"
    static let songCardTempo = "segue.songCard.tempo"
    static let songCardLength = "segue.songCard.length"
    static let songCardKeyMode = "segue.songCard.keyMode"
    static let editSong = "segue.song.edit"
    static let editorVisual = "segue.editor.visual"
    static let editorTransposeUp = "segue.editor.transpose.up"
    static let sidebarSetlists = "segue.sidebar.setlists"
    static let setlistRow = "segue.setlists.row"
    static let setlistStartShow = "segue.setlist.startShow"
    static let checklistStart = "segue.live.checklist.start"
    static let liveTitle = "segue.live.title"
    static let liveSearch = "segue.live.search"
    static let liveEndDialog = "segue.live.endDialog"
    static let pasteSheet = "segue.paste.sheet"
    static let pasteCancel = "segue.paste.cancel"
    static let assistantBar = "segue.assistant.bar"
    static let assistantField = "segue.assistant.field"
    static let assistantBuild = "segue.assistant.build"
}
