import Editing
import Foundation
import Library
import MusicTheory
@testable import SegueUI
import Testing

/// Picking a walk-up in the editor (P8-4b sections 8.8, 8.9, 11.3): the preview draws the
/// suggestion, a pick writes the sidecar (never the `.cho`) and redraws as yours, undo and
/// reset bring the suggestion back, and the stage request carries the same pick.
@MainActor
struct WalkUpPickerTests {
    static let song = "{title: Harbour}\n{key: G}\n\n[G]Hello there [C]my friend\n"

    static func runs(_ model: RenderModel?) -> [ApproachRun] {
        model?.sections.flatMap(\.items).flatMap { item -> [ApproachRun] in
            guard case let .lyrics(line) = item else { return [] }
            return line.chords.compactMap(\.approach)
        } ?? []
    }

    struct Opened {
        var library: LibraryViewModel
        var editor: SongEditorViewModel
        var song: SongRecord
    }

    private func open(_ env: TestEnvironment) async throws -> Opened {
        let store = InstrumentProfileStore(defaults: env.defaults)
        store.update { $0.bassNotes = true }
        store.setWalkUps(.everyChange)
        let library = try await env.openLibrary()
        library.instrument = store
        let song = try await library.createSong(source: Self.song)
        library.beginEditing(song)
        let editor = try #require(library.editor)
        try await AISettingsTests.waitUntil(timeout: .seconds(30)) {
            Self.runs(editor.renderModel).first?.notes == ["A", "B"]
        }
        return Opened(library: library, editor: editor, song: song)
    }

    @Test
    func `choosing a candidate writes the sidecar only and redraws it as a pick`() async throws {
        let env = try TestEnvironment()
        let opened = try await open(env)
        let (library, editor, song) = (opened.library, opened.editor, opened.song)
        let cho = try env.read(song.relativePath)
        let run = try #require(Self.runs(editor.renderModel).first)
        #expect(run.isPick == false)
        let details = try #require(editor.walkUpDetails(run.change))
        #expect(details.change.fromName == "G")
        #expect(details.change.toName == "C")
        let half = try #require(details.change.candidates.first { $0.kind == .diatonicNeighbour })

        editor.pickWalkUp(details.change, half)
        try await AISettingsTests.waitUntil(timeout: .seconds(30)) {
            Self.runs(editor.renderModel).first?.isPick == true
        }
        #expect(Self.runs(editor.renderModel).first?.notes == ["B"])
        await editor.bassTask?.value
        #expect(try env.read(song.relativePath) == cho)
        let saved = try #require(try await library.store.song(id: song.id))
        #expect(saved.sidecar.bass.walkUps.map(\.kind) == [.diatonicNeighbour])

        // The stage shows the same pick.
        let model = SongSummary.renderModel(saved, bass: library.instrument?.bassView)
        #expect(Self.runs(model).first?.notes == ["B"])

        // Undo brings the suggestion back.
        editor.sourceEditor.undoManager.undo()
        try await AISettingsTests.waitUntil(timeout: .seconds(30)) {
            Self.runs(editor.renderModel).first?.notes == ["A", "B"]
        }
        await editor.bassTask?.value
        let undone = try #require(try await library.store.song(id: song.id))
        #expect(undone.sidecar.bass.walkUps.isEmpty)
    }

    @Test
    func `nothing here hides the run and reset brings the suggestion back`() async throws {
        let env = try TestEnvironment()
        let editor = try await open(env).editor
        let run = try #require(Self.runs(editor.renderModel).first)
        let details = try #require(editor.walkUpDetails(run.change))
        editor.pickWalkUp(details.change, nil)
        try await AISettingsTests.waitUntil(timeout: .seconds(30)) {
            Self.runs(editor.renderModel).isEmpty
        }
        let held = try #require(editor.walkUpDetails(run.change))
        #expect(held.change.pick?.kind == .hold)
        editor.resetWalkUp(held.change)
        try await AISettingsTests.waitUntil(timeout: .seconds(30)) {
            Self.runs(editor.renderModel).first?.notes == ["A", "B"]
        }
    }

    @Test
    func `a new song cannot pick yet`() {
        let editor = SongEditorViewModel(mode: .create, source: Self.song) { _ in
            throw CancellationError()
        }
        #expect(!editor.canPickWalkUps)
        #expect(!editor.walkUpPicking.isEnabled)
    }

    @Test
    func `walk-ups need the bass-note view`() async throws {
        let env = try TestEnvironment()
        let store = InstrumentProfileStore(defaults: env.defaults)
        store.setWalkUps(.everyChange)
        let library = try await env.openLibrary()
        library.instrument = store
        let song = try await library.createSong(source: Self.song)
        let model = SongSummary.renderModel(song, bass: store.bassView)
        #expect(Self.runs(model).isEmpty)
    }
}
