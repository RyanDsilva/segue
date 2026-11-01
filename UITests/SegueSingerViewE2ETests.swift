import XCTest

/// Singer view on stage (P9-2 section 16.4) on a fresh library: a song with a tempo, an
/// instrumental intro and chords inside romanized Hindi words, in a slot whose arrangement
/// shows the last chorus as Chords only. Rehearse the set: chords on stage; `v` hides every
/// chord, the split words read whole, the intro reads "Instrumental", the Singer chip shows
/// and the map keeps the same chips; `b` only explains itself; `v` brings the chords back.
final class SegueSingerViewE2ETests: SetlistE2ETestCase {
    private static let song = """
    {title: Dil Ki Raah}
    {artist: Mira Sen}
    {key: Am}
    {tempo: 88}

    {start_of_verse: Intro}
    [Am]  [G]  [F]  [E]
    {end_of_verse}

    {start_of_verse: Verse 1}
    Tu[Am]jh mein [G]rab dikh[F]ta hai
    [Am]Purani si gali mein [G]kitaabon ki du[F]kaan
    {end_of_verse}

    {start_of_chorus}
    Ke[F]sari[G]ya te[Am]ra
    [F]Har ek kahaani [G]mein teri [E]yaad
    {end_of_chorus}
    """

    @MainActor
    func testSingerViewOnStage() throws {
        let root = try XCTUnwrap(libraryRoot)
        try seed(root)
        let app = try launch()
        click(app, SingerAXID.sidebarSetlists)
        click(app, SingerAXID.setlistRow)
        E2E.bringToFront(app)
        app.typeKey(.return, modifierFlags: [.command, .option], in: app)
        click(app, SingerAXID.checklistStart)
        let title = app.staticTexts[SingerAXID.liveTitle]
        XCTAssertTrue(title.appears(timeout: 10), "the rehearsal never reached the stage")

        // Chords on stage, four passes on the map, the last one Chords only.
        SetlistE2E.waitUntil("no chords on stage") { Self.chords(app) > 0 }
        let chips = Self.chips(app)
        XCTAssertEqual(chips.count, 4, "\(chips)")
        XCTAssertFalse(SetlistE2E.element(app, SingerAXID.singerChip).exists)
        screenshot(app, "singer-view-chords")

        // V: lyrics only.
        E2E.bringToFront(app)
        app.typeKey("v", modifierFlags: [], in: app)
        XCTAssertTrue(SetlistE2E.element(app, SingerAXID.singerChip).appears(timeout: 5))
        SetlistE2E.waitUntil("chords still on stage in singer view") {
            Self.chords(app) == 0
        }
        let lyrics = SetlistE2E.texts(app, SingerAXID.lyric)
        XCTAssertTrue(lyrics.contains("Tujh mein rab dikhta hai"), "a split word: \(lyrics)")
        XCTAssertTrue(lyrics.contains("Kesariya tera"), "a split word in the chorus: \(lyrics)")
        XCTAssertTrue(lyrics.contains("Instrumental"), "the intro has no placeholder: \(lyrics)")
        XCTAssertEqual(Self.chips(app), chips, "the map changed")
        screenshot(app, "singer-view-lyrics")

        // B only explains itself.
        app.typeKey("b", modifierFlags: [], in: app)
        let indicator = SetlistE2E.element(app, SingerAXID.indicator)
        XCTAssertTrue(indicator.appears(timeout: 5))
        XCTAssertEqual(SetlistE2E.text(indicator), "Singer view hides chords (V shows them)")
        XCTAssertEqual(Self.chords(app), 0)

        // V again: the chords are back.
        app.typeKey("v", modifierFlags: [], in: app)
        SetlistE2E.waitUntil("the chords never came back") {
            Self.chords(app) > 0
        }
        XCTAssertTrue(SetlistE2E.element(app, SingerAXID.singerChip).disappears(timeout: 5))

        app.typeKey(".", modifierFlags: .command, in: app)
        XCTAssertTrue(SetlistE2E.element(app, SingerAXID.endDialog).appears(timeout: 5))
        app.typeKey(.return, modifierFlags: [], in: app)
        XCTAssertTrue(title.disappears(timeout: 10))
    }

    // MARK: Steps and helpers

    /// The song over the fixture's Dil Ki Raah (same id), in a setlist slot arranged Intro,
    /// Verse 1, Chorus, Chorus (Chords only).
    @MainActor
    private func seed(_ root: URL) throws {
        try SetlistFixture.write(Self.song, to: root.appending(path: "songs/dil-ki-raah.cho"))
        let song = SetlistFixture.song("Dil Ki Raah")
        try SetlistFixture.write(
            """
            {"schemaVersion": 7, "id": "01JC0000000000000000000F09", "name": "Friday",
             "entries": [{"itemId": "01JC0000000000000000000T09", "songId": "\(song.id)",
               "arrangement": {"passes": [
                 {"section": "Intro", "occurrence": 1},
                 {"section": "Verse 1", "occurrence": 1},
                 {"section": "Chorus", "occurrence": 1},
                 {"section": "Chorus", "occurrence": 1, "mode": "chords"}]}}]}
            """,
            to: root.appending(path: "setlists/friday.setlist.json"),
        )
    }

    /// The map's chip labels, in order.
    @MainActor
    private static func chips(_ app: XCUIApplication) -> [String] {
        (1 ... 9).map { SetlistE2E.element(app, SingerAXID.chip($0)) }
            .filter(\.exists)
            .map(\.label)
    }

    /// Chord runs on stage (the setlist page behind it shows none).
    @MainActor
    private static func chords(_ app: XCUIApplication) -> Int {
        SetlistE2E.texts(app, SingerAXID.chord).count
    }

    @MainActor
    private func click(_ app: XCUIApplication, _ identifier: String) {
        E2E.bringToFront(app)
        let element = SetlistE2E.element(app, identifier)
        XCTAssertTrue(element.appears(timeout: 10), "No \(identifier)")
        element.click(in: app)
    }
}

/// Mirrors `AccessibilityID+Singer` and the live IDs this suite reads.
enum SingerAXID {
    static let sidebarSetlists = "segue.sidebar.setlists"
    static let setlistRow = "segue.setlists.row"
    static let checklistStart = "segue.live.checklist.start"
    static let liveTitle = "segue.live.title"
    static let singerChip = "segue.live.singer"
    static let indicator = "segue.live.indicator"
    static let endDialog = "segue.live.endDialog"
    static let chord = "segue.sheet.chord"
    static let lyric = "segue.live.lyric"

    static func chip(_ number: Int) -> String {
        "segue.live.map.chip.\(number)"
    }
}
