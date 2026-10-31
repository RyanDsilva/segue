// P8-7d (docs/phases/8-workstreams/P8-7-time-model-and-fills.md sections 12.4, 12.5, 12.8). The
// gestures and keys of the fretboard + grid and the piano roll, as model calls (so they test
// in process): each one an edit of the shared draft, one undo step.

import Foundation
import Library
import MusicTheory

extension FillEditorModel {
    // MARK: Fretboard + grid

    /// A click on the neck: the selected note takes that position, pinned to that string;
    /// with nothing selected, a new note one step long at the cursor.
    func placeOnNeck(string: Int, fret: Int) {
        let tuning = grid.tuning
        guard tuning.strings.indices.contains(string) else { return }
        let midi = tuning.strings[string] + fret
        let pin = grid.pin(string: string)
        let draft = draft
        if let id = draft.selection.first, draft.selection.count == 1 {
            draft.setPitch(id, midi: midi, pin: pin, on: grid)
        } else {
            draft.add(tick: draft.cursor.tick, length: rhythm.ticks, midi: midi, pin: pin, on: grid)
        }
        draft.cursor.string = string
        noteEdited(in: .fretboard)
    }

    /// A click on the step grid: on a note selects it (⇧ adds it); on an empty cell moves the
    /// cursor there and adds a note on the chord's root at its suggested place.
    func tapGrid(tick: Int, string: Int, note: Int?, extending: Bool) {
        let draft = draft
        draft.cursor = FillDraft.Cursor(tick: tick, string: string)
        if let note {
            if extending {
                if draft.selection.contains(note) {
                    draft.selection.remove(note)
                } else {
                    draft.selection.insert(note)
                }
            } else {
                draft.selection = [note]
            }
            return
        }
        guard !extending else { return }
        let chord = grid.chord(atTick: tick)
        guard grid.chords.indices.contains(chord) else { return }
        let id = draft.add(
            tick: tick,
            length: rhythm.ticks,
            midi: grid.chords[chord].placed,
            on: grid,
        )
        if let position = draft.note(id).flatMap({ grid.position(of: $0.event) }) {
            draft.cursor.string = position.string
        }
        noteEdited(in: .fretboard)
    }

    /// A finished drag in either view: the notes moved (⌥: copied), or a note resized.
    func finish(_ drag: FillNoteDrag, view: FillEditorView) {
        let draft = draft
        if let id = drag.resizing, let note = draft.note(id) {
            draft.resize(id, length: max(rhythm.ticks, note.event.len + drag.ticks), on: grid)
        } else if !drag.ids.isEmpty {
            draft.move(
                drag.ids,
                ticks: drag.ticks,
                semitones: drag.semitones,
                copy: drag.copy,
                on: grid,
            )
        } else {
            return
        }
        noteEdited(in: view)
    }

    /// A typed digit on the grid (`at`: the key event's time, seconds).
    func typeFret(_ digit: Int, at time: TimeInterval) {
        draft.type(digit: digit, at: time, rhythm: rhythm, on: grid)
        noteEdited(in: .fretboard)
    }

    /// `+` / `-` on the grid or the roll.
    func lengthen(by steps: Int, in view: FillEditorView) {
        draft.lengthen(by: steps, step: rhythm.ticks, on: grid)
        noteEdited(in: view)
    }

    /// `R`, Delete: the selection (else the note at the cursor) becomes rest.
    func rest(in view: FillEditorView) {
        draft.delete(on: grid)
        noteEdited(in: view)
    }

    /// An articulation button or ⌥ key.
    func toggle(_ articulation: Articulation) {
        draft.toggle(articulation, on: grid)
        noteEdited(in: view)
    }

    /// Whether every selected note (else the one at the cursor) has `articulation`.
    func has(_ articulation: Articulation) -> Bool {
        let draft = draft
        let ids = draft.selection.isEmpty
            ? (draft.noteAtCursor(on: grid).map { [$0.id] } ?? []) : draft.selection
        return !ids.isEmpty && ids.allSatisfy {
            draft.note($0)?.event.articulations.contains(articulation) == true
        }
    }

    /// A note's spelled name in the draft (section 9.2).
    func name(of note: FillDraft.Note) -> String {
        let events = draft.events
        guard let index = events.firstIndex(of: note.event) else { return "" }
        return resolved(events).first { $0.event == index }?.name ?? ""
    }

    // MARK: The grid for VoiceOver

    private func note(startingAt tick: Int) -> FillDraft.Note? {
        draft.notes.first { grid.tick(of: $0.event) == tick }
    }

    private func note(covering tick: Int) -> FillDraft.Note? {
        draft.notes.first { note in
            let start = grid.tick(of: note.event)
            return (start ..< start + note.event.len).contains(tick)
        }
    }

    /// "Bar 2 beat 4 and, over E, F sharp, A string fret 9, eighth note, slide", "held F
    /// sharp" or "rest".
    func spokenStep(_ tick: Int) -> String {
        let position = grid.spokenPosition(tick, timeline: song.timeline)
        let chord = grid.chords.indices.contains(grid.chord(atTick: tick))
            ? grid.chords[grid.chord(atTick: tick)].name : ""
        var parts = [position, "over \(chord)"]
        if let note = note(startingAt: tick) {
            parts.append(BassLine.spokenNote(name(of: note)))
            if let place = grid.position(of: note.event) {
                parts.append("\(spokenString(place.string)) fret \(place.fret)")
            }
            parts.append(Self.spokenLength(note.event.len))
            parts += Articulation.allCases.filter(note.event.articulations.contains)
                .map(\.rawValue)
            if grid.isOutside(note.event) {
                parts.append("outside its chord")
            } else if grid.isFolded(note.event) {
                parts.append("moved an octave")
            }
        } else if let held = note(covering: tick) {
            parts.append("held \(BassLine.spokenNote(name(of: held)))")
        } else {
            parts.append("rest")
        }
        return parts.joined(separator: ", ")
    }

    /// "A string" (the open string's letter).
    func spokenString(_ string: Int) -> String {
        "\(BassLine.spokenNote(grid.tuning.openStringName(string))) string"
    }

    /// "eighth note", "dotted quarter note", "5 sixteenths".
    static func spokenLength(_ ticks: Int) -> String {
        let names = [
            120: "sixteenth note", 160: "triplet eighth", 240: "eighth note",
            320: "triplet quarter", 360: "dotted eighth", 480: "quarter note",
            720: "dotted quarter", 960: "half note", 1440: "dotted half", 1920: "whole note",
        ]
        if let name = names[ticks] {
            return name
        }
        return ticks.isMultiple(of: 120) ? "\(ticks / 120) sixteenths" : "\(ticks) ticks"
    }

    /// Increment / decrement on a step: its note's fret up or down on its string (a rest
    /// gets the chord's root).
    func adjustStep(_ tick: Int, up: Bool) {
        let draft = draft
        guard let note = note(startingAt: tick) else {
            draft.cursor.tick = tick
            tapGrid(tick: tick, string: draft.cursor.string, note: nil, extending: false)
            return
        }
        guard let place = grid.position(of: note.event) else { return }
        let fret = place.fret + (up ? 1 : -1)
        guard (0 ... 24).contains(fret) else { return }
        draft.setPitch(
            note.id,
            midi: grid.tuning.strings[place.string] + fret,
            pin: grid.pin(string: place.string),
            on: grid,
        )
        noteEdited(in: .fretboard)
    }

    func lengthenStep(_ tick: Int, by steps: Int) {
        guard let note = note(startingAt: tick) else { return }
        draft.selection = [note.id]
        lengthen(by: steps, in: .fretboard)
    }

    func restStep(_ tick: Int) {
        guard let note = note(covering: tick) else { return }
        draft.delete([note.id], on: grid)
        noteEdited(in: .fretboard)
    }

    /// "String up" / "String down": the same pitch on the neighbouring string.
    func moveStepString(_ tick: Int, by steps: Int) {
        guard let note = note(startingAt: tick), let place = grid.position(of: note.event)
        else { return }
        let target = place.string + steps
        guard grid.tuning.strings.indices.contains(target) else { return }
        let midi = grid.midi(of: note.event)
        guard (0 ... 24).contains(midi - grid.tuning.strings[target]) else { return }
        draft.setPitch(note.id, midi: midi, pin: grid.pin(string: target), on: grid)
        draft.cursor.string = target
        noteEdited(in: .fretboard)
    }

    // MARK: Piano roll

    /// A click in the roll: on a note selects it (⇧ adds); on an empty cell adds a note one
    /// step long, its pitch snapped unless `bypass` (⌥).
    func tapRoll(tick: Int, midi: Int, note: Int?, extending: Bool, bypass: Bool) {
        let draft = draft
        if let note {
            if extending {
                if draft.selection.contains(note) {
                    draft.selection.remove(note)
                } else {
                    draft.selection.insert(note)
                }
            } else {
                draft.selection = [note]
            }
            return
        }
        guard !extending, grid.rollRange.contains(midi) else { return }
        let pitch = bypass ? midi : grid.snapPitch(midi, pitchSnap, atTick: tick)
        draft.add(tick: tick, length: rhythm.ticks, midi: pitch, on: grid)
        draft.cursor.tick = tick
        noteEdited(in: .pianoRoll)
    }

    /// A finished drag in the roll: time snaps (the drag already did), pitch snaps on the
    /// grabbed note unless `bypass` (⌥, which also copies).
    func finishRoll(_ drag: FillNoteDrag, rawSemitones: Int, bypass: Bool) {
        var drag = drag
        if drag.resizing == nil, let hit = drag.hit, let note = draft.note(hit.id) {
            let from = grid.midi(of: note.event)
            let target = from + rawSemitones
            let tick = grid.tick(of: note.event) + drag.ticks
            let snapped = bypass ? target : grid.snapPitch(target, pitchSnap, atTick: tick)
            drag.semitones = min(max(snapped, grid.rollRange.lowerBound), grid.rollRange.upperBound)
                - from
        }
        finish(drag, view: .pianoRoll)
    }

    /// ↑ / ↓ in the roll (⇧: an octave).
    func transposeSelection(by direction: Int, octave: Bool) {
        draft.transpose(by: direction, octave: octave, snap: pitchSnap, on: grid)
        noteEdited(in: .pianoRoll)
    }

    /// ← / → in the roll: the selection by one step.
    func nudgeSelection(by steps: Int) {
        let draft = draft
        guard !draft.selection.isEmpty else { return }
        draft.move(draft.selection, ticks: steps * rhythm.ticks, semitones: 0, on: grid)
        noteEdited(in: .pianoRoll)
    }

    /// "F sharp 2, bar 2 beat 4 and, an eighth".
    func spokenRollNote(_ note: FillDraft.Note) -> String {
        let midi = grid.midi(of: note.event)
        let name = BassLine.spokenNote(name(of: note)) + " \(midi / 12 - 1)"
        let tick = grid.tick(of: note.event)
        var parts = [
            name,
            grid.spokenPosition(tick, timeline: song.timeline),
            Self.spokenLength(note.event.len),
        ]
        parts += Articulation.allCases.filter(note.event.articulations.contains).map(\.rawValue)
        if draft.selection.contains(note.id) {
            parts.append("selected")
        }
        return parts.joined(separator: ", ")
    }
}
