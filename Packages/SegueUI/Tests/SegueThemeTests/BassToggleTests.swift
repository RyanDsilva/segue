import AppKit
import ChordPro
import Editing
import Library
@testable import SegueUI
import Support
import SwiftUI
import Testing

/// The bass-note view in the editor and library (P8-4 6.3, 6.5, 11.3): the Bass segment
/// flips the user-level store for anyone, the preview shows notes at sounding pitch while
/// the visual canvas keeps chart chords, and no per-song prefs are written.
@MainActor
struct BassToggleTests {
    static let song = "{title: Harbour}\n{key: G}\n{capo: 2}\n\n[G]Hello [G/B]there [C]friend\n"

    private func editor(
        _ env: TestEnvironment,
        store: InstrumentProfileStore,
        prefs: DisplayPrefs = DisplayPrefs(),
        persisted: PrefsLog? = nil,
    ) -> SongEditorViewModel {
        SongEditorViewModel(
            mode: .create,
            source: Self.song,
            prefs: prefs,
            persistPrefs: persisted.map { log in
                { _, prefs in
                    log.writes.append(prefs)
                    throw CancellationError()
                }
            },
            instrument: store,
        ) { _ in throw CancellationError() }
    }

    final class PrefsLog {
        var writes: [DisplayPrefs] = []
    }

    static func chords(_ model: RenderModel?) -> [String] {
        model?.sections.flatMap { section in
            section.items.flatMap { item -> [String] in
                guard case let .lyrics(line) = item else { return [] }
                return line.chords.map(\.text)
            }
        } ?? []
    }

    @Test
    func `the Bass segment flips the store and re-renders the preview at sounding pitch`(
    ) async throws {
        let env = try TestEnvironment()
        let store = InstrumentProfileStore(defaults: env.defaults)
        let model = editor(env, store: store)
        #expect(!model.showsBassNotes)
        #expect(Self.chords(model.renderModel) == ["G", "G/B", "C"])

        model.toggleBassNotes()
        #expect(store.profile.bassNotes)
        #expect(!store.profile.playsBass)
        try await AISettingsTests.waitUntil { Self.chords(model.renderModel) == ["A", "C#", "D"] }
        #expect(model.renderModel?.header.key == "A")
        #expect(model.renderModel?.header.scale == "A major: A B C# D E F# G#")
        // The song's own prefs are untouched.
        #expect(model.options.bass == nil)
        #expect(DisplayPrefs(model.options) == DisplayPrefs())

        // A flip from anywhere else (the stage, Settings) re-renders too.
        store.toggleBassNotes(from: .stage)
        try await AISettingsTests.waitUntil { Self.chords(model.renderModel) == ["G", "G/B", "C"] }
    }

    @Test
    func `the visual canvas keeps chart chords in bass view`() async throws {
        let env = try TestEnvironment()
        let store = InstrumentProfileStore(defaults: env.defaults)
        store.update { $0.bassNotes = true }
        let model = editor(env, store: store)
        // An existing song opens on the visual canvas.
        #expect(model.editorMode == .visual)
        model.refreshCanvas()
        #expect(Self.chords(model.canvasModel) == ["G", "G/B", "C"])
        #expect(Self.chords(model.renderModel) == ["A", "C#", "D"])
        model.scheduleRender(delay: .zero)
        await model.renderTask?.value
        #expect(Self.chords(model.canvasModel) == ["G", "G/B", "C"])
        #expect(Self.chords(model.renderModel) == ["A", "C#", "D"])
    }

    @Test
    func `the Nashville button stays the song's own toggle in bass view`() async throws {
        let env = try TestEnvironment()
        let store = InstrumentProfileStore(defaults: env.defaults)
        store.update { $0.bassNotes = true }
        let model = editor(env, store: store)
        model.setNashville(true)
        #expect(model.options.nashville)
        #expect(store.profile == InstrumentProfile(bassNotes: true))
        await model.renderTask?.value
        #expect(Self.chords(model.renderModel) == [
            "1 \u{00B7} A", "3 \u{00B7} C#", "4 \u{00B7} D",
        ])
    }

    @Test
    func `the library preview shows bass notes with the chord beside`() throws {
        let env = try TestEnvironment()
        let store = InstrumentProfileStore(defaults: env.defaults)
        store.update { $0.bassNotes = true }
        store.update { $0.chordBeside = true }
        let record = Self.record(Self.song)
        let model = SongSummary.renderModel(record, bass: store.bassView)
        let chords = model.sections.flatMap { section in
            section.items.flatMap { item -> [RenderChord] in
                guard case let .lyrics(line) = item else { return [] }
                return line.chords
            }
        }
        #expect(chords.map(\.text) == ["A", "C#", "D"])
        #expect(chords.map(\.detail) == ["A", "A/C#", "D"])
        #expect(SongSummary.performanceLine(model) == "A")
        let off = SongSummary.renderModel(record)
        #expect(SongSummary.performanceLine(off) == "G, capo 2")
        #expect(try LyricLineView.spokenText(LyricToken.tokens(for: #require(
            model.sections.first?.items.first.flatMap { item -> RenderLine? in
                guard case let .lyrics(line) = item else { return nil }
                return line
            },
        ))) == "A, C#, bass of A slash C#, D: Hello there friend")
    }

    static func record(_ source: String) -> SongRecord {
        let id = SongID(ULID(milliseconds: 1, randomness: Array(repeating: 0, count: 10)))
        let (document, diagnostics) = ChordProParser.parse(source)
        return SongRecord(
            id: id,
            relativePath: "songs/harbour.cho",
            source: source,
            document: document,
            diagnostics: diagnostics,
            sidecar: Sidecar(id: id, createdAt: .distantPast, updatedAt: .distantPast),
            revision: SongRevision(contentHash: "", sidecarHash: nil),
        )
    }
}
