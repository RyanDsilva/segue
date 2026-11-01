import ChordPro
import Editing
import Foundation
import Library
@testable import SegueUI
import Services
import Testing

/// Singer view in the library and editor previews (P9-2 section 7, 16.3): one remembered
/// toggle shared by both, separate from the stage's, the same transform as the stage, the
/// Song menu item where a song is shown or edited.
@MainActor
@Suite(.timeLimit(.minutes(1)))
struct SingerPreviewTests {
    static let song = """
    {title: Kitaabon}
    {key: G}
    {capo: 2}
    {tempo: 96}
    {start_of_verse: Intro}
    [G]  [D]  [Em]
    {end_of_verse}
    {start_of_verse: Verse}
    Tu[G]jh mein [D]rab dikh[Em]ta hai
    {end_of_verse}
    """

    @Test
    func `the previews share one remembered toggle and never touch the stage's`() async throws {
        let env = try TestEnvironment()
        let app = try await env.openApp()
        let library = try #require(app.session?.library)
        let prefs = app.previewPrefs
        #expect(!prefs.singer)
        #expect(app.singerPreviewContext == nil)

        let record = try await library.createSong(source: Self.song)
        library.select(record.id)
        _ = try await env.waitFor { library.detail == .song(record.id) ? true : nil }
        #expect(library.preview === prefs)
        #expect(app.singerPreviewContext == .library)

        prefs.setSinger(true, from: .library)
        #expect(env.defaults.bool(forKey: PreviewPrefs.singerKey))
        #expect(PreviewPrefs(defaults: env.defaults).singer)
        #expect(!app.liveSettings.settings.singerView)

        library.beginEditing(record)
        let editor = try await env.waitFor { library.editor }
        #expect(app.singerPreviewContext == .editor)
        // The editor reads the same toggle, in Visual and Text mode alike.
        #expect(editor.preview === prefs)
        #expect(editor.showsSingerPreview)
        editor.setEditorMode(.text)
        #expect(editor.showsSingerPreview)
        prefs.setSinger(false, from: .editor)
        #expect(!editor.showsSingerPreview)
        #expect(!env.defaults.bool(forKey: PreviewPrefs.singerKey))
        #expect(!app.liveSettings.settings.singerView)
    }

    @Test
    func `switching on counts once per context`() throws {
        let env = try TestEnvironment()
        let analytics = RecordingAnalytics(env)
        let prefs = PreviewPrefs(defaults: env.defaults)
        prefs.services = analytics.hub
        prefs.setSinger(true, from: .library)
        prefs.setSinger(true, from: .library)
        prefs.setSinger(false, from: .library)
        prefs.setSinger(true, from: .editor)
        #expect(analytics.features == ["singerView", "singerView"])
        let contexts = analytics.log.entries().compactMap { entry in
            (entry["params"] as? [String: String])?["segue.context"]
        }
        #expect(contexts == ["library", "editor"])
    }

    @Test
    func `a preview draws the singer model with the sounding key`() {
        let record = BassToggleTests.record(Self.song)
        let chart = SongSummary.renderModel(record)
        let singer = SingerView.model(chart)
        #expect(SongSummary.performanceLine(chart) == "G, capo 2, 96")
        #expect(SongSummary.singerSubtitle(singer) == "Key A, 96")
        let lines = singer.sections.flatMap(\.items).compactMap { item -> String? in
            guard case let .lyrics(line) = item else { return nil }
            #expect(line.chords.isEmpty)
            return line.lyrics
        }
        #expect(lines == ["Tujh mein rab dikhta hai"])
        #expect(singer.diagrams.isEmpty)
    }

    @Test
    func `singer preview has its own free shortcut in the Song menu`() {
        let shortcut = MenuShortcuts.singerPreview
        #expect(shortcut.menu == "Song")
        #expect(shortcut.displayText == "⇧⌘Y")
        #expect(MenuShortcuts.all.filter { $0.shortcut == shortcut.shortcut }.count == 1)
    }
}
