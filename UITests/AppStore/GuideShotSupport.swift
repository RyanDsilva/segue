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
    class var windowSize: CGSize {
        CGSize(width: 1280, height: 800)
    }

    var windowFrame: String {
        "0,0,\(Int(Self.windowSize.width)),\(Int(Self.windowSize.height))"
    }

    /// Dates in the gig log and cards stay the same between runs.
    /// Friday 20 November 2026, 7:30 PM in California: a gig night.
    static let fixedClock = "2026-11-21T03:30:00Z"

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
            "-SegueWindowFrame", windowFrame,
            "-SegueStageWindowed", "YES",
            "-SegueFixedClock", Self.fixedClock,
            "-SegueGuideFixtures", "YES",
        ] + extra)
        // The frame is applied once the window exists: wait for it before driving the UI.
        let window = mainWindow(app)
        let size = Self.windowSize
        XCTAssertTrue(
            E2E.waitUntil(timeout: 10) {
                window.exists && abs(window.frame.width - size.width) < 2
                    && abs(window.frame.height - size.height) < 2
            },
            "the main window did not move to \(windowFrame)",
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
        clip: CGRect? = nil,
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
        if stage, let app {
            // The status line fades in on any mouse move and out 3 s later.
            let status = app.descendants(matching: .any)[GuideAXID.liveStatus]
            XCTAssertTrue(status.disappears(timeout: 6), "the stage status line stayed up")
        }
        _ = element.settles(timeout: 3)
        var frame = element.frame
        var png = element.screenshot().pngRepresentation
        if let clip {
            // Only this part of the element (a scroll view's frame can run past its sheet).
            frame = frame.intersection(clip)
            png = Self.screenCrop(frame) ?? png
        }
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

    /// `rect` (screen points) cut from a screenshot of the main screen, as PNG.
    @MainActor
    static func screenCrop(_ rect: CGRect) -> Data? {
        let shot = XCUIScreen.main.screenshot()
        guard let image = shot.image.cgImage(forProposedRect: nil, context: nil, hints: nil)
        else { return nil }
        // The screenshot is in pixels of the main screen; frames are in its points.
        let points = NSScreen.screens.first?.frame.width ?? shot.image.size.width
        let scale = Double(image.width) / points
        let pixels = CGRect(
            x: rect.minX * scale,
            y: rect.minY * scale,
            width: rect.width * scale,
            height: rect.height * scale,
        ).integral
        guard let cropped = image.cropping(to: pixels) else { return nil }
        return NSBitmapImageRep(cgImage: cropped).representation(using: .png, properties: [:])
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
    static let songCardLength = "segue.songCard.length"
    static let editSong = "segue.song.edit"
    static let editorVisual = "segue.editor.visual"
    static let editorTransposeUp = "segue.editor.transpose.up"
    static let sidebarSetlists = "segue.sidebar.setlists"
    static let setlistRow = "segue.setlists.row"
    static let setlistStartShow = "segue.setlist.startShow"
    static let newSetlistName = "segue.setlists.new.name"
    static let setlistComposer = "segue.setlist.composer"
    static let setlistComposerGhost = "segue.setlist.composer.ghost"
    static let checklistStart = "segue.live.checklist.start"
    static let liveTitle = "segue.live.title"
    static let liveSearch = "segue.live.search"
    static let liveEndDialog = "segue.live.endDialog"
    static let pasteSheet = "segue.paste.sheet"
    static let pasteCancel = "segue.paste.cancel"
    static let assistantBar = "segue.assistant.bar"
    static let assistantField = "segue.assistant.field"
    static let assistantBuild = "segue.assistant.build"
    static let assistantChip = "segue.assistant.chip"
    static let assistantChips = "segue.assistant.chips"
    static let assistantStatus = "segue.assistant.status"
    static let assistantBreakdown = "segue.assistant.breakdown"
    static let songCardTimeIt = "segue.songCard.timeIt"
    static let welcomeAddSongs = "segue.welcome.addSongs"
    static let editorTransposeDown = "segue.editor.transpose.down"
    static let editorDiagramsToggle = "segue.editor.diagrams"
    static let diagramStrip = "segue.diagrams.strip"
    static let sectionBand = "segue.editor.sectionBand"
    static let editorModeText = "segue.editor.mode.text"
    static let editorText = "segue.editor.text"
    static let slashMenu = "segue.editor.slashMenu"
    static let sectionNotesOpen = "segue.sectionNotes.open"
    static let sectionNotesAddChorus = "segue.sectionNotes.add.chorus"
    static let sectionNotesText = "segue.sectionNotes.note.text"
    static let sectionNotesDone = "segue.sectionNotes.done"
    static let liveCue = "segue.live.cue"
    static let liveView = "segue.live"
    static let liveBreak = "segue.live.break"
    static let liveStatus = "segue.live.status"
    static let liveSearchField = "segue.live.search.field"
    static let liveSearchResult = "segue.live.search.result"
    static let liveSearchNote = "segue.live.search.note"
    static let liveUpNext = "segue.live.upNext"
    static let liveRequestCount = "segue.live.requestCount"
    static let reorderDiscard = "segue.reorder.discard"
    static let pasteOriginal = "segue.paste.original"
    static let pasteResult = "segue.paste.result"
    static let pasteProvider = "segue.paste.provider"
    static let pasteRefining = "segue.paste.refining"
    static let pasteSectionLabel = "segue.paste.sectionLabel"
    static let pasteBatchRow = "segue.paste.batchRow"
    static let entryTitle = "segue.setlist.entry.title"
    static let builderLibraryRow = "segue.builder.library.row"
    static let setlistBreak = "segue.setlist.break"
    static let setlistTimeline = "segue.setlist.timeline"
    static let setlistUnknown = "segue.setlist.unknown"
    static let setlistTotal = "segue.setlist.total"
    static let missingLengths = "segue.setlist.missingLengths"
    static let arrangementOpen = "segue.setlist.arrangement.open"
    static let arrangementSheet = "segue.setlist.arrangement.sheet"
    static let arrangementDone = "segue.setlist.arrangement.done"
    static let newSmartFilter = "segue.sidebar.newSmartFilter"
    static let smartFilterName = "segue.smartFilter.name"
    static let smartFilterAddRow = "segue.smartFilter.addRow"
    static let smartFilterField = "segue.smartFilter.field"
    static let smartFilterAddKey = "segue.smartFilter.addKey"
    static let tagField = "segue.song.tag.field"
    static let sidebarGigLog = "segue.sidebar.gigLog"
    static let gigLogRow = "segue.gigLog.row"
    static let gigSummary = "segue.gig.summary"
    static let modelDownload = "segue.settings.ai.model.download"
    static let modelState = "segue.settings.ai.model.state"
    static let editorPill = "segue.editor.pill"
    static let editorNashville = "segue.editor.display.nashville"
    static let settingsMinLyricSize = "segue.settings.live.minLyricSize"

    /// A song card token chip (`key`, `tempo`, `length`, `capo`, `time`).
    static func cardToken(_ field: String) -> String {
        "segue.songCard.token.\(field)"
    }
}
