import XCTest

/// The stage map, section jump and the rehearsal loop on a single song from the library
/// (P8-2, R147, R148, R150), on a fresh library: select a song with three choruses (two
/// written, one `{chorus}`) and a tempo, Rehearse (⌥⌘↩) with no checklist, the map shows
/// "Chorus 1/3" ... "Chorus 3/3" and the "2 of 3" badges with no "Repeat chorus", 3 jumps
/// with a confirmation, L loops, ⌘. ends, and nothing reaches `shows/` or the Gig Log.
final class SegueStageMapE2ETests: SetlistE2ETestCase {
    private static let song = """
    {title: Harbor Lights}
    {artist: The Lanterns}
    {key: G}
    {tempo: 96}

    {start_of_verse: Verse 1}
    [G]Lanterns on the water, boats come drifting in
    [C]Ropes against the harbor wall, the evening coming in
    {end_of_verse}

    {start_of_chorus}
    [C]Hold on, harbor lights
    [G]Bring the fishing boats home
    {end_of_chorus}

    {start_of_verse: Verse 2}
    [G]Salt upon my collar and the tide is turning thin
    {end_of_verse}

    {chorus}

    {start_of_bridge}
    [Em]Somewhere past the breakwater
    {end_of_bridge}

    {start_of_chorus}
    [C]Hold on, harbor lights
    [G]Bring us all back home
    {end_of_chorus}
    """

    @MainActor
    func testRehearseOneSongJumpAndLoop() throws {
        let root = try XCTUnwrap(libraryRoot)
        try SetlistFixture.write(Self.song, to: root.appending(path: "songs/harbor-lights.cho"))
        let showsBefore = Self.showFiles(root)
        let app = try launch()

        // Select the song in the library and rehearse it: no pre-show checklist.
        click(app, SetlistAXID.sidebarLibrary)
        let row = SetlistE2E.row(app, SetlistAXID.songRow, "Harbor Lights")
        XCTAssertTrue(row.appears(timeout: 10), "Harbor Lights is not listed")
        row.click(in: app)
        XCTAssertTrue(SetlistE2E.element(app, StageMapAXID.rehearseButton).appears(timeout: 5))
        E2E.bringToFront(app)
        app.typeKey(.return, modifierFlags: [.command, .option], in: app)
        let title = app.staticTexts[StageMapAXID.liveTitle]
        XCTAssertTrue(title.appears(timeout: 10), "the stage never opened")
        XCTAssertFalse(SetlistE2E.element(app, StageMapAXID.checklistStart).exists)
        try mapJumpAndLoop(app)

        // ⌘. and Return: back in the library, nothing written, nothing in the Gig Log.
        app.typeKey(".", modifierFlags: .command, in: app)
        XCTAssertTrue(SetlistE2E.element(app, StageMapAXID.endDialog).appears(timeout: 5))
        app.typeKey(.return, modifierFlags: [], in: app)
        XCTAssertTrue(title.disappears(timeout: 10))
        XCTAssertTrue(row.appears(timeout: 5))
        XCTAssertEqual(Self.showFiles(root), showsBefore, "a show file was written")
        click(app, SetlistAXID.sidebarGigLog)
        XCTAssertFalse(
            SetlistE2E.element(app, SetlistAXID.gigLogRow).appears(timeout: 2),
            "the single song went into the Gig Log",
        )
    }

    /// The map, 3 to jump, L to loop.
    @MainActor
    private func mapJumpAndLoop(_ app: XCUIApplication) throws {
        // The map: every pass written out, the choruses numbered, badges in the gutter.
        XCTAssertTrue(SetlistE2E.element(app, StageMapAXID.map).appears(timeout: 5))
        let labels = (1 ... 6).map { SetlistE2E.element(app, StageMapAXID.chip($0)).label }
        XCTAssertEqual(labels, [
            "Verse 1", "Chorus, 1 of 3", "Verse 2", "Chorus, 2 of 3", "Bridge", "Chorus, 3 of 3",
        ])
        XCTAssertTrue(SetlistE2E.element(app, StageMapAXID.badge(4)).exists, "no 2 of 3 badge")
        // On the stage window (the library behind it previews the song as written).
        let stage = app.windows.containing(.any, identifier: StageMapAXID.liveTitle).firstMatch
        XCTAssertEqual(
            stage.staticTexts.matching(NSPredicate(format: "value == 'Repeat chorus'")).count,
            0,
            "A repeat is collapsed on stage",
        )
        screenshot(app, "stage-map-rehearse")

        // 3 jumps to Verse 2: the confirmation shows and its chip is current.
        E2E.bringToFront(app)
        app.typeKey("3", modifierFlags: [], in: app)
        let toast = SetlistE2E.element(app, StageMapAXID.jumped)
        XCTAssertTrue(toast.appears(timeout: 5), "no jump confirmation")
        XCTAssertEqual(SetlistE2E.text(toast), "Jumped to Verse 2")
        let chip = SetlistE2E.element(app, StageMapAXID.chip(3))
        SetlistE2E.waitUntil("chip 3 never read current") {
            (chip.value as? String)?.hasPrefix("current") == true
        }
        screenshot(app, "stage-map-jumped")

        // L loops Verse 2: the header pill appears.
        app.typeKey("l", modifierFlags: [], in: app)
        let pill = SetlistE2E.element(app, StageMapAXID.loop)
        XCTAssertTrue(pill.appears(timeout: 5), "no loop pill")
        SetlistE2E.waitUntil("chip 3 never read looping") {
            (chip.value as? String) == "current, looping"
        }
        screenshot(app, "stage-map-loop")
    }

    // MARK: Helpers

    @MainActor
    private func click(_ app: XCUIApplication, _ identifier: String) {
        E2E.bringToFront(app)
        let element = SetlistE2E.element(app, identifier)
        XCTAssertTrue(element.appears(timeout: 10), "No \(identifier)")
        element.click(in: app)
    }

    private static func showFiles(_ root: URL) -> [String] {
        let folder = root.appending(path: "shows", directoryHint: .isDirectory)
        let names = (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
        return names.filter { $0.hasSuffix(".show.json") }.sorted()
    }
}

/// Mirrors `AccessibilityID+StageMap` and the live IDs this suite reads.
enum StageMapAXID {
    static let rehearseButton = "segue.library.song.rehearse"
    static let liveButton = "segue.library.song.live"
    static let liveTitle = "segue.live.title"
    static let checklistStart = "segue.live.checklist.start"
    static let map = "segue.live.map"
    static let jumped = "segue.live.jumped"
    static let loop = "segue.live.loop"
    static let endDialog = "segue.live.endDialog"

    static func chip(_ number: Int) -> String {
        "segue.live.map.chip.\(number)"
    }

    static func badge(_ number: Int) -> String {
        "segue.live.passBadge.\(number)"
    }
}
