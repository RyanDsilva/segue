import AppKit
import XCTest

// MARK: - Helpers

@MainActor
extension GuideShotCase {
    /// A library row whose label starts with `title`.
    func song(_ app: XCUIApplication, titled title: String) -> XCUIElement {
        let row = app.descendants(matching: .any).matching(identifier: GuideAXID.songRow)
            .matching(NSPredicate(format: "label BEGINSWITH %@", title)).firstMatch
        XCTAssertTrue(row.appears(timeout: 15), "no song row \(title)")
        return row
    }

    /// Opens the setlist `name` in the set builder (setlists sort by name, so never rely on
    /// the first row).
    func openSetlist(_ app: XCUIApplication, _ name: String) {
        let row = app.descendants(matching: .any).matching(identifier: GuideAXID.setlistRow)
            .matching(NSPredicate(format: "label CONTAINS %@ OR value CONTAINS %@", name, name))
            .firstMatch
        XCTAssertTrue(row.appears(timeout: 15), "no setlist \(name)")
        row.click(in: app)
    }

    /// The stage: the live view, which fills its borderless window edge to edge (a
    /// borderless window is not an accessibility window, so the view is captured).
    func stageWindow(_ app: XCUIApplication) -> XCUIElement {
        let stage = app.descendants(matching: .any)[GuideAXID.liveView]
        XCTAssertTrue(stage.appears(timeout: 10), "the stage window is missing")
        return stage
    }

    /// Command-Period, then Return ends the show.
    func endShow(_ app: XCUIApplication) {
        app.typeKey(".", modifierFlags: .command, in: app)
        XCTAssertTrue(element(app, GuideAXID.liveEndDialog).exists)
        app.typeKey(.return, modifierFlags: [], in: app)
    }

    /// Puts the guide fixture paste on the pasteboard, opens the review with
    /// Option-Command-V and waits for the AI pass to finish.
    func pasteFixture(_ app: XCUIApplication) -> XCUIElement {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(GuideFixtures.chordSitePaste, forType: .string)
        _ = element(app, GuideAXID.songRow)
        app.typeKey("v", modifierFlags: [.command, .option], in: app)
        let review = element(app, GuideAXID.pasteSheet)
        let refining = app.descendants(matching: .any)[GuideAXID.pasteRefining]
        XCTAssertTrue(refining.disappears(timeout: 20), "the AI pass never finished")
        // The sheet opens with the Title selected for typing; a capture shows it at rest
        // (no focus ring or selection highlight): focus goes back to the original text.
        app.typeKey(.tab, modifierFlags: .shift, in: app)
        _ = review.settles(timeout: 5)
        return app.sheets.firstMatch.exists ? app.sheets.firstMatch : review
    }

    /// A section label the recorded model answer decided (it carries the sparkle).
    func aiSectionLabel(_ app: XCUIApplication) -> XCUIElement {
        let label = app.descendants(matching: .any)
            .matching(identifier: GuideAXID.pasteSectionLabel)
            .matching(NSPredicate(
                format: "label ENDSWITH %@ OR value ENDSWITH %@",
                "labelled by AI",
                "labelled by AI",
            )).firstMatch
        if !label.appears(timeout: 10) {
            let all = app.descendants(matching: .any)
                .matching(identifier: GuideAXID.pasteSectionLabel).allElementsBoundByIndex
            let seen = all.map { "\($0.label)|\($0.value ?? "")" }
            let footer = app.descendants(matching: .any)[GuideAXID.pasteProvider]
            XCTFail(
                "no AI-labelled section (recorded answer not replayed?): labels \(seen), "
                    + "footer \(footer.label)|\(footer.value ?? "")",
            )
        }
        return label
    }
}

/// Text the captures use: exactly `GuideFixtures.chordSitePaste` in
/// App/Sources/Debug/GuideFixtures.swift (the recorded model answer is keyed to it). Original
/// lyrics only: the Welcome song "Kettle On, Lights Low" laid out as a chord site would show
/// it, with no section headers (so the converter asks the model).
enum GuideFixtures {
    static let chordSitePaste = """
    Kettle On, Lights Low Chords by Segue Originals
    Transpose  -1  +1   Autoscroll
    Capo 3

    G          Cadd9
    Kettle on, lights low,
    G              D/F#
    Rain on the window glass,
    Em7            Cadd9
    Nowhere we need to go,
    G       D       G
    Let the evening pass.

    G        Cadd9
    Two old chairs that creak,
    G          D/F#
    One old song we know,
    Em7              Cadd9
    Half of it hummed, not sung,
    G       D         G
    Kettle on, lights low.

    Cadd9         G
    Turn, turn, round the room,
    Cadd9            D
    Slow as the clock can go,
    Em7        Cadd9          G
    One more waltz for the afternoon,
    Am7      D          G
    Kettle on, lights low.

    G        Cadd9
    Cups gone cold again,
    G          D/F#
    Records spinning slow,
    Em7               Cadd9
    Stay till the morning, then,
    G       D         G
    Kettle on, lights low.

    Cadd9         G
    Turn, turn, round the room,
    Cadd9            D
    Slow as the clock can go,
    Em7        Cadd9          G
    One more waltz for the afternoon,
    Am7      D          G
    Kettle on, lights low.
    """
}
