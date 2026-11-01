import Editing
import Foundation
import Library
import MusicTheory
import Playback
@testable import SegueUI
import Testing

/// Saved fills with walk-ups Off (R175, amending R168 Q7): the density governs only the
/// generated walk-ups, so a saved fill shows in the editor's preview (text and visual mode)
/// and the library's preview whenever the bass-note view is on, and plays in their
/// play-along, while no walk-up is drawn or played anywhere.
@MainActor
@Suite(.serialized)
struct FillsWithoutWalkUpsTests {
    static let song = """
    {title: Harbour}
    {key: G}
    {tempo: 120}

    {start_of_verse}
    [G]Hello there [C]my friend
    {end_of_verse}

    {start_of_chorus}
    [D]Sing it [G]home
    {end_of_chorus}

    """

    struct Opened {
        var env: TestEnvironment
        var store: InstrumentProfileStore
        var library: LibraryViewModel
        var editor: SongEditorViewModel
        var song: SongRecord
    }

    /// The song with one fill over the verse's C into the chorus's D (D on C's beat 4), the
    /// bass-note view on and walk-ups left Off (the default), open in the editor.
    static func open() async throws -> Opened {
        let env = try TestEnvironment()
        let store = InstrumentProfileStore(defaults: env.defaults)
        store.update { $0.bassNotes = true }
        #expect(store.profile.walkUps == .off)
        let rig = SoundRig(env, services: RecordingAnalytics(env).hub)
        let library = try await env.openLibrary()
        library.instrument = store
        library.sound = rig.session
        var song = try await library.createSong(source: Self.song)
        song = try await library.store.updateParts(id: song.id, [PlayAlongTests.fill(song)])
        library.beginEditing(song)
        let editor = try #require(library.editor)
        try await AISettingsTests.waitUntil(timeout: .seconds(30)) {
            !fillRuns(editor.renderModel).isEmpty
        }
        return Opened(env: env, store: store, library: library, editor: editor, song: song)
    }

    /// "chord: run" for every fill run of a render model.
    static func fillRuns(_ model: RenderModel?) -> [String] {
        chords(model).compactMap { chord in
            chord.fill?.drawn.map { "\(chord.original): \($0.text)" }
        }
    }

    static func walkUps(_ model: RenderModel?) -> [ApproachRun] {
        chords(model).compactMap(\.approach)
    }

    private static func chords(_ model: RenderModel?) -> [RenderChord] {
        (model?.sections ?? []).flatMap(\.items).flatMap { item -> [RenderChord] in
            guard case let .lyrics(line) = item else { return [] }
            return line.chords
        }
    }

    @Test
    func `the editor preview shows the fill in text and visual mode`() async throws {
        let opened = try await Self.open()
        let editor = opened.editor
        for mode in [SongEditorViewModel.EditorMode.text, .visual] {
            editor.setEditorMode(mode)
            editor.scheduleRender(delay: .zero)
            await editor.renderTask?.value
            #expect(Self.fillRuns(editor.renderModel) == ["C: D \u{203A}"], "\(mode)")
            #expect(Self.walkUps(editor.renderModel).isEmpty, "\(mode)")
        }
        // The canvas never draws runs (P8-4 decision 5).
        #expect(Self.fillRuns(editor.canvasModel).isEmpty)
        // Without the bass-note view the fill is hidden (it shows only there).
        opened.store.toggleBassNotes(from: .editor)
        try await AISettingsTests.waitUntil(timeout: .seconds(30)) {
            Self.fillRuns(editor.renderModel).isEmpty
        }
    }

    @Test
    func `the library preview shows the fill`() async throws {
        let opened = try await Self.open()
        #expect(opened.song.sidecar.parts.count == 1)
        let model = SongSummary.renderModel(opened.song, bass: opened.store.bassView)
        #expect(Self.fillRuns(model) == ["C: D \u{203A}"])
        #expect(Self.walkUps(model).isEmpty)
    }

    @Test
    func `play-along plays the fill and no walk-up`() async throws {
        let opened = try await Self.open()
        let playAlong = try #require(opened.editor.playAlong)
        playAlong.setOpen(true)
        playAlong.update(opened.editor.playAlongSource)
        let source = try #require(opened.editor.playAlongSource)
        #expect(!source.hasWalkUps)
        #expect(source.changes.allSatisfy { $0.shown == nil })
        let fills = playAlong.timeline.fills
        #expect(fills.count == 1)
        #expect(fills.first?.notes.map { $0.midi % 12 } == [2])
        // The library's bar plays it too.
        let record = opened.song
        opened.library.closeEditor()
        let library = try #require(opened.library.playAlong)
        opened.library.showPlayAlong(record, render: SongSummary.renderModel(record))
        #expect(library.timeline.fills.count == 1)
    }
}
