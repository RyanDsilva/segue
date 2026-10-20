import XCTest

// The steps of `SegueEditorE2ETests.testEditorFlow`.

@MainActor
extension SegueEditorE2ETests {
    // MARK: - Steps

    func createSongWithAutocomplete(_ app: XCUIApplication) {
        element(app, EditorAXID.newSong).click(in: app)
        // New Song opens the paste flow (R83); Start blank is the empty song.
        element(app, "segue.paste.startBlank").click(in: app)
        let editor = app.textViews[EditorAXID.editorText]
        XCTAssertTrue(editor.appears(timeout: 10))
        XCTAssertTrue(element(app, EditorAXID.editorModeText).isSelected)
        editor.click(in: app)

        // Every automatic substitution is off on both editor views.
        let settings = element(app, EditorAXID.editorInputSettings)
        XCTAssertTrue(settings.appears(timeout: 5))
        let report = settings.label
        XCTAssertTrue(report.contains("spelling=off"), report)
        XCTAssertFalse(report.contains("=on"), report)

        // `{` directive completion.
        editor.typeText("{ti", in: app)
        let chips = completionChips(app)
        XCTAssertTrue(chips.firstMatch.appears(timeout: 5), "No directive completion")
        XCTAssertEqual(chips.firstMatch.label, "Title")
        attachScreenshot(app, name: "directive-completion")
        app.typeKey(.return, modifierFlags: [], in: app)
        XCTAssertTrue(waitForValue(editor, "{title: }"))
        editor.typeText("Raah Test", in: app)
        app.typeKey(.rightArrow, modifierFlags: [], in: app)
        editor.typeText("\n{key: G}\n\n{start_of_verse}\n", in: app)

        // `[` chord completion: diatonic chords of G, filtered by typing; Return inserts.
        editor.typeText("[", in: app)
        XCTAssertTrue(chips.firstMatch.appears(timeout: 5), "No chord completion")
        XCTAssertEqual(chips.firstMatch.label, "G")
        add(XCTAttachment(string: "after [: \(editor.value as? String ?? "")"))
        editor.typeText("C", in: app)
        add(XCTAttachment(string: "after C: \(editor.value as? String ?? "")"))
        XCTAssertTrue(wait { chips.firstMatch.label == "C" })
        attachScreenshot(app, name: "chord-completion")
        app.typeKey(.return, modifierFlags: [], in: app)
        XCTAssertTrue(chips.firstMatch.disappears(timeout: 5))

        // Romanized Hindi with autocorrect bait: nothing is changed.
        editor.typeText("Dil ki baat. hai \"sach\" -- [G]teh\n{end_of_verse}\n", in: app)
        XCTAssertTrue(waitForValue(editor, EditorFixture.typed))
        let preview = element(app, EditorAXID.editorPreview)
        XCTAssertTrue(waitForValue(preview.staticTexts[EditorAXID.songTitle], "Raah Test"))
        XCTAssertEqual(previewChords(app), ["C", "G"])
        attachScreenshot(app, name: "text-mode")
    }

    func editInVisualMode(_ app: XCUIApplication) {
        element(app, EditorAXID.editorModeVisual).click(in: app)
        let canvas = app.textViews[EditorAXID.editorVisual]
        XCTAssertTrue(canvas.appears(timeout: 10))
        XCTAssertTrue(wait { self.pillLabels(app) == ["C", "G"] }, "\(pillLabels(app))")
        attachScreenshot(app, name: "visual-mode")

        // Click the syllable "hai": popover, type a chord, Return.
        lane(app, "hai").coordinate(withNormalizedOffset: CGVector(dx: 0.1, dy: 0.5)).click(in: app)
        let field = app.textFields[EditorAXID.editorChordField]
        XCTAssertTrue(field.appears(timeout: 5), "No chord popover")
        field.typeText("Em", in: app)
        attachScreenshot(app, name: "chord-popover")
        app.typeKey(.return, modifierFlags: [], in: app)
        XCTAssertTrue(wait { self.pillLabels(app) == ["C", "Em", "G"] }, "\(pillLabels(app))")

        // Drag C from "Dil" to "ki", then undo.
        let from = pill(app, "C").coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        let to = lane(app, "ki").coordinate(withNormalizedOffset: CGVector(dx: 0.05, dy: 0.5))
        from.press(forDuration: 0.3, thenDragTo: to, in: app)
        XCTAssertTrue(wait { (canvas.value as? String)?.contains("Dil ki") == true })
        switchMode(app, to: .text)
        XCTAssertTrue(waitForValue(app.textViews[EditorAXID.editorText], EditorFixture.afterDrag))
        switchMode(app, to: .visual)
        app.typeKey("z", modifierFlags: .command, in: app)
        switchMode(app, to: .text)
        let editor = app.textViews[EditorAXID.editorText]
        XCTAssertTrue(waitForValue(editor, EditorFixture.withEm))

        // Visual -> text cursor mapping: lyric line 1, before "ki". The section label sits
        // in the band beside the lines (P3-11), not on a row, so Cmd-Up lands on the lyric.
        switchMode(app, to: .visual)
        app.typeKey(.upArrow, modifierFlags: .command, in: app)
        for _ in 0 ..< 4 {
            app.typeKey(.rightArrow, modifierFlags: [], in: app)
        }
        switchMode(app, to: .text)
        XCTAssertTrue(waitForValue(element(app, EditorAXID.editorCursor), "Line 5, column 8"))

        // Text -> visual: move to "ba|at", switch, type in the canvas, undo.
        for _ in 0 ..< 5 {
            app.typeKey(.rightArrow, modifierFlags: [], in: app)
        }
        XCTAssertTrue(waitForValue(element(app, EditorAXID.editorCursor), "Line 5, column 13"))
        switchMode(app, to: .visual)
        app.textViews[EditorAXID.editorVisual].typeText("X", in: app)
        switchMode(app, to: .text)
        XCTAssertTrue(waitForValue(
            editor,
            EditorFixture.withEm.replacingOccurrences(of: "baat", with: "baXat"),
        ))
        XCTAssertTrue(waitForValue(element(app, EditorAXID.editorCursor), "Line 5, column 14"))
        app.typeKey("z", modifierFlags: .command, in: app)
        XCTAssertTrue(waitForValue(editor, EditorFixture.withEm))
    }

    func toggleDisplayOptions(_ app: XCUIApplication) {
        element(app, EditorAXID.editorCapoUp).click(in: app)
        element(app, EditorAXID.editorCapoUp).click(in: app)
        XCTAssertTrue(waitForValue(element(app, EditorAXID.editorCapoValue), "2"))
        XCTAssertTrue(wait { self.previewChords(app) == ["C", "Em", "G"] })
        element(app, EditorAXID.editorConcert).click(in: app)
        XCTAssertTrue(
            wait { self.previewChords(app) == ["D", "F#m", "A"] },
            "\(previewChords(app))",
        )
        attachScreenshot(app, name: "concert")
        element(app, EditorAXID.editorShapes).click(in: app)
        element(app, EditorAXID.editorTransposeUp).click(in: app)
        XCTAssertTrue(waitForValue(element(app, EditorAXID.editorTransposeValue), "Ab, +1"))
        XCTAssertTrue(
            wait { self.previewChords(app) == ["Db", "Fm", "Ab"] },
            "\(previewChords(app))",
        )
        element(app, EditorAXID.editorNashville).click(in: app)
        XCTAssertTrue(wait { self.previewChords(app) == ["4", "6m", "1"] }, "\(previewChords(app))")
        attachScreenshot(app, name: "nashville")
        element(app, EditorAXID.editorNashville).click(in: app)
        element(app, EditorAXID.editorTransposeDown).click(in: app)
        XCTAssertTrue(waitForValue(element(app, EditorAXID.editorTransposeValue), "G, +0"))
        XCTAssertTrue(wait { self.previewChords(app) == ["C", "Em", "G"] })
    }

    func addCustomShape(_ app: XCUIApplication) {
        let diagrams = app.descendants(matching: .any)
            .matching(identifier: EditorAXID.guitarDiagram)
        // The diagram strip is off by default (phase 1 build rulings); turn it on.
        XCTAssertFalse(diagrams.firstMatch.exists, "Diagram strip shown by default")
        element(app, EditorAXID.editorDiagramsToggle).click(in: app)
        let diagram = diagrams.matching(NSPredicate(format: "label BEGINSWITH 'G'")).firstMatch
        XCTAssertTrue(diagram.appears(timeout: 10), "No G diagram in the strip")
        diagram.click(in: app)
        let save = element(app, EditorAXID.shapeEditorSave)
        XCTAssertTrue(save.appears(timeout: 5), "No shape editor")
        attachScreenshot(app, name: "shape-editor")
        save.click(in: app)
        let editor = app.textViews[EditorAXID.editorText]
        XCTAssertTrue(wait { (editor.value as? String)?.contains("{define: G ") == true })
    }

    func applyTranspositionToSource(_ app: XCUIApplication) {
        element(app, EditorAXID.editSong).click(in: app)
        // Existing songs open on the visual canvas.
        XCTAssertTrue(app.textViews[EditorAXID.editorVisual].appears(timeout: 10))
        element(app, EditorAXID.editorTransposeUp).click(in: app)
        element(app, EditorAXID.editorTransposeUp).click(in: app)
        let apply = element(app, EditorAXID.editorApplyTransposition)
        XCTAssertTrue(apply.appears(timeout: 5))
        apply.click(in: app)
        let banner = element(app, EditorAXID.editorFlaggedDefines)
        XCTAssertTrue(banner.appears(timeout: 5), "No flagged-shape warning")
        XCTAssertTrue(Self.text(banner).contains("G"), Self.text(banner))
        XCTAssertTrue(waitForValue(element(app, EditorAXID.editorTransposeValue), "A, +0"))
        attachScreenshot(app, name: "flagged-defines")
    }

    /// Clicks Done: the last edits are saved and the editor closes on the rendered song.
    func finishEditing(_ app: XCUIApplication) {
        let done = app.buttons[EditorAXID.editorDone]
        XCTAssertTrue(done.isEnabled)
        done.click(in: app)
        XCTAssertTrue(done.disappears(timeout: 10))
        XCTAssertTrue(element(app, EditorAXID.editSong).appears(timeout: 10))
    }
}
