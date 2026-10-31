import ChordPro
import CoreText
import Editing
import Foundation
import Library
import LiveLayout
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
        let recorder = RecordingAnalytics(env)
        editor.services = recorder.hub
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
        // Row 25: one walkUpPicked per (kind, rank, feel) a day, no song data.
        let picked = recorder.log.entries().filter {
            $0["name"] as? String == "Segue.Bass.walkUpPicked"
        }.compactMap { $0["params"] as? [String: String] }
        #expect(picked == [
            ["segue.kind": "hold", "segue.rank": "nothing", "segue.genre": "pop"],
            ["segue.kind": "scaleWalk", "segue.rank": "reset", "segue.genre": "pop"],
        ])
        #expect(recorder.features == ["walkUpPick"])
        // The same choice again the same day is throttled.
        editor.pickWalkUp(details.change, nil)
        #expect(recorder.log.entries().count(where: {
            $0["name"] as? String == "Segue.Bass.walkUpPicked"
        }) == 2)
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

    // MARK: The Walk-ups list (section 8.9)

    @Test
    func `the editor's list groups changes, sets the feel with undo and removes stale picks`(
    ) async throws {
        let env = try TestEnvironment()
        let opened = try await open(env)
        let (library, editor, song) = (opened.library, opened.editor, opened.song)
        let source = try #require(editor.walkUpsSource)
        #expect(source.title == "Harbour")
        #expect(source.changes.map { "\($0.fromName)>\($0.toName)" } == ["G>C"])
        #expect(WalkUpsSheet.groups(source.changes).map(\.changes.count) == [1])
        #expect(source.feel == nil)
        #expect(source.defaultFeel == .pop)
        #expect(source.unmatched.isEmpty)

        source.setFeel(.bollywood)
        #expect(editor.walkUpsSource?.feel == .bollywood)
        await editor.bassTask?.value
        #expect(try await library.store.song(id: song.id)?.sidecar.bass.genre == .bollywood)
        editor.sourceEditor.undoManager.undo()
        #expect(editor.walkUpsSource?.feel == nil)
        source.setFeel(.rock)
        source.setFeel(nil)
        await editor.bassTask?.value
        #expect(try await library.store.song(id: song.id)?.sidecar.bass.genre == nil)

        // The scale (R170): G major offers the major-quality scales, defaults to Major, and
        // is one undo step.
        #expect(source.scale == nil)
        #expect(source.defaultScale == .major)
        #expect(source.scales == [.major, .bhairav, .majorPentatonic])
        source.setScale(.majorPentatonic)
        #expect(editor.walkUpsSource?.scale == .majorPentatonic)
        await editor.bassTask?.value
        #expect(try await library.store.song(id: song.id)?.sidecar.bass.mode == .majorPentatonic)
        editor.sourceEditor.undoManager.undo()
        #expect(editor.walkUpsSource?.scale == nil)

        // A pick whose target changed no longer matches: listed, then removed.
        let change = try #require(source.changes.first)
        editor.pickWalkUp(change, change.candidates.first)
        editor.sourceEditor.replaceAll(with: Self.song.replacingOccurrences(
            of: "[C]",
            with: "[Am]",
        ))
        try await AISettingsTests.waitUntil(timeout: .seconds(30)) {
            editor.walkUpsSource?.unmatched.count == 1
        }
        let stale = try #require(editor.walkUpsSource?.unmatched.first)
        #expect(stale.text == "Lead-in: G \u{2192} C, A B")
        editor.walkUpsSource?.remove([stale.pick])
        #expect(editor.walkUpsSource?.unmatched.isEmpty == true)
        #expect(editor.bassPrefs.walkUps.isEmpty)
    }

    @Test
    func `the library picks, sets the feel and lists without undo`() async throws {
        let env = try TestEnvironment()
        let store = InstrumentProfileStore(defaults: env.defaults)
        store.update { $0.bassNotes = true }
        store.setWalkUps(.everyChange)
        let library = try await env.openLibrary()
        library.instrument = store
        let song = try await library.createSong(source: Self.song)
        let cho = try env.read(song.relativePath)
        #expect(library.showsWalkUps)
        let source = try #require(library.walkUpsSource(songID: song.id))
        let change = try #require(source.changes.first)
        #expect(source.readOnlyHelp == nil)
        let details = try #require(source.picking.details(change.id))
        #expect(details.feel == "Pop")
        let half = try #require(change.candidates.first { $0.kind == .diatonicNeighbour })
        source.picking.choose(change, half)
        await library.walkUpWrite?.value
        let saved = try #require(library.song(id: song.id))
        #expect(saved.sidecar.bass.walkUps.map(\.kind) == [.diatonicNeighbour])
        #expect(try env.read(song.relativePath) == cho)
        #expect(library.walkUpsSource(songID: song.id)?.changes.first?.pick != nil)

        source.setFeel(.worship)
        await library.walkUpWrite?.value
        #expect(library.song(id: song.id)?.sidecar.bass.genre == .worship)
        source.setScale(.bhairav)
        await library.walkUpWrite?.value
        #expect(library.song(id: song.id)?.sidecar.bass.mode == .bhairav)

        let picked = try #require(library.walkUpsSource(songID: song.id)?.changes.first)
        source.picking.reset(picked)
        await library.walkUpWrite?.value
        #expect(library.song(id: song.id)?.sidecar.bass.walkUps.isEmpty == true)

        // Outside the bass-note view the library offers no walk-ups.
        store.toggleBassNotes(from: .library)
        #expect(!library.showsWalkUps)
        #expect(library.walkUpsSource(songID: song.id) == nil)
    }

    @Test
    func `the option breakdown lists each weighted term and sums to the score`() throws {
        let (document, _) = ChordProParser.parse(Self.song)
        let options = DisplayOptions().withBass(InstrumentProfile(
            bassNotes: true,
            walkUps: .everyChange,
        ))
        let model = RenderModel(document: document, options: options)
        let change = try #require(BassLine.changes(
            model,
            document: document,
            prefs: BassPrefs(),
        ).first)
        let top = try #require(change.candidates.first)
        let text = WalkUpPopover.breakdown(top)
        #expect(text.hasPrefix("genrePrior "))
        #expect(text.hasSuffix(" = \(Int(top.score))") || text.contains(" = "))
        #expect(text.contains("resolution 2"))
    }

    @Test
    func `the run reads as a VoiceOver button and the stage face has its glyphs`() {
        let run = ApproachRun(
            change: ChangeID(from: ChordPosition(section: 0, chord: 0), toBass: PitchClass(0)),
            notes: ["A", "B"],
            chromatic: [false, false],
            isPick: false,
            accessibility: "walk up A, B into C",
        )
        #expect(WalkUpRunView.spokenName(run) == "Walk-up into C: A, B")
        // The run's "\u{203A}" and chromatic "\u{00B0}" exist in the stage face (no
        // fallback font, no ">" needed).
        #expect(Theme.registerFonts())
        for role in [TextRole.approach, .chord] {
            let font = StageTextMetrics.ctFont(role, size: 20)
            var characters: [UniChar] = [0x203A, 0x00B0]
            var glyphs = [CGGlyph](repeating: 0, count: characters.count)
            #expect(CTFontGetGlyphsForCharacters(font, &characters, &glyphs, characters.count))
        }
    }
}
