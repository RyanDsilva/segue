import Editing
import Foundation
import Library
import MusicTheory
@testable import SegueUI
import Testing

/// The key-change chip and the directive inserts in the editor (P8-7 sections 6.1, 6.2,
/// 16.3), through the real editor, store and parser: the chip on the fixture's lifted last
/// chorus in both modes, Insert writes `{key: A}` before the section and undoes, dismissing
/// writes `dismissedKeys` to the sidecar only and hides the chip, and the Insert ... Change
/// Here values are validated.
@MainActor
@Suite(.serialized)
struct KeyChangeUITests {
    /// A G song whose last chorus is lifted to A.
    static let song = """
    {title: Lift}
    {key: G}

    {start_of_verse}
    [G]la [C]la [D]la [G]la [Em]la [C]la [D]la [G]la
    {end_of_verse}

    {start_of_chorus}
    [C]la [G]la [D]la [G]la [C]la [G]la [D]la [G]la
    {end_of_chorus}

    {start_of_chorus}
    [A]la [B]la [C#m]la [D]la [A]la [B]la [C#m]la [D]la
    {end_of_chorus}

    """

    struct Opened {
        var env: TestEnvironment
        var library: LibraryViewModel
        var editor: SongEditorViewModel
        var song: SongRecord
        var recorder: RecordingAnalytics

        /// Row 28's events as "action interval".
        var keyChanges: [String] {
            recorder.log.entries().filter { $0["name"] as? String == "Segue.Timing.keyChange" }
                .compactMap { $0["params"] as? [String: String] }
                .map { "\($0["segue.action"] ?? "") \($0["segue.interval"] ?? "")" }
        }
    }

    private func open() async throws -> Opened {
        let env = try TestEnvironment()
        let library = try await env.openLibrary()
        let recorder = RecordingAnalytics(env)
        library.services = recorder.hub
        let song = try await library.createSong(source: Self.song)
        library.beginEditing(song)
        let editor = try #require(library.editor)
        editor.sourceEditor.undoManager.groupsByEvent = false
        try await AISettingsTests.waitUntil(timeout: .seconds(30)) { editor.renderModel != nil }
        return Opened(env: env, library: library, editor: editor, song: song, recorder: recorder)
    }

    private func gesture(_ opened: Opened, _ action: () -> Void) {
        let undo = opened.editor.sourceEditor.undoManager
        undo.beginUndoGrouping()
        action()
        undo.endUndoGrouping()
    }

    private func rendered(_ opened: Opened, _ condition: @escaping () -> Bool) async throws {
        try await AISettingsTests.waitUntil(timeout: .seconds(30)) {
            opened.editor.renderModel != nil && condition()
        }
    }

    @Test
    func `the chip shows on the lifted chorus in the preview and on the canvas`() async throws {
        let opened = try await open()
        let suggestions = opened.editor.keyChangeSuggestions()
        #expect(suggestions.map(\.key.name) == ["A"])
        #expect(suggestions.map(\.section) == [2])
        // Text mode: a chip row right above the last chorus, nowhere else.
        let model = try #require(opened.editor.renderModel)
        let rows = SheetRow.rows(of: model.sections, style: .preview, keyChanges: suggestions)
        let chips = rows.enumerated().filter {
            if case .keyChange = $0.element.content {
                return true
            }
            return false
        }
        #expect(chips.count == 1)
        let next = try #require(chips.first.map { rows[$0.offset + 1] })
        #expect(next.id == "2.0")
        #expect(next.label == "Chorus")
        // Without suggestions (the library, the stage) the rows are unchanged.
        #expect(!SheetRow.rows(of: model.sections, style: .preview).contains {
            if case .keyChange = $0.content {
                return true
            }
            return false
        })
        // Visual mode works the same chip out for the canvas.
        opened.editor.setEditorMode(.visual)
        opened.editor.visualEditor.reload()
        #expect(opened.editor.visualEditor.keyChips.suggestions.map(\.key.name) == ["A"])
    }

    @Test
    func `insert writes the key before the section and undoes`() async throws {
        let opened = try await open()
        let suggestion = try #require(opened.editor.keyChangeSuggestions().first)
        gesture(opened) { opened.editor.acceptKeyChange(suggestion) }
        #expect(opened.editor.source
            .contains("{end_of_chorus}\n\n{key: A}\n{start_of_chorus}\n[A]"))
        try await rendered(opened) { opened.editor.keyChangeSuggestions().isEmpty }
        #expect(opened.recorder.features == ["keyChangeChip"])
        #expect(opened.keyChanges == ["confirmed wholeUp"])
        opened.editor.sourceEditor.undoManager.undo()
        #expect(opened.editor.source == Self.song)
    }

    @Test
    func `dismiss remembers it in the sidecar only and hides the chip`() async throws {
        let opened = try await open()
        let cho = try opened.env.read(opened.song.relativePath)
        let suggestion = try #require(opened.editor.keyChangeSuggestions().first)
        gesture(opened) { opened.editor.dismissKeyChange(suggestion) }
        #expect(opened.editor.keyChangeSuggestions().isEmpty)
        await opened.editor.bassTask?.value
        let saved = try #require(try await opened.library.store.song(id: opened.song.id))
        #expect(saved.sidecar.bass.timing.dismissedKeys.map(\.key.name) == ["A"])
        #expect(opened.keyChanges == ["dismissed wholeUp"])
        #expect(try opened.env.read(opened.song.relativePath) == cho)
        // Undo brings the chip back.
        opened.editor.sourceEditor.undoManager.undo()
        #expect(opened.editor.keyChangeSuggestions().map(\.key.name) == ["A"])
    }

    @Test
    func `the insert popover starts from what is in effect and validates`() async throws {
        let opened = try await open()
        let model = try #require(opened.editor.renderModel)
        let chorus = try #require(model.sections[2].path)
        let line = try #require(model.sections[1].items.first.flatMap { item -> BlockPath? in
            if case let .lyrics(line) = item {
                return line.path
            }
            return nil
        })
        // The key defaults to the chip's suggestion there, else the key in effect.
        #expect(opened.editor.directiveDraft(.key, before: chorus).key.name == "A")
        #expect(opened.editor.directiveDraft(.key, before: line).key.name == "G")
        #expect(opened.editor.directiveDraft(.time, before: line).time == "4/4")
        #expect(opened.editor.directiveDraft(.key, before: line).capoNote == nil)
        // Bad values are refused and nothing is written.
        #expect(opened.editor.insertDirective(.time, value: "three", before: line) != nil)
        #expect(opened.editor.insertDirective(.tempo, value: "-4", before: line) != nil)
        #expect(opened.editor.source == Self.song)
        // One directive per action, as its own line inside the section, before the line.
        gesture(opened) {
            #expect(opened.editor.insertDirective(.tempo, value: " 132 ", before: line) == nil)
        }
        #expect(opened.editor.source.contains("{start_of_chorus}\n{tempo: 132}\n[C]la"))
        gesture(opened) {
            #expect(opened.editor.insertDirective(.time, value: "3/4", before: chorus) == nil)
        }
        #expect(opened.editor.source.contains("{time: 3/4}\n{start_of_chorus}\n[A]"))
        #expect(opened.recorder.features == ["chartDirective"])
        gesture(opened) {
            #expect(opened.editor.insertDirective(.key, value: "Ab", before: line) == nil)
        }
        #expect(opened.keyChanges == ["inserted halfUp"])
        opened.editor.sourceEditor.undoManager.undo()
        opened.editor.sourceEditor.undoManager.undo()
        opened.editor.sourceEditor.undoManager.undo()
        #expect(opened.editor.source == Self.song)
    }

    @Test
    func `the menus offer the three inserts`() async throws {
        let opened = try await open()
        #expect(ChartDirective.allCases.map(\.menuTitle) == [
            "Insert Key Change Here...", "Insert Time Change Here...",
            "Insert Tempo Change Here...",
        ])
        opened.editor.setEditorMode(.visual)
        opened.editor.visualEditor.reload()
        let path = try #require(opened.editor.renderModel?.sections[2].path)
        let items = opened.editor.visualEditor.directiveMenuItems(before: path, band: 2)
        #expect(items.map(\.title) == ChartDirective.allCases.map(\.menuTitle))
        #expect(ChartDirective.problem(.key, value: "H") != nil)
        #expect(ChartDirective.problem(.key, value: "F#m") == nil)
        #expect(ChartDirective.problem(.time, value: "6/8") == nil)
    }
}
