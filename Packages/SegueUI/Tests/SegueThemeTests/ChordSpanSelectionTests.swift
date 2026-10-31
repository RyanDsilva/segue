import Editing
import Foundation
import Library
import MusicTheory
import Playback
@testable import SegueUI
import Testing

/// Selecting a run of chords for a bass fill (P8-7 sections 10, 12.1, 12.8) through the real
/// editor and library: a click plays and anchors, a shift-click selects silently in either
/// direction and across a section boundary, the span's limits refuse with their reason, the
/// canvas, the lane and VoiceOver select the same way, and an exact saved span reads "Edit".
@MainActor
@Suite(.serialized)
struct ChordSpanSelectionTests {
    static let song = """
    {title: Harbour}
    {key: G}
    {tempo: 90}

    {start_of_verse}
    [G]Hello there [C]my friend
    {end_of_verse}

    {start_of_chorus}
    [D]Sing it [G]home
    {end_of_chorus}

    """

    struct Opened {
        var env: TestEnvironment
        var rig: SoundRig
        var library: LibraryViewModel
        var editor: SongEditorViewModel
        var song: SongRecord
        var recorder: RecordingAnalytics
    }

    static func open(_ source: String = song) async throws -> Opened {
        let env = try TestEnvironment()
        let recorder = RecordingAnalytics(env)
        let rig = SoundRig(env, services: recorder.hub)
        let store = InstrumentProfileStore(defaults: env.defaults)
        store.update { $0.bassNotes = true }
        store.setWalkUps(.everyChange)
        let library = try await env.openLibrary()
        library.instrument = store
        library.sound = rig.session
        library.services = recorder.hub
        let song = try await library.createSong(source: source)
        library.beginEditing(song)
        let editor = try #require(library.editor)
        try await AISettingsTests.waitUntil(timeout: .seconds(30)) { editor.renderModel != nil }
        return Opened(
            env: env,
            rig: rig,
            library: library,
            editor: editor,
            song: song,
            recorder: recorder,
        )
    }

    /// The chord units of the rendered preview: (line, chord) in written order.
    static func units(_ model: RenderModel?) -> [(BlockPath, RenderChord)] {
        model?.sections.flatMap(\.items).flatMap { item -> [(BlockPath, RenderChord)] in
            guard case let .lyrics(line) = item else { return [] }
            return line.chords.filter { $0.kind == .chord }.map { (line.path, $0) }
        } ?? []
    }

    @Test
    func `a click plays and anchors, a shift-click selects silently across sections`()
        async throws
    {
        let opened = try await Self.open()
        let actions = opened.editor.chordSpanActions
        let units = Self.units(opened.editor.renderModel)
        #expect(units.count == 4)
        // A plain click on C: anchored (not a span yet); the caller plays it.
        #expect(!actions.click(line: units[1].0, chord: units[1].1, extending: false))
        #expect(opened.editor.spanSelection.anchor == 1)
        #expect(opened.editor.spanSelection.span == nil)
        let made = opened.rig.outputs.made
        // Shift-click on D in the chorus: the span C ... D, nothing sounds.
        #expect(actions.click(line: units[2].0, chord: units[2].1, extending: true))
        #expect(opened.editor.spanSelection.span == 1 ... 2)
        #expect(opened.editor.spanSelection.problem == nil)
        #expect(opened.rig.outputs.made == made)
        #expect(opened.editor.spanSelection.place(of: 2).map { [$0.place, $0.count] } == [2, 2])
        #expect(opened.editor.spanSelection.actionTitle == "Create Bass Fill\u{2026}")
        // Shift-click again moves the landing; either direction.
        actions.click(line: units[0].0, chord: units[0].1, extending: true)
        #expect(opened.editor.spanSelection.span == 0 ... 1)
        #expect(opened.editor.spanSelection.isLanding(1))
        // Esc / a click on empty space.
        opened.editor.spanSelection.clear()
        #expect(opened.editor.spanSelection.span == nil)
        // With no anchor, shift-click alone anchors.
        actions.click(line: units[3].0, chord: units[3].1, extending: true)
        #expect(opened.editor.spanSelection.anchor == 3)
        #expect(opened.editor.spanSelection.span == nil)
    }

    @Test
    func `an edit clears the span and a timing change keeps it`() async throws {
        let opened = try await Self.open()
        opened.editor.refreshSpanSelection()
        opened.editor.spanSelection.select(0 ... 2)
        opened.editor.changeTiming("Change Chord Length") { _ in }
        #expect(opened.editor.spanSelection.span == 0 ... 2)
        opened.editor.sourceTextDidChange(Self.song.replacingOccurrences(of: "[C]", with: "[Am]"))
        try await AISettingsTests.waitUntil(timeout: .seconds(30)) {
            opened.editor.spanSelection.span == nil
        }
    }

    @Test(arguments: [
        ("[G]a [C]b [N.C.]c [D]d", 0 ... 2, "A fill can't cross N.C."),
        (
            "[G]a [C]b [D]c [Em]d [C]e [G]f [D]g [Em]h [C]i [G]j",
            0 ... 9,
            "A fill covers at most 9 chords",
        ),
    ])
    func `spans past the limits are refused with the reason`(
        body: String,
        span: ClosedRange<Int>,
        reason: String,
    ) async throws {
        let opened = try await Self.open("{title: Limits}\n{key: G}\n\n\(body)\n")
        opened.editor.refreshSpanSelection()
        let selection = opened.editor.spanSelection
        let first = try #require(selection.timeline.chords.indices.first)
        // Spans are chord indices in the timeline; N.C. is a timed silence there.
        let last = min(span.upperBound, selection.timeline.chords.count - 1)
        selection.select(first ... last)
        #expect(selection.problem?.reason == reason)
        opened.editor.openFillEditor(span: first ... last)
        #expect(opened.editor.fillEditor == nil)
    }

    @Test
    func `a span over eight bars is refused`() async throws {
        let opened = try await Self
            .open("{title: Long}\n{key: G}\n\n[G]a [C]b [D]c [Em]d [C]e [G]f\n")
        // Two bars a chord: five departing chords are ten bars.
        opened.editor.changeTiming("Change Timing") { $0.rule = .each(.twoBars) }
        try await AISettingsTests.waitUntil(timeout: .seconds(30)) {
            opened.editor.fillSong?.timeline.chords.first?.length == 3840
        }
        opened.editor.refreshSpanSelection()
        opened.editor.spanSelection.select(0 ... 5)
        #expect(opened.editor.spanSelection.problem?.reason == "A fill covers at most 8 bars")
        opened.editor.spanSelection.select(0 ... 4)
        #expect(opened.editor.spanSelection.problem == nil)
    }

    @Test
    func `the canvas shift-click and VoiceOver's start and end actions select the same span`()
        async throws
    {
        let opened = try await Self.open()
        let units = Self.units(opened.editor.renderModel)
        opened.editor.anchorFillSpan(line: units[1].0, offset: units[1].1.offset)
        opened.editor.extendFillSpan(line: units[3].0, offset: units[3].1.offset)
        #expect(opened.editor.spanSelection.span == 1 ... 3)
        #expect(opened.editor.isInFillSpan(line: units[2].0, offset: units[2].1.offset))
        #expect(!opened.editor.isInFillSpan(line: units[0].0, offset: units[0].1.offset))
        // VoiceOver: "Start fill at G", then "End fill at C".
        let selection = opened.editor.spanSelection
        selection.clear()
        selection.start(at: 0)
        selection.finish(at: 1)
        #expect(selection.span == 0 ... 1)
        // Moving the start keeps the landing.
        selection.start(at: 2)
        #expect(selection.span == 1 ... 2)
    }

    @Test
    func `an exact saved span reads Edit Bass Fill and opens on the saved fill`() async throws {
        let opened = try await Self.open()
        opened.editor.refreshSpanSelection()
        opened.editor.openFillEditor(span: 1 ... 2)
        let sheet = try #require(opened.editor.fillEditor)
        sheet.save()
        #expect(opened.editor.parts.count == 1)
        opened.editor.refreshSpanSelection()
        opened.editor.spanSelection.select(1 ... 2)
        #expect(opened.editor.spanSelection.actionTitle == "Edit Bass Fill\u{2026}")
        opened.editor.fillEditorClosed(sheet, forGig: false)
        opened.editor.openFillEditor(span: 1 ... 2)
        let again = try #require(opened.editor.fillEditor)
        #expect(again.editing?.id == opened.editor.parts.first?.id)
        #expect(again.selected == .saved)
        #expect(again.rows.first == .saved)
    }

    @Test
    func `the lane's shift-click span maps to the song's chords`() async throws {
        let opened = try await Self.open()
        let lane = try #require(opened.editor.playAlong)
        lane.update(opened.editor.playAlongSource)
        lane.setRange(.section(1))
        lane.select(0, extending: false)
        lane.select(1, extending: true)
        // The chorus's D and G are chords 2 and 3 of the written song.
        #expect(lane.fillSpan == 2 ... 3)
        #expect(lane.fillSpanProblem == nil)
        opened.editor.refreshSpanSelection()
        #expect(opened.editor.canCreateFill)
        opened.editor.createFillFromMenu()
        #expect(opened.editor.fillEditor?.span == 2 ... 3)
    }

    @Test
    func `the library preview selects a span and opens the sheet on it`() async throws {
        let opened = try await Self.open()
        opened.library.closeEditor()
        let record = try #require(opened.library.song(id: opened.song.id))
        let render = SongSummary.renderModel(record, bass: opened.library.instrument?.bassView)
        let actions = opened.library.chordSpanActions(record, render: render)
        let units = Self.units(render)
        actions.click(line: units[0].0, chord: units[0].1, extending: false)
        actions.click(line: units[1].0, chord: units[1].1, extending: true)
        #expect(opened.library.spanSelection.span == 0 ... 1)
        #expect(opened.library.canCreateFill)
        actions.openSpan()
        let sheet = try #require(opened.library.fillEditor)
        #expect(sheet.span == 0 ... 1)
        #expect(opened.recorder.features.contains("fillEditor"))
    }
}
