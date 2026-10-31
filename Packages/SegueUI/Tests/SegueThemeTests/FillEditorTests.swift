import Diagrams
import Editing
import Foundation
import Library
import MusicTheory
import Playback
@testable import SegueUI
import Services
import Testing

/// The fill editor (P8-7 sections 12.2-12.8, 15) through the real editor, library store and
/// sound session: candidates A-D plus More, hearing and A/B, the shared draft's edits and
/// undo in both views, the remembered view, the mini tab, Save, Revert, Delete, replacing an
/// overlapping fill, the gig gate and the analytics.
@MainActor
@Suite(.serialized)
struct FillEditorTests {
    @MainActor
    struct Opened {
        var base: ChordSpanSelectionTests.Opened
        var sheet: FillEditorModel

        var editor: SongEditorViewModel {
            base.editor
        }

        var draft: FillDraft {
            sheet.draft
        }

        var grid: FillGrid {
            sheet.grid
        }
    }

    /// The sheet over C -> D (verse into chorus).
    private func open(span: ClosedRange<Int> = 1 ... 2) async throws -> Opened {
        let base = try await ChordSpanSelectionTests.open()
        base.editor.refreshSpanSelection()
        base.editor.openFillEditor(span: span)
        let sheet = try #require(base.editor.fillEditor)
        return Opened(base: base, sheet: sheet)
    }

    private func run(_ opened: Opened, for seconds: Double) {
        for _ in 0 ..< Int((seconds * 10).rounded()) {
            opened.base.env.clock.advance(by: 0.1)
            opened.base.rig.session.player?.pump()
        }
    }

    private func bass(_ opened: Opened, from: TimeInterval = 0) -> [Int] {
        opened.base.rig.outputs.last?.played
            .filter { $0.event.voice == .bass && $0.at >= from - 1e-6 }
            .map { Int($0.event.note) } ?? []
    }

    private func phraseBass(_ opened: Opened, _ row: FillEditorModel.Row) throws -> [Int] {
        try #require(opened.sheet.phrase(for: row)).phrase.events
            .filter { $0.voice == .bass }.map { Int($0.note) }
    }

    @Test
    func `the sheet offers A-D and More with one corpus pattern each`() async throws {
        let opened = try await open()
        let sheet = opened.sheet
        #expect(sheet.candidates.count >= 4)
        #expect(sheet.rows == [.candidate(0), .candidate(1), .candidate(2), .candidate(3)])
        #expect(sheet.selected == .candidate(0))
        // R170: one candidate per corpus pattern family (rhythm families may repeat).
        let templates = sheet.candidates.map(\.template)
        #expect(Set(templates).count == templates.count)
        #expect(Set(sheet.rows.map { sheet.subtitle($0) }).count == sheet.rows.count)
        #expect(sheet.letter(.candidate(1)) == "B")
        #expect(!sheet.title(.candidate(0)).isEmpty)
        #expect(sheet.spanTitle.contains("\u{2192}"))
        #expect(sheet.tempoTitle == "90 BPM")
        if sheet.hasMore {
            sheet.select(letter: "e")
            #expect(sheet.showsMore)
            #expect(sheet.selected == .candidate(4))
            #expect(sheet.rows.count == 5)
        }
        #expect(sheet.spokenRow(.candidate(0)).hasPrefix("Option A, "))
        #expect(sheet.spokenRow(.candidate(0)).hasSuffix("suggested"))
        #expect(opened.base.recorder.features == ["fillEditor"])
    }

    @Test
    func `play schedules the row's phrase once and loops switch at the next wrap`()
        async throws
    {
        let opened = try await open()
        let sheet = opened.sheet
        let rowA = FillEditorModel.Row.candidate(0)
        let rowB = FillEditorModel.Row.candidate(1)
        sheet.setLooping(false)
        sheet.toggle(rowA)
        #expect(sheet.isSounding(rowA))
        run(opened, for: 12)
        #expect(try bass(opened) == phraseBass(opened, rowA))
        #expect(opened.base.rig.session.player?.isPlaying == false)
        #expect(opened.base.recorder.features.contains("fillAudition"))
        // Looping: B takes over at the next phrase start, A plays out its pass.
        sheet.setLooping(true)
        sheet.toggle(rowA)
        let length = try #require(sheet.phrase(for: rowA)).phrase.length
        run(opened, for: 0.5)
        sheet.select(rowB)
        #expect(sheet.isSounding(rowB))
        let wrap = opened.base.env.clock.now().timeIntervalSinceReferenceDate - 0.5 + length
        run(opened, for: length + 9)
        #expect(try Array(bass(opened, from: wrap).prefix(4)) == Array(phraseBass(opened, rowB)
                .prefix(4)))
        sheet.stop()
        #expect(opened.base.rig.session.player?.isPlaying == false)
    }

    @Test
    func `typed frets, plus and minus and R edit the grid at the cursor`() async throws {
        let opened = try await open()
        let sheet = opened.sheet
        sheet.select(.scratch)
        let draft = opened.draft
        let grid = opened.grid
        #expect(draft.events.isEmpty)
        // The A string (1) at the span's start: 7 -> E2 (40).
        draft.cursor = FillDraft.Cursor(tick: grid.region.lowerBound, string: 1)
        sheet.typeFret(7, at: 100)
        #expect(draft.notes.count == 1)
        #expect(grid.midi(of: draft.events[0]) == 40)
        #expect(draft.events[0].string == "A1")
        #expect(draft.events[0].len == 240)
        // "1" then "2" within 0.6 s is fret 12, one undo step.
        draft.moveCursor(by: 1, extending: false, rhythm: sheet.rhythm, on: grid)
        sheet.typeFret(1, at: 101)
        sheet.typeFret(2, at: 101.4)
        #expect(draft.notes.count == 2)
        #expect(grid.position(of: draft.events[1]) == FretPosition(string: 1, fret: 12))
        draft.undo()
        #expect(draft.notes.count == 1)
        draft.redo()
        // A second digit after 0.6 s is a new fret on the same note.
        sheet.typeFret(1, at: 110)
        sheet.typeFret(3, at: 111)
        #expect(grid.position(of: draft.events[1]) == FretPosition(string: 1, fret: 3))
        // + lengthens by one step, truncating nothing; - shortens; R rests.
        sheet.lengthen(by: 1, in: .fretboard)
        #expect(draft.events[1].len == 480)
        sheet.lengthen(by: -1, in: .fretboard)
        #expect(draft.events[1].len == 240)
        sheet.rest(in: .fretboard)
        #expect(draft.notes.count == 1)
        #expect(sheet.isEdited(.scratch))
    }

    @Test
    func `a neck click pins the selected note to that string`() async throws {
        let opened = try await open()
        let sheet = opened.sheet
        let draft = opened.draft
        let first = try #require(draft.ordered(on: opened.grid).first)
        draft.selection = [first.id]
        // The E string, fret 5: A1 (33) on the low string.
        sheet.placeOnNeck(string: 0, fret: 5)
        let note = try #require(draft.note(first.id))
        #expect(opened.grid.midi(of: note.event) == 33)
        #expect(note.event.string == "E1")
        #expect(opened.grid.position(of: note.event) == FretPosition(string: 0, fret: 5))
        #expect(sheet.isEdited(.candidate(0)))
    }

    @Test
    func `the piano roll adds, moves and resizes with the snaps and option bypasses them`()
        async throws
    {
        let opened = try await open()
        let sheet = opened.sheet
        sheet.select(.scratch)
        sheet.view = .pianoRoll
        let grid = opened.grid
        let draft = opened.draft
        let start = grid.region.lowerBound
        // Over C in G: C# (37) snaps to the scale (C or D, ties down: C 36).
        sheet.pitchSnap = .scale
        sheet.tapRoll(tick: start, midi: 37, note: nil, extending: false, bypass: false)
        #expect(grid.midi(of: draft.events[0]) == 36)
        // Option places it as is.
        sheet.tapRoll(tick: start + 480, midi: 37, note: nil, extending: false, bypass: true)
        #expect(grid.midi(of: draft.events[1]) == 37)
        // Chord tones: B (35) snaps to C (36).
        sheet.pitchSnap = .chordTones
        sheet.tapRoll(tick: start + 960, midi: 35, note: nil, extending: false, bypass: false)
        #expect(grid.midi(of: draft.events[2]) == 36)
        // Drag the first note right a beat and up a semitone (snapped to E, a chord tone):
        // the note it lands on is replaced (monophonic).
        let first = try #require(draft.ordered(on: grid).first)
        let drag = FillNoteDrag(
            hit: .init(id: first.id, edge: false),
            ids: [first.id],
            ticks: 480,
            moved: true,
        )
        sheet.finishRoll(drag, rawSemitones: 3, bypass: false)
        #expect(draft.notes.count == 2)
        let moved = try #require(draft.note(first.id))
        #expect(grid.tick(of: moved.event) == start + 480)
        #expect(grid.midi(of: moved.event) == 40)
        // Resize by its right edge.
        let resize = FillNoteDrag(
            hit: .init(id: first.id, edge: true),
            ids: [],
            resizing: first.id,
            ticks: 240,
            moved: true,
        )
        sheet.finishRoll(resize, rawSemitones: 0, bypass: false)
        #expect(draft.note(first.id)?.event.len == 480)
        // ⌥-drag copies.
        let copy = FillNoteDrag(
            hit: .init(id: first.id, edge: false),
            ids: [first.id],
            ticks: -480,
            copy: true,
            moved: true,
        )
        sheet.finishRoll(copy, rawSemitones: 0, bypass: true)
        #expect(draft.notes.count == 3)
        #expect(opened.base.recorder.features.contains("fillPianoRoll"))
    }

    @Test
    func `one undo stack and one selection across both views, and the view is remembered`()
        async throws
    {
        let opened = try await open()
        let sheet = opened.sheet
        let draft = opened.draft
        let grid = opened.grid
        #expect(sheet.view == .fretboard)
        let before = draft.events
        let first = try #require(draft.ordered(on: grid).first)
        draft.selection = [first.id]
        sheet.placeOnNeck(string: 1, fret: 9)
        sheet.view = .pianoRoll
        #expect(draft.selection == [first.id])
        sheet.transposeSelection(by: 1, octave: true)
        #expect(try grid.midi(of: #require(draft.note(first.id)).event) == 54)
        draft.undo()
        sheet.view = .fretboard
        draft.undo()
        #expect(draft.events == before)
        #expect(!sheet.isEdited(.candidate(0)))
        // A new sheet opens on the last view used (per user, never per song).
        sheet.view = .pianoRoll
        sheet.cancel()
        opened.editor.fillEditorClosed(sheet, forGig: false)
        opened.editor.openFillEditor(span: 0 ... 1)
        #expect(opened.editor.fillEditor?.view == .pianoRoll)
        #expect(opened.editor.instrument?.fillEditor.view == .pianoRoll)
    }
}

/// Saving, the mini tab, the gig gate and the vocabularies.
extension FillEditorTests {
    @Test
    func `the mini tab reads the draft and the landing root`() async throws {
        let opened = try await open()
        let sheet = opened.sheet
        #expect(!sheet.tabNotes.isEmpty)
        sheet.select(.scratch)
        let notes = sheet.tabNotes
        #expect(notes.count == 1)
        #expect(notes.last?.isLanding == true)
        #expect(notes.last?.name == "D")
        let spoken = TabLayout.spoken(notes, tuning: opened.grid.tuning)
        #expect(spoken.hasPrefix("Tab: "))
        #expect(spoken.hasSuffix("D"))
        let layout = TabLayout.layout(
            notes: notes,
            chords: sheet.tabChords,
            ticks: opened.grid.region,
            pulses: opened.grid.pulses,
            bars: opened.grid.bars.map(\.tick),
            tuning: opened.grid.tuning,
            width: 600,
            measure: { Double($0.count) * 6 },
        )
        #expect(layout.spoken == spoken)
        #expect(layout.chords.map(\.text) == ["C", "D"])
    }

    @Test
    func `save writes the sidecar's parts only, with the origin, and undo takes it back`()
        async throws
    {
        let opened = try await open()
        let sheet = opened.sheet
        let id = opened.base.song.id
        let library = opened.base.library
        let source = try #require(library.song(id: id)).source
        sheet.select(.candidate(1))
        let first = try #require(opened.draft.ordered(on: opened.grid).first)
        opened.draft.selection = [first.id]
        sheet.placeOnNeck(string: 2, fret: 2)
        sheet.name = "Into the chorus"
        sheet.passes = .last
        sheet.show = .tab
        sheet.save()
        #expect(sheet.isClosed)
        let part = try #require(opened.editor.parts.first)
        #expect(part.name == "Into the chorus")
        #expect(part.passes == .last)
        #expect(part.show == .tab)
        #expect(part.origin?.rank == .b)
        #expect(part.origin?.edited == true)
        #expect(part.origin?.family == sheet.candidates[1].family)
        try await AISettingsTests.waitUntil(timeout: .seconds(30)) {
            library.song(id: id)?.sidecar.parts == [part]
        }
        #expect(library.song(id: id)?.source == source)
        // Row 26.
        let saved = opened.base.recorder.log.entries()
            .compactMap { $0["params"] as? [String: String] }
            .first { $0["segue.family"] != nil }
        #expect(saved?["segue.rank"] == "b")
        #expect(saved?["segue.edited"] == "true")
        #expect(saved?["segue.view"] == "fretboard")
        #expect(saved?["segue.shows"] == "last")
        #expect(saved?["segue.chords"] == "2-4")
        // The fill covers its change: no walk-up shows on C -> D in that pass.
        try await AISettingsTests.waitUntil(timeout: .seconds(30)) {
            opened.editor.walkUpsSource?.changes.contains { $0.coveredBy == part.id } == true
        }
        // One undo step on the editor.
        opened.editor.sourceEditor.undoManager.undo()
        #expect(opened.editor.parts.isEmpty)
        try await AISettingsTests.waitUntil(timeout: .seconds(30)) {
            library.song(id: id)?.sidecar.parts.isEmpty == true
        }
    }

    @Test
    func `revert, delete and the replace prompt`() async throws {
        let opened = try await open()
        let sheet = opened.sheet
        let first = try #require(opened.draft.ordered(on: opened.grid).first)
        opened.draft.selection = [first.id]
        sheet.placeOnNeck(string: 0, fret: 3)
        #expect(sheet.isEdited(.candidate(0)))
        sheet.revert()
        #expect(!sheet.isEdited(.candidate(0)))
        sheet.save()
        let saved = try #require(opened.editor.parts.first)
        // A new fill over B ... C shares the change C -> D: Save asks to replace it.
        opened.editor.fillEditorClosed(sheet, forGig: false)
        opened.editor.openFillEditor(span: 0 ... 2)
        let other = try #require(opened.editor.fillEditor)
        other.save()
        #expect(other.confirmation == .replace([saved.name ?? "a fill"]))
        #expect(opened.editor.parts == [saved])
        other.confirmReplace()
        #expect(opened.editor.parts.count == 1)
        #expect(opened.editor.parts.first?.id != saved.id)
        // Delete Fill removes it.
        opened.editor.fillEditorClosed(other, forGig: false)
        opened.editor.openFillEditor(span: 0 ... 2)
        let editing = try #require(opened.editor.fillEditor)
        #expect(editing.editing != nil)
        editing.delete()
        #expect(opened.editor.parts.isEmpty)
    }

    @Test
    func `a gig turns sound off, closes the sheet and keeps its draft for the same span`()
        async throws
    {
        let opened = try await open()
        let sheet = opened.sheet
        let first = try #require(opened.draft.ordered(on: opened.grid).first)
        opened.draft.selection = [first.id]
        sheet.placeOnNeck(string: 0, fret: 3)
        sheet.toggle(.candidate(0))
        #expect(sheet.isSounding(.candidate(0)))
        opened.base.rig.session.stageChanged(kind: .gig)
        #expect(!sheet.canPlay)
        sheet.closeForGig()
        #expect(sheet.isClosed)
        opened.editor.fillEditorClosed(sheet, forGig: true)
        #expect(opened.editor.parts.isEmpty)
        // Nothing opens during the gig.
        opened.editor.openFillEditor(span: 1 ... 2)
        #expect(opened.editor.fillEditor == nil)
        opened.base.rig.session.stageChanged(kind: nil)
        opened.editor.openFillEditor(span: 1 ... 2)
        let again = try #require(opened.editor.fillEditor)
        #expect(again === sheet)
        #expect(again.isEdited(.candidate(0)))
    }

    @Test
    func `the analytics vocabularies mirror the fill model's`() {
        #expect(Set(FillSavedFamily.allCases.map(\.rawValue))
            == Set(FillFamily.allCases.map(\.rawValue) + ["scratch"]))
        #expect(Set(FillSavedRank.allCases.map(\.rawValue))
            == Set(CandidateRank.allCases.map(\.rawValue)))
        #expect(Set(WalkUpFeel.allCases.map(\.rawValue)) == Set(BassGenre.allCases.map(\.rawValue)))
    }
}
