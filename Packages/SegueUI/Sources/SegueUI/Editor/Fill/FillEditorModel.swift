// P8-7d (docs/phases/8-workstreams/P8-7-time-model-and-fills.md sections 12.2, 12.3, 12.7,
// 15, R166, R167 Q7, Q8, Q11, Q13). The fill sheet's model: the span, the generated
// candidates A-D plus More (and the saved fill when editing one), one draft per row with its
// own undo, hearing a row once or looping with A/B at the next phrase start, the footer's
// name, "Shows on" and "Show as", and Save, Revert and Delete. Saving writes the sidecar's
// `parts` only, never the `.cho`.

import Diagrams
import Editing
import Foundation
import Library
import MusicTheory
import Observation
import Playback
import Services
import SwiftUI

@MainActor
@Observable
final class FillEditorModel: Identifiable {
    /// A row of the candidates column.
    enum Row: Hashable {
        /// The fill being edited, as saved.
        case saved
        /// `Fill.candidates[index]`: A-D, then "More".
        case candidate(Int)
        /// "Start from scratch": an empty part.
        case scratch
    }

    /// What Save needs confirmed first.
    enum Confirmation: Equatable {
        /// "Replace 'Into last chorus'?": the span shares a change with other fills.
        case replace([String])
        case delete
    }

    @ObservationIgnored let host: FillHost
    /// The span, indices into the song's written-order timeline (start ... landing).
    let span: ClosedRange<Int>
    let anchor: SpanAnchor
    private(set) var song: FillSong
    private(set) var grid: FillGrid
    private(set) var candidates: [FillCandidate]
    /// The saved fill this sheet edits (nil for a new one).
    let editing: Part?
    private(set) var selected: Row
    /// "More" is open (shows the fifth candidate).
    var showsMore = false
    @ObservationIgnored private(set) var drafts: [Row: FillDraft] = [:]

    // Footer
    var name: String
    var passes: PassFilter
    var show: PartShow
    var confirmation: Confirmation?
    /// Set when the sheet should close (Save, Delete, Cancel, a gig starting).
    private(set) var isClosed = false
    /// It closed because a gig started (its drafts are kept).
    private(set) var closedForGig = false
    /// The sheet's chord lane: the song's play-along lane over the span's sections, the
    /// span selected (lengths and pushes edited there write the song's timing).
    @ObservationIgnored let lane: PlayAlong?

    // Editor controls
    var rhythm: FillRhythmSnap = .eighth
    var pitchSnap: FillPitchSnap = .scale
    /// The grid's blocks show note names instead of frets.
    var showsNames = false
    /// The views a note was edited in (row 26's `segue.view`).
    @ObservationIgnored private(set) var editedIn: Set<FillEditorView> = []
    @ObservationIgnored private var recordedPianoRoll = false

    /// Audition
    @ObservationIgnored let audition: FillAudition?
    /// Loop (default on in the sheet).
    var looping = true
    /// The sheet's Click toggle (default off).
    var click = false
    /// The session tempo: 50, 75 or 100% (never saved).
    var tempoFactor: Double = 1
    /// The row sounding now.
    var sounding: Row?
    /// The phrase the playhead follows.
    @ObservationIgnored var playing: FillAuditionPhrase?
    /// The generation of the player when this sheet started it.
    @ObservationIgnored var generation: Int?

    nonisolated var id: ObjectIdentifier {
        ObjectIdentifier(self)
    }

    /// The sheet for `span` of `song` (nil when the span cannot take a fill); `editing` the
    /// saved part on exactly that span, if any.
    init?(host: FillHost, song: FillSong, span: ClosedRange<Int>, editing: Part? = nil) {
        guard FillSpan.problem(timeline: song.timeline, chords: span) == nil,
              let anchor = song.anchor(span)
        else { return nil }
        self.host = host
        self.span = span
        self.anchor = anchor
        self.song = song
        self.editing = editing
        grid = Self.grid(song, span)
        let candidates = song.context(span).map { Fill.candidates($0) } ?? []
        self.candidates = candidates
        name = editing?.name ?? ""
        passes = editing?.passes ?? .all
        show = editing?.show ?? .names
        audition = host.sound.map { session in
            session.fillAudition(placement: { song.placement }, context: host.context)
        }
        lane = host.sound.map { session in
            PlayAlong(session: session, context: host.context, writeTiming: host.writeTiming)
        }
        selected = editing == nil ? (candidates.isEmpty ? .scratch : .candidate(0)) : .saved
        _ = draft(for: selected)
        updateLane()
    }

    /// The lane shows the passes the span plays in, the span selected.
    private func updateLane() {
        guard let lane else { return }
        let timeline = song.timeline
        let first = timeline.chords[span.lowerBound].pass
        let last = timeline.chords[span.upperBound].pass
        lane.update(song.playAlong)
        lane.setRange(first == last ? .section(first) : .from(first))
        let offset = timeline.chords.firstIndex { $0.pass >= first } ?? 0
        if lane.selected == nil {
            lane.select(span.lowerBound - offset, extending: false)
            lane.select(span.upperBound - offset, extending: true)
        }
    }

    private static func grid(_ song: FillSong, _ span: ClosedRange<Int>) -> FillGrid {
        FillGrid.make(
            timeline: song.timeline,
            span: span,
            transform: song.transform,
            tuning: song.placement.tuning,
            home: song.placement.home,
            mode: FillMode.resolved(
                song.prefs.mode,
                genre: song.genre,
                key: song.context(span)?.span.first?.key,
            ),
        )
    }

    /// The song changed under the sheet (a timing edit in its lane, a save elsewhere): the
    /// grid and the candidates follow; drafts keep their chord-relative notes.
    func update(_ song: FillSong) {
        guard FillSpan.problem(timeline: song.timeline, chords: span) == nil else { return }
        let grid = Self.grid(song, span)
        let candidates = song.context(span).map { Fill.candidates($0) } ?? []
        self.song = song
        updateLane()
        if grid != self.grid {
            self.grid = grid
        }
        if candidates != self.candidates {
            self.candidates = candidates
            for (row, draft) in drafts where !draft.isEdited {
                if case let .candidate(index) = row, candidates.indices.contains(index) {
                    drafts[row] = makeDraft(candidates[index].events)
                }
            }
        }
    }

    // MARK: Rows

    /// The rows shown: the saved fill first when editing, A-D, then E under "More".
    var rows: [Row] {
        let shown = showsMore ? candidates.count : min(candidates.count, 4)
        return (editing == nil ? [] : [.saved]) + (0 ..< shown).map { .candidate($0) }
    }

    /// Whether there is a fifth candidate for "More".
    var hasMore: Bool {
        candidates.count > 4
    }

    /// The row's events as loaded.
    func loaded(_ row: Row) -> [PartEvent] {
        switch row {
        case .saved: editing?.events ?? []
        case let .candidate(index):
            candidates.indices.contains(index) ? candidates[index].events : []
        case .scratch: []
        }
    }

    private func makeDraft(_ events: [PartEvent]) -> FillDraft {
        let draft = FillDraft(events: events)
        let first = events.min { grid.tick(of: $0) < grid.tick(of: $1) }
        draft.cursor = FillDraft.Cursor(
            tick: grid.region.lowerBound,
            string: first.flatMap { grid.position(of: $0)?.string } ?? 0,
        )
        draft.onChange = { [weak self, weak draft] in
            guard let self, let draft else { return }
            draftChanged(draft)
        }
        return draft
    }

    func draft(for row: Row) -> FillDraft {
        if let draft = drafts[row] {
            return draft
        }
        let draft = makeDraft(loaded(row))
        drafts[row] = draft
        return draft
    }

    /// The draft being edited: the selected row's.
    var draft: FillDraft {
        draft(for: selected)
    }

    /// Whether a row's draft was changed from what it loaded.
    func isEdited(_ row: Row) -> Bool {
        drafts[row]?.isEdited == true
    }

    /// Selects a row (click, ↑ / ↓, the letters). While a loop sounds, the row takes over
    /// at the next phrase start and VoiceOver hears "Now playing option C" once.
    func select(_ row: Row) {
        guard row != selected else { return }
        selected = row
        _ = draft
        guard looping, sounding != nil, let player = audition?.current(), player.isPlaying,
              player.isLooping, isOurs(player), let phrase = phrase(for: row)
        else { return }
        player.swapAtNextWrap(phrase.phrase)
        playing = phrase
        sounding = row
        audition?.played()
        AccessibilityNotification.Announcement("Now playing \(spokenName(row))").post()
    }

    /// ↑ / ↓ in the candidates column.
    func moveSelection(by step: Int) {
        let rows = rows + [.scratch]
        let index = rows.firstIndex(of: selected) ?? 0
        select(rows[min(max(index + step, 0), rows.count - 1)])
    }

    /// The letters A-E select their row (E opens "More").
    func select(letter: Character) {
        guard let ascii = letter.uppercased().first?.asciiValue, ascii >= 65 else { return }
        let index = Int(ascii) - 65
        guard candidates.indices.contains(index) else { return }
        if index >= 4 {
            showsMore = true
        }
        select(.candidate(index))
    }

    /// "Revert to A": the selected row's draft back to what it loaded (one undo step).
    func revert() {
        draft.revert()
    }

    // MARK: Views

    var view: FillEditorView {
        get { host.settings.view }
        set {
            host.settings.view = newValue
            if newValue == .pianoRoll, !recordedPianoRoll {
                recordedPianoRoll = true
                host.services.record(.featureUsed(.fillPianoRoll, host.context))
            }
        }
    }

    /// A note edit happened in `view` (row 26 records where).
    func noteEdited(in view: FillEditorView) {
        editedIn.insert(view)
    }

    // MARK: Save, Delete

    var canSave: Bool {
        song.canEdit && !draft.events.isEmpty
    }

    /// Why Save is unavailable.
    var saveHelp: String? {
        if !song.canEdit {
            return song.readOnlyHelp ?? "Save the song first"
        }
        return draft.events.isEmpty ? "Add a note to save the fill" : nil
    }

    /// Saved fills (other than the one being edited) sharing a change with the span.
    var overlapping: [Part] {
        song.resolved.overlapping(positions).filter { $0.id != editing?.id }
    }

    /// The part Save writes.
    var part: Part {
        let draft = draft
        let origin: PartOrigin? = switch selected {
        case .saved:
            editing?.origin.map { origin in
                var origin = origin
                origin.edited = origin.edited || draft.isEdited
                return origin
            }
        case let .candidate(index):
            candidates.indices.contains(index) ? candidates[index].family.map { family in
                PartOrigin(
                    family: family,
                    template: candidates[index].template,
                    rank: CandidateRank(index: index),
                    edited: draft.isEdited,
                )
            } : nil
        case .scratch: nil
        }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return Part(
            id: editing?.id ?? PartID(),
            name: trimmed.isEmpty ? nil : trimmed,
            span: anchor,
            passes: passes,
            show: show,
            origin: origin,
            events: draft.events,
        )
    }

    /// Return / Save: asks to replace overlapping fills first, else writes.
    func save() {
        guard canSave else { return }
        let overlaps = overlapping
        if !overlaps.isEmpty {
            confirmation = .replace(overlaps.map { $0.name ?? "a fill" })
            return
        }
        write(replacing: [])
    }

    /// "Replace" in the overlap confirmation.
    func confirmReplace() {
        confirmation = nil
        write(replacing: overlapping.map(\.id))
    }

    private func write(replacing: [PartID]) {
        let part = part
        var parts = song.parts.filter { !replacing.contains($0.id) }
        if let index = parts.firstIndex(where: { $0.id == part.id }) {
            parts[index] = part
        } else {
            parts.append(part)
        }
        host.writeParts(parts, editing == nil ? "Save Fill" : "Change Fill")
        host.services.record(.fillSaved(summary(for: part)))
        if !song.bassViewOn, !host.settings.bassViewNoteShown {
            host.settings.bassViewNoteShown = true
            host.showNote(Self.bassViewNote)
        }
        close()
    }

    /// Delete Fill (asks once): removes the saved fill.
    func delete() {
        guard let editing, song.canEdit else { return }
        confirmation = nil
        host.writeParts(song.parts.filter { $0.id != editing.id }, "Delete Fill")
        close()
    }

    /// Cancel or Esc: discards every draft.
    func cancel() {
        close()
    }

    private func close() {
        stop()
        lane?.stop()
        isClosed = true
    }

    /// A gig is starting: the sheet closes, its drafts kept for the next open of this span
    /// (never saved).
    func closeForGig() {
        closedForGig = true
        close()
    }

    /// Reopened after a gig closed it.
    func reopen() {
        isClosed = false
        closedForGig = false
    }
}
