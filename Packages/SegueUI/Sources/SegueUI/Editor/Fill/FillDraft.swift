// P8-7d (docs/phases/8-workstreams/P8-7-time-model-and-fills.md sections 12.4, 12.5). The fill
// being edited: one `[PartEvent]` draft shared by the fretboard + grid and the piano roll,
// one selection (kept across the view toggle), one sheet-local undo stack (every gesture one
// step), and the grid's step cursor. Monophonic: a new or longer note truncates the one it
// overlaps.

import Foundation
import Library
import MusicTheory
import Observation

@MainActor
@Observable
final class FillDraft {
    /// One note with a stable identity for selection.
    struct Note: Identifiable, Hashable {
        var id: Int
        var event: PartEvent
    }

    /// The grid's step cursor: a step column (its start tick) and a string.
    struct Cursor: Equatable {
        var tick: Int
        var string: Int
    }

    private struct Snapshot: Equatable {
        var notes: [Note]
        var selection: Set<Int>
    }

    private(set) var notes: [Note]
    var selection: Set<Int> = []
    var cursor = Cursor(tick: 0, string: 0)
    /// The events as loaded (a candidate's, the saved fill's): what "Edited" and Revert
    /// compare against.
    private(set) var original: [PartEvent]
    private var undoStack: [Snapshot] = []
    private var redoStack: [Snapshot] = []
    @ObservationIgnored private var nextID = 0
    /// The first digit of a fret being typed, its note and when (a second digit within 0.6 s
    /// makes 10-15).
    @ObservationIgnored private var typing: Typing?

    /// A fret digit typed on a note at a time.
    private struct Typing {
        var note: Int
        var digit: Int
        var at: TimeInterval
    }

    /// Called after every change (a looping audition swaps the edit in at the next wrap).
    @ObservationIgnored var onChange: (@MainActor () -> Void)?

    static let twoDigitWindow: TimeInterval = 0.6

    init(events: [PartEvent]) {
        original = events
        notes = []
        notes = events.map(makeNote)
    }

    private func makeNote(_ event: PartEvent) -> Note {
        defer { nextID += 1 }
        return Note(id: nextID, event: event)
    }

    /// The events in time order.
    var events: [PartEvent] {
        notes.map(\.event).sorted { lhs, rhs in
            lhs.chord != rhs.chord ? lhs.chord < rhs.chord : lhs.at < rhs.at
        }
    }

    /// Changed from what was loaded.
    var isEdited: Bool {
        Set(events) != Set(original)
    }

    var canUndo: Bool {
        !undoStack.isEmpty
    }

    var canRedo: Bool {
        !redoStack.isEmpty
    }

    func note(_ id: Int) -> Note? {
        notes.first { $0.id == id }
    }

    /// The notes in time order on `grid`.
    func ordered(on grid: FillGrid) -> [Note] {
        notes.sorted { grid.tick(of: $0.event) < grid.tick(of: $1.event) }
    }

    // MARK: Undo

    private var snapshot: Snapshot {
        Snapshot(notes: notes, selection: selection)
    }

    /// Runs `change` as one undo step (nothing when it changed nothing).
    private func edit(_ change: () -> Void) {
        let before = snapshot
        change()
        guard snapshot.notes != before.notes else {
            return
        }
        undoStack.append(before)
        redoStack.removeAll()
        typing = nil
        onChange?()
    }

    func undo() {
        guard let last = undoStack.popLast() else { return }
        redoStack.append(snapshot)
        notes = last.notes
        selection = last.selection.filter { id in last.notes.contains { $0.id == id } }
        typing = nil
        onChange?()
    }

    func redo() {
        guard let next = redoStack.popLast() else { return }
        undoStack.append(snapshot)
        notes = next.notes
        selection = next.selection
        typing = nil
        onChange?()
    }

    /// Back to the events as loaded (undoable).
    func revert() {
        edit {
            notes = original.map(makeNote)
            selection = []
        }
    }

    // MARK: Editing

    /// Adds a note and selects it; it truncates whatever it overlaps.
    @discardableResult
    func add(tick: Int, length: Int, midi: Int, pin: String? = nil, on grid: FillGrid) -> Int {
        var added = 0
        edit {
            let note = makeNote(grid.event(tick: tick, length: length, midi: midi, pin: pin))
            notes.append(note)
            added = note.id
            truncate(around: note.id, on: grid)
            selection = [note.id]
        }
        return added
    }

    /// Note `id` sounds `midi` (a neck click or typed fret pins it to `pin`'s string; nil
    /// keeps no pin).
    func setPitch(_ id: Int, midi: Int, pin: String?, on grid: FillGrid) {
        edit {
            guard let index = notes.firstIndex(where: { $0.id == id }) else { return }
            let event = notes[index].event
            notes[index].event = grid.event(
                tick: grid.tick(of: event),
                length: event.len,
                midi: midi,
                pin: pin,
                like: event,
            )
        }
    }

    /// The selected notes move by `ticks` and `semitones` (⌥: copies stay behind).
    func move(_ ids: Set<Int>, ticks: Int, semitones: Int, copy: Bool = false, on grid: FillGrid) {
        guard ticks != 0 || semitones != 0 || copy else { return }
        edit {
            var moved: Set<Int> = []
            for id in ids {
                guard let index = notes.firstIndex(where: { $0.id == id }) else { continue }
                let event = notes[index].event
                let start = grid.tick(of: event) + ticks
                guard grid.region.contains(start) else { continue }
                let shifted = grid.event(
                    tick: start,
                    length: event.len,
                    midi: grid.midi(of: event) + semitones,
                    pin: semitones == 0 ? event.string : nil,
                    like: event,
                )
                if copy {
                    let note = makeNote(shifted)
                    notes.append(note)
                    moved.insert(note.id)
                } else {
                    notes[index].event = shifted
                    moved.insert(id)
                }
            }
            for id in moved {
                truncate(around: id, on: grid)
            }
            selection = moved.filter { id in notes.contains { $0.id == id } }
        }
    }

    /// Note `id` lasts `length` ticks (at least one).
    func resize(_ id: Int, length: Int, on grid: FillGrid) {
        edit {
            guard let index = notes.firstIndex(where: { $0.id == id }) else { return }
            let start = grid.tick(of: notes[index].event)
            notes[index].event.len = max(1, min(length, grid.region.upperBound - start))
            truncate(around: id, on: grid)
        }
    }

    /// `+` / `-`: the selected notes (else the note at the cursor) by one step.
    func lengthen(by steps: Int, step: Int, on grid: FillGrid) {
        let ids = targets(on: grid)
        guard !ids.isEmpty else { return }
        edit {
            for id in ids {
                guard let index = notes.firstIndex(where: { $0.id == id }) else { continue }
                let start = grid.tick(of: notes[index].event)
                let length = notes[index].event.len + steps * step
                notes[index].event.len = max(
                    min(step, notes[index].event.len),
                    min(length, grid.region.upperBound - start),
                )
                truncate(around: id, on: grid)
            }
        }
    }

    /// Delete, or `R` on the grid: the selection (else the note at the cursor) becomes rest.
    func delete(_ ids: Set<Int>? = nil, on grid: FillGrid) {
        let ids = ids ?? targets(on: grid)
        guard !ids.isEmpty else { return }
        edit {
            notes.removeAll { ids.contains($0.id) }
            selection.subtract(ids)
        }
    }

    /// An articulation button: on for every target unless all have it (then off).
    func toggle(_ articulation: Articulation, on grid: FillGrid) {
        let ids = targets(on: grid)
        guard !ids.isEmpty else { return }
        let allHave = ids.allSatisfy {
            note($0)?.event.articulations.contains(articulation) == true
        }
        edit {
            for index in notes.indices where ids.contains(notes[index].id) {
                if allHave {
                    notes[index].event.articulations.remove(articulation)
                } else {
                    notes[index].event.articulations.insert(articulation)
                    // A note is either a ghost or accented, never both.
                    if articulation == .ghost {
                        notes[index].event.articulations.remove(.accent)
                    } else if articulation == .accent {
                        notes[index].event.articulations.remove(.ghost)
                    }
                }
            }
        }
    }

    /// ↑ / ↓ in the piano roll: the selection by the pitch snap's next step (⇧: an octave).
    func transpose(by direction: Int, octave: Bool, snap: FillPitchSnap, on grid: FillGrid) {
        guard !selection.isEmpty else { return }
        edit {
            for index in notes.indices where selection.contains(notes[index].id) {
                let event = notes[index].event
                let tick = grid.tick(of: event)
                let midi = grid.midi(of: event)
                let next = octave ? midi + 12 * direction
                    : grid.step(midi, by: direction, snap, atTick: tick)
                guard grid.rollRange.contains(next), next != midi else { continue }
                notes[index].event = grid.event(
                    tick: tick,
                    length: event.len,
                    midi: next,
                    like: event,
                )
            }
        }
    }

    func selectAll() {
        selection = Set(notes.map(\.id))
    }

    // MARK: Monophony

    /// Other notes overlapping note `id`: one ringing into it is cut at its start, one
    /// starting inside it is removed.
    private func truncate(around id: Int, on grid: FillGrid) {
        guard let note = note(id) else { return }
        let start = grid.tick(of: note.event)
        let end = start + note.event.len
        var removed: Set<Int> = []
        for index in notes.indices where notes[index].id != id {
            let other = notes[index].event
            let otherStart = grid.tick(of: other)
            let otherEnd = otherStart + other.len
            if otherStart < start, otherEnd > start {
                notes[index].event.len = start - otherStart
            } else if otherStart >= start, otherStart < end {
                removed.insert(notes[index].id)
            }
        }
        notes.removeAll { removed.contains($0.id) }
        selection.subtract(removed)
    }
}

// MARK: - The grid's keys

extension FillDraft {
    /// The note sounding at the cursor's tick.
    func noteAtCursor(on grid: FillGrid) -> Note? {
        notes.first { note in
            let start = grid.tick(of: note.event)
            return (start ..< start + note.event.len).contains(cursor.tick)
        }
    }

    /// The selection, else the note at the cursor.
    private func targets(on grid: FillGrid) -> Set<Int> {
        if !selection.isEmpty {
            return selection
        }
        return noteAtCursor(on: grid).map { [$0.id] } ?? []
    }

    /// ← / →: the cursor by one step (⇧ extends the selection over the notes it passes).
    func moveCursor(by steps: Int, extending: Bool, rhythm: FillRhythmSnap, on grid: FillGrid) {
        let columns = grid.columns(rhythm)
        guard !columns.isEmpty else { return }
        let current = columns.lastIndex { $0 <= cursor.tick } ?? 0
        let next = min(max(current + steps, 0), columns.count - 1)
        cursor.tick = columns[next]
        typing = nil
        let here = noteAtCursor(on: grid)
        if extending {
            if let here {
                selection.insert(here.id)
            }
        } else {
            selection = here.map { [$0.id] } ?? []
            if let here, let string = grid.position(of: here.event)?.string {
                cursor.string = string
            }
        }
    }

    /// ↑ / ↓: the cursor string (up is the higher string).
    func moveString(by steps: Int, on grid: FillGrid) {
        cursor.string = min(max(cursor.string + steps, 0), max(0, grid.tuning.strings.count - 1))
        typing = nil
    }

    /// A digit typed on the grid: that fret on the cursor string at the cursor, a new note
    /// one step long when there is none; a second digit within 0.6 s makes 10-15. The pitch
    /// snap never applies to a typed fret.
    func type(digit: Int, at time: TimeInterval, rhythm: FillRhythmSnap, on grid: FillGrid) {
        guard (0 ... 9).contains(digit), grid.tuning.strings.indices.contains(cursor.string)
        else { return }
        let open = grid.tuning.strings[cursor.string]
        let pin = grid.pin(string: cursor.string)
        if let typing, time - typing.at <= Self.twoDigitWindow, typing.digit == 1,
           digit <= 5, note(typing.note) != nil
        {
            // The second digit replaces the first in the same undo step.
            let id = typing.note
            if let index = notes.firstIndex(where: { $0.id == id }) {
                let event = notes[index].event
                notes[index].event = grid.event(
                    tick: grid.tick(of: event),
                    length: event.len,
                    midi: open + 10 + digit,
                    pin: pin,
                    like: event,
                )
                onChange?()
            }
            self.typing = nil
            return
        }
        let id: Int
        if let here = noteAtCursor(on: grid) {
            setPitch(here.id, midi: open + digit, pin: pin, on: grid)
            id = here.id
            selection = [id]
        } else {
            id = add(
                tick: cursor.tick,
                length: rhythm.ticks,
                midi: open + digit,
                pin: pin,
                on: grid,
            )
        }
        typing = Typing(note: id, digit: digit, at: time)
    }
}
