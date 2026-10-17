import XCTest

// The steps of `SegueEditorE2ETests.testEditorFlow`.

@MainActor
extension SegueEditorE2ETests {
    // MARK: - Steps

    func createSongWithAutocomplete(_ app: XCUIApplication) {
        element(app, EditorAXID.newSong).click()
        let editor = app.textViews[EditorAXID.editorText]
        XCTAssertTrue(editor.waitForExistence(timeout: 10))
        XCTAssertTrue(element(app, EditorAXID.editorModeText).isSelected)
        editor.click()

        // Every automatic substitution is off on both editor views.
        let settings = element(app, EditorAXID.editorInputSettings)
        XCTAssertTrue(settings.waitForExistence(timeout: 5))
        let report = settings.label
        XCTAssertTrue(report.contains("spelling=off"), report)
        XCTAssertFalse(report.contains("=on"), report)

        // `{` directive completion.
        editor.typeText("{ti")
        let chips = completionChips(app)
        XCTAssertTrue(chips.firstMatch.waitForExistence(timeout: 5), "No directive completion")
        XCTAssertEqual(chips.firstMatch.label, "title")
        attachScreenshot(app, name: "directive-completion")
        app.typeKey(.return, modifierFlags: [])
        XCTAssertTrue(waitForValue(editor, "{title: }"))
        editor.typeText("Raah Test")
        app.typeKey(.rightArrow, modifierFlags: [])
        editor.typeText("\n{key: G}\n\n{start_of_verse}\n")

        // `[` chord completion: diatonic chords of G, filtered by typing; Return inserts.
        editor.typeText("[")
        XCTAssertTrue(chips.firstMatch.waitForExistence(timeout: 5), "No chord completion")
        XCTAssertEqual(chips.firstMatch.label, "G")
        add(XCTAttachment(string: "after [: \(editor.value as? String ?? "")"))
        editor.typeText("C")
        add(XCTAttachment(string: "after C: \(editor.value as? String ?? "")"))
        XCTAssertTrue(wait { chips.firstMatch.label == "C" })
        attachScreenshot(app, name: "chord-completion")
        app.typeKey(.return, modifierFlags: [])
        XCTAssertTrue(chips.firstMatch.waitForNonExistence(timeout: 5))

        // Romanized Hindi with autocorrect bait: nothing is changed.
        editor.typeText("Dil ki baat. hai \"sach\" -- [G]teh\n{end_of_verse}\n")
        XCTAssertTrue(waitForValue(editor, EditorFixture.typed))
        let preview = element(app, EditorAXID.editorPreview)
        XCTAssertTrue(waitForValue(preview.staticTexts[EditorAXID.songTitle], "Raah Test"))
        XCTAssertEqual(previewChords(app), ["C", "G"])
        attachScreenshot(app, name: "text-mode")
    }

    func editInVisualMode(_ app: XCUIApplication) {
        element(app, EditorAXID.editorModeVisual).click()
        let canvas = app.textViews[EditorAXID.editorVisual]
        XCTAssertTrue(canvas.waitForExistence(timeout: 10))
        XCTAssertTrue(wait { self.pillLabels(app) == ["C", "G"] }, "\(pillLabels(app))")
        attachScreenshot(app, name: "visual-mode")

        // Click the syllable "hai": popover, type a chord, Return.
        lane(app, "hai").coordinate(withNormalizedOffset: CGVector(dx: 0.1, dy: 0.5)).click()
        let field = app.textFields[EditorAXID.editorChordField]
        XCTAssertTrue(field.waitForExistence(timeout: 5), "No chord popover")
        field.typeText("Em")
        attachScreenshot(app, name: "chord-popover")
        app.typeKey(.return, modifierFlags: [])
        XCTAssertTrue(wait { self.pillLabels(app) == ["C", "Em", "G"] }, "\(pillLabels(app))")

        // Drag C from "Dil" to "ki", then undo.
        let from = pill(app, "C").coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        let to = lane(app, "ki").coordinate(withNormalizedOffset: CGVector(dx: 0.05, dy: 0.5))
        from.press(forDuration: 0.3, thenDragTo: to)
        XCTAssertTrue(wait { (canvas.value as? String)?.contains("Dil ki") == true })
        switchMode(app, to: .text)
        XCTAssertTrue(waitForValue(app.textViews[EditorAXID.editorText], EditorFixture.afterDrag))
        switchMode(app, to: .visual)
        app.typeKey("z", modifierFlags: .command)
        switchMode(app, to: .text)
        let editor = app.textViews[EditorAXID.editorText]
        XCTAssertTrue(waitForValue(editor, EditorFixture.withEm))

        // Visual -> text cursor mapping: lyric line 1, before "ki".
        switchMode(app, to: .visual)
        app.typeKey(.upArrow, modifierFlags: .command)
        app.typeKey(.downArrow, modifierFlags: [])
        for _ in 0 ..< 4 {
            app.typeKey(.rightArrow, modifierFlags: [])
        }
        switchMode(app, to: .text)
        XCTAssertTrue(waitForValue(element(app, EditorAXID.editorCursor), "Line 5, column 8"))

        // Text -> visual: move to "ba|at", switch, type in the canvas, undo.
        for _ in 0 ..< 5 {
            app.typeKey(.rightArrow, modifierFlags: [])
        }
        XCTAssertTrue(waitForValue(element(app, EditorAXID.editorCursor), "Line 5, column 13"))
        switchMode(app, to: .visual)
        app.textViews[EditorAXID.editorVisual].typeText("X")
        switchMode(app, to: .text)
        XCTAssertTrue(waitForValue(
            editor,
            EditorFixture.withEm.replacingOccurrences(of: "baat", with: "baXat"),
        ))
        XCTAssertTrue(waitForValue(element(app, EditorAXID.editorCursor), "Line 5, column 14"))
        app.typeKey("z", modifierFlags: .command)
        XCTAssertTrue(waitForValue(editor, EditorFixture.withEm))
    }

    func toggleDisplayOptions(_ app: XCUIApplication) {
        element(app, EditorAXID.editorCapoUp).click()
        element(app, EditorAXID.editorCapoUp).click()
        XCTAssertTrue(waitForValue(element(app, EditorAXID.editorCapoValue), "2"))
        XCTAssertTrue(wait { self.previewChords(app) == ["C", "Em", "G"] })
        element(app, EditorAXID.editorConcert).click()
        XCTAssertTrue(
            wait { self.previewChords(app) == ["D", "F#m", "A"] },
            "\(previewChords(app))",
        )
        attachScreenshot(app, name: "concert")
        element(app, EditorAXID.editorShapes).click()
        element(app, EditorAXID.editorTransposeUp).click()
        XCTAssertTrue(waitForValue(element(app, EditorAXID.editorTransposeValue), "Ab, +1"))
        XCTAssertTrue(
            wait { self.previewChords(app) == ["Db", "Fm", "Ab"] },
            "\(previewChords(app))",
        )
        element(app, EditorAXID.editorNashville).click()
        XCTAssertTrue(wait { self.previewChords(app) == ["4", "6m", "1"] }, "\(previewChords(app))")
        attachScreenshot(app, name: "nashville")
        element(app, EditorAXID.editorNashville).click()
        element(app, EditorAXID.editorTransposeDown).click()
        XCTAssertTrue(waitForValue(element(app, EditorAXID.editorTransposeValue), "G, +0"))
        XCTAssertTrue(wait { self.previewChords(app) == ["C", "Em", "G"] })
    }

    func addCustomShape(_ app: XCUIApplication) {
        let diagrams = app.descendants(matching: .any)
            .matching(identifier: EditorAXID.guitarDiagram)
        let diagram = diagrams.matching(NSPredicate(format: "label BEGINSWITH 'G'")).firstMatch
        XCTAssertTrue(diagram.waitForExistence(timeout: 10), "No G diagram in the strip")
        diagram.click()
        // The shape editor's container identifier currently masks `shapeEditorSave` (unit B),
        // so find Save by title within the sheet.
        let save = app.sheets.buttons["Save"].firstMatch
        XCTAssertTrue(save.waitForExistence(timeout: 5), "No shape editor")
        attachScreenshot(app, name: "shape-editor")
        save.click()
        let editor = app.textViews[EditorAXID.editorText]
        XCTAssertTrue(wait { (editor.value as? String)?.contains("{define: G ") == true })
    }

    func applyTranspositionToSource(_ app: XCUIApplication) {
        element(app, EditorAXID.editSong).click()
        // Existing songs open on the visual canvas.
        XCTAssertTrue(app.textViews[EditorAXID.editorVisual].waitForExistence(timeout: 10))
        element(app, EditorAXID.editorTransposeUp).click()
        element(app, EditorAXID.editorTransposeUp).click()
        let apply = element(app, EditorAXID.editorApplyTransposition)
        XCTAssertTrue(apply.waitForExistence(timeout: 5))
        apply.click()
        let banner = element(app, EditorAXID.editorFlaggedDefines)
        XCTAssertTrue(banner.waitForExistence(timeout: 5), "No flagged-shape warning")
        XCTAssertTrue(Self.text(banner).contains("G"), Self.text(banner))
        XCTAssertTrue(waitForValue(element(app, EditorAXID.editorTransposeValue), "A, +0"))
        attachScreenshot(app, name: "flagged-defines")
    }

    func saveEditor(_ app: XCUIApplication) {
        let save = app.buttons[EditorAXID.editorSave]
        XCTAssertTrue(save.isEnabled)
        save.click()
        XCTAssertTrue(save.waitForNonExistence(timeout: 10))
        XCTAssertTrue(element(app, EditorAXID.editSong).waitForExistence(timeout: 10))
    }
}
